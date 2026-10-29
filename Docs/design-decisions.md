# Design Decisions

This document records the key decisions made in the project and the reasons behind them. Data findings that led to some of these decisions are described in [data-quality.md](data-quality.md).

## 1. Environment and publishing

| ID | Decision | Reason |
|---|---|---|
| DD-01 | The project is built locally on SQL Server Express 2022. The database is moved to a free Azure SQL Database only at the publishing stage. | No compute limits during development. The free Azure SQL tier has a monthly compute limit and pauses when idle, which suits a finished model better than daily development. |
| DD-02 | Two report versions: (1) workspace version with DirectQuery to Azure SQL, aggregations and RLS; (2) public version in Import mode, published with Publish to web from My Workspace. | Publish to web does not support RLS or DirectQuery. Publishing from My Workspace keeps the public link working after the Power BI Pro trial ends. |
| DD-03 | Everything that depends on the Power BI Service (workspace, DirectQuery, RLS, incremental refresh) is documented with screenshots and video before the Pro trial ends. | After the trial, workspace content is no longer accessible, and recruiters cannot access the workspace version anyway. |
| DD-04 | The Power BI project is saved in PBIP format (PBIR report, TMDL model) and versioned in Git. | Model and report become readable text files, so changes are visible in the commit history. |
| DD-05 | The Contoso `.bak` file is not stored in the repository. | Too large for GitHub and publicly available from the source. The documentation states where the data comes from. |

## 2. Data source and model

| ID | Decision | Reason |
|---|---|---|
| DD-06 | Source data: Contoso Data Generator V2 (SQLBI), ready-made SQL Server database with 1M orders. | Large enough for aggregations and performance comparisons to be meaningful, small enough for SQL Server Express (10 GB) and the Power BI model (1 GB). |
| DD-07 | `Data.Sales` is the sales fact table. `Orders` is used later to generate payments. | `Sales` is the flattened version of `Orders` + `OrderRows`. Payments relate to whole orders, so the order header is the right grain for them. |
| DD-08 | Power BI reads from a dedicated SQL layer (views or CTAS tables), not from the raw Contoso tables. | Column selection, derived columns and cleaning rules live in one place, close to the source. The choice between views and CTAS tables is still open. |
| DD-09 | Planned model: facts Sales, Budget (Excel), Payments (CSV folder), Sales aggregation table, NBP exchange rates (Web API); dimensions Date, Customer, Product (optional snowflake: Subcategory, Category), Store. | Covers the requirements: sales and margin, budget vs actual, receivables / DSO, multi-currency, five types of data sources. |
| DD-10 | `Data.CurrencyExchange` is not used. | Local-currency amounts come from `ExchangeRate` in `Sales`, PLN amounts from NBP rates. |

## 3. Measures and currency methodology

| ID | Decision | Reason |
|---|---|---|
| DD-11 | Measure definitions: net sales = `NetPrice × Quantity`; gross sales = `UnitPrice × Quantity`; discount = gross − net; cost = `UnitCost × Quantity`; margin = net sales − cost. All base amounts in USD. | `NetPrice` is the unit price after discount. The same net sales definition is used by SQLBI for Contoso. |
| DD-12 | The report shows USD by default, with a currency switch USD / PLN. | Contoso is an international group whose group currency is USD. PLN makes the report easier to read for a Polish audience. |
| DD-13 | PLN is always calculated from USD: USD amount × NBP USD/PLN rate. Local currency is always calculated from Contoso: USD amount × `ExchangeRate`. The two paths are never mixed. | Contoso's `ExchangeRate` is transactional data (the rate at which the customer actually paid). The NBP rate is a presentation rate. Converting a EUR sale via NBP EUR/PLN would give a different PLN value than via USD/PLN, so one sale could have two PLN values. |
| DD-14 | Local-currency amounts are shown only when filtered to a single currency. | Amounts in different currencies cannot be summed. |
| DD-15 | Currency (`CurrencyCode`) is kept as an attribute to show the revenue structure by currency (FX exposure). | Low effort, useful business information. |
| DD-16 | NBP rate rule: *to be decided* (rate of the transaction date or of the last business day before the transaction date, common in Polish accounting). | — |

## 4. NBP exchange rates (Power Query)

| ID | Decision | Reason |
|---|---|---|
| DD-17 | Only the USD rate is downloaded, but the query is a custom function with the currency code as a parameter. | Only USD is needed for PLN conversion. Adding another currency takes minutes. |
| DD-18 | Rates are downloaded per calendar quarter (max 92 days) for 2016-05-10 to 2025-12-31. | The NBP API allows at most 93 days per request and requires HTTPS. A few days of buffer before the first sale (2016-05-18) guarantee a rate for the first sales day. |
| DD-19 | The request is built with `Web.Contents` and the `RelativePath` and `Query` options. | Power BI Service cannot refresh queries with dynamically concatenated URLs. |
| DD-20 | Missing rates for weekends and holidays are filled with the last available rate. Helper queries are not loaded to the model. | NBP publishes rates only on business days, while sales happen every day. |

## 5. Date table and time scope

| ID | Decision | Reason |
|---|---|---|
| DD-21 | One date table, built in the SQL layer (not in DAX or Power Query). | In the composite model the date table must work in Dual mode, which requires a DirectQuery-capable source. A DAX or Power Query-generated table can only be Import, which would create limited relationships with the DirectQuery fact table. One table also means one source of truth. |
| DD-22 | The date table covers full years 2016–2025. 2016 is flagged as a partial year. | Sales run from 2016-05-18 to 2025-12-31. |
| DD-23 | The model contains the full history. Report pages open on 2025 vs 2024 by default, with older years available through filters. | Recent period is what a manager looks at; full history enables trends, incremental refresh and like-for-like analysis. |
| DD-24 | Budget is generated only for 2024 and 2025. | Budgets are prepared for the current year; a decade of budgets would be unrealistic. |
| DD-25 | Reporting cut-off date: 2025-12-31. | Orders from late December are still unpaid on that date, which gives a realistic receivables balance. |

## 6. Stores, geography and like-for-like

| ID | Decision | Reason |
|---|---|---|
| DD-26 | `StoreKey` is the relationship key; `StoreCode` identifies the physical store. | A restructuring creates a new `StoreKey` for the same `StoreCode` (see DQ-07). |
| DD-27 | Derived store status in the SQL layer: no `CloseDate` → Open; `CloseDate` and Status 'Restructured' → Restructured; any other `CloseDate` → Closed. The close date decides whether a store is active. | The raw `Status` column is inconsistent for one store (see DQ-06). |
| DD-28 | The online store is a separate sales channel (`Channel`: Store / Online). | It is not a physical location and accounts for ~39% of net sales. |
| DD-29 | Sales geography and RLS are based on customer country. Country names are unified across Customer and Store in the SQL layer. | Customer country covers 100% of sales; store country would put ~39% of sales under "Online" (see DQ-10). |
| DD-30 | Like-for-like (LFL) rules: a store is LFL for a year if it was open for the whole year and the whole previous year; the LFL store set is defined separately for each year-over-year comparison; the online store is excluded; LFL starts with 2018 vs 2017. Restructured stores are excluded automatically, because neither the old nor the new `StoreKey` is open for two full years around the change. | Standard retail practice. 2016 is a partial year. |
| DD-31 | LFL is shown as a trend for the whole period. | Store openings and closings happen in 2016–2019; from about 2021 LFL and total sales converge, which is itself an insight. |

## 7. Data quality and cleaning

| ID | Decision | Reason |
|---|---|---|
| DD-32 | Data is cleaned only where there is a real need. Where data is clean, quality checks prove it. | Cleaning clean data for show is not credible. |
| DD-33 | Quality issues in the generated budget (Excel) and payment extracts (CSV) are simulated and described as such. | Reflects typical real-life problems with manual and bank files, while staying transparent. |
| DD-34 | Quality checks cover only columns that are used in the model, relationships, filters or business rules. | Checking unused columns adds no value. |

## 8. Report and documentation

| ID | Decision | Reason |
|---|---|---|
| DD-35 | The report has an "About this report" page: purpose, navigation, data sources, key measures with business logic, model diagram, links to detailed documentation on GitHub. | Recruiters are more likely to open the report than the repository. |
| DD-36 | The README states that Claude was used as a mentor and code reviewer, while all SQL, DAX and Power Query code was written by the author. | Transparency about AI use. |

## Open questions

- SQL layer: views or CTAS tables refreshed by a stored procedure.
- NBP rate rule (DD-16).
- Constant-currency analysis: possible extension, not decided.
