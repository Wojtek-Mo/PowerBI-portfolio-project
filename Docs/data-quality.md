# Data Quality Log

This log records what was checked in the source data, what was found, and how each finding is handled in the project.

Source: Contoso Data Generator V2 (SQLBI), ready-made SQL Server database, 1M orders, restored locally as `Contoso V2 1M`.

Scripts: `sql/00_data_profiling.sql`, `sql/01_data_quality_checks.sql` (in progress).

## Baseline row counts

Used as a reference point for validation in Power Query and the model.

| Table | Rows |
|---|---|
| Data.Sales | 2,349,091 |
| Data.OrderRows | 2,349,091 |
| Data.Orders | 980,666 |
| Data.CurrencyExchange | 100,450 |
| Data.Customer | 86,908 |
| Data.Product | 2,517 |
| Data.Date | 4,018 |
| Data.Store | 74 |

## Findings

| ID | Area | Finding | How detected | Impact | Resolution | Status |
|---|---|---|---|---|---|---|
| DQ-01 | Sales | `Sales` has the same row count as `OrderRows`. `Sales` is a flattened version of `Orders` (header) + `OrderRows` (lines). | Row count comparison | None. Confirms the two structures are consistent. | `Sales` is used as the sales fact table. `Orders` is used later to generate payments (order level). | Confirmed |
| DQ-02 | Dates | Sales start on 2016-05-18 and end on 2025-12-31 (3,515 calendar days). 2016 is a partial year. | `MIN` / `MAX` of `OrderDate` | YoY 2017 vs 2016 would be overstated. | Date table covers full years 2016–2025. 2016 is flagged as partial in the report. Like-for-like analysis starts from 2018 vs 2017. Reporting cut-off date: 2025-12-31. | Decided |
| DQ-03 | Currency | All amounts in `Sales` (`UnitPrice`, `NetPrice`, `UnitCost`) are in USD. `CurrencyCode` is the transaction currency, `ExchangeRate` converts USD to that currency (always 1 for USD). | Average unit price per product compared across currencies: prices are nearly identical regardless of `CurrencyCode`. | Amounts can be summed across currencies. Local-currency amounts must not be summed across currencies. | Base measures in USD. PLN = USD amount × NBP USD/PLN rate of the order date. Local currency = USD amount × `ExchangeRate`. | Confirmed |
| DQ-04 | Currency | 5 currencies: USD (~51% of sales rows), EUR (~22%), CAD (~11%), GBP (~10%), AUD (~6%). All are available in NBP table A. | Distinct currencies in `CurrencyExchange` and `Sales` | Defines which NBP rates are needed. | NBP rates downloaded for the sales period (with a few days of buffer before 2016-05-18). | Confirmed |
| DQ-05 | Store | Online store: `StoreKey` 999999, `StoreCode` -1, `CountryName` 'Online'. Filtering on `CountryCode <> 'Online'` did not exclude it. | Store queries | Online store is not a physical location. | Excluded from like-for-like and geographic analyses, or shown separately. Filtered by `StoreKey`. | Decided |
| DQ-06 | Store | Empty `Status` means an open store. One store has an empty `Status` but a `CloseDate` of 2019-11-03 (within the sales period). It has no successor with the same `StoreCode`, so it is a regular closure with a missing status. StoreKey: 630. | `COUNT(*)` vs `COUNT(CloseDate)` grouped by `Status` | The raw `Status` column is inconsistent with `CloseDate`. | Derived status in the SQL layer: no `CloseDate` → Open; `CloseDate` and Status 'Restructured' → Restructured; any other `CloseDate` → Closed. Rule: the close date decides whether a store is active. The raw column is not loaded to the model. | Decided |
| DQ-07 | Store | `StoreCode` is not unique: 6 codes have more than one `StoreKey` (13 keys, i.e. 7 extra keys = 7 stores with Status 'Restructured'). A restructuring closes the old key and reopens the same physical store under a new key after 95–308 days. Store 7 was restructured twice. | `COUNT(*) OVER (PARTITION BY StoreCode)` and `LAG(CloseDate)` | `StoreCode` identifies the physical store, `StoreKey` identifies a version of it (SCD Type 2 pattern). | `StoreKey` is the relationship key. `StoreCode` is kept for reporting at physical-store level. Only one restructuring falls inside the sales period (store 7: closed 2018-02-02, reopened 2018-06-02); it is excluded from like-for-like 2018 vs 2017 and 2019 vs 2018. | Confirmed |
| DQ-08 | Store | Store openings and closings happen between 2013 and 2019. From 2020 onwards the store base is stable. | `MIN` / `MAX` of `OpenDate` and `CloseDate` by `Status` | Like-for-like differs from total sales mainly in 2017–2020. | Like-for-like shown as a trend for the whole period. | Confirmed |
| DQ-09 | Store / Sales | No sales before a store's `OpenDate` and no sales after its `CloseDate`. Stores closed before the sales period (StoreKey 30, 70, 110) have no sales at all. Restructured store 72 sells until its close date (2018-02-02) and its successor 74 starts selling on its open date (2018-06-02). | First and last `OrderDate` per store compared with `OpenDate` / `CloseDate` (flags) | None. Sales are consistent with store activity periods. | No action needed. Check kept in `01_data_quality_checks.sql`. | Confirmed |
| DQ-10 | Store / Currency | Each physical store country uses exactly one currency (Australia: AUD, Canada: CAD, United Kingdom: GBP, United States: USD, France / Germany / Italy / Netherlands: EUR). The online store sells in all 5 currencies, so for online sales the currency depends on the customer, not the store. The online store accounts for about 973k of 2.35M sales rows (~41%) and 38.96% of net sales value. | Store country × `CurrencyCode` from `Sales` | Store country alone cannot be used for sales geography or RLS: ~41% of sales would fall under "Online". Like-for-like covers only physical stores (~59% of sales rows). | Confirmed by customer country × `CurrencyCode` for all sales: each customer country has exactly one currency, and customer country covers 100% of sales rows. `CurrencyCode` is determined by the customer's country (customers of physical stores buy in their own country). Decision: sales geography and RLS based on customer country; online store treated as a separate sales channel (`Channel` attribute: Store / Online). Customer country is stored as a code (NL, US, GB, …), store country as code and name; country naming to be unified in the SQL layer. | Confirmed |
| DQ-11 | Customer | Every customer in `Customer` (86,908) has at least one order. Customers come from 8 countries (the same as physical store countries): US ~44%, GB ~14%, CA, DE and AU ~9–10% each, NL, IT and FR ~4–5% each. | Customers per country vs distinct customers in `Orders` (`LEFT JOIN`) | No inactive customers, which is a characteristic of synthetic data (customers are generated together with their orders). Inactive-customer analysis is not meaningful; new vs returning customers still is. Each country has enough customers for an RLS demo. | No action needed. Limitation described in the documentation. | Confirmed |
| DQ-12 | Product | 2,517 products in 8 categories and 32 subcategories. The hierarchy is consistent: no subcategory key belongs to more than one category key (control test with `>= 1` returned all 32 subcategories). Every product has been sold at least once. Categories are uneven in size (Home Appliances and Computers over 600 products each, Music, Movies and Audio Books 90 products in one subcategory). Some names are inconsistent in style (e.g. "MP4&MP3", "Cell phones Accessories"). | Category / subcategory counts; `COUNT(DISTINCT CategoryKey)` per `SubCategoryKey` with `HAVING > 1`; anti-join `Product` → `Sales` | Hierarchy can be used for drill-down, a snowflake branch and category-level budget. Name styles must be matched exactly when mapping budget categories from Excel. | Source names kept unchanged. Budget mapped to categories via a mapping table. | Confirmed |

## Planned checks (`01_data_quality_checks.sql`)

- Missing keys and amounts in `Sales`.
- Duplicate keys in dimensions and duplicate `OrderKey` + `LineNumber` in `Sales`.
- Orphan records: sales without a matching customer, product or store.
- Invalid values: quantity or prices ≤ 0, `NetPrice` higher than `UnitPrice`, exchange rate ≤ 0, exchange rate ≠ 1 for USD.
- Date logic: delivery before order, sales before store opening or after store closing.
- Consistency: row count and total quantity in `Sales` vs `OrderRows`.
