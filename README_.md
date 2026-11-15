# Contoso Finance Report – Power BI portfolio project

A finance and controlling report for **Contoso**, a fictional consumer electronics retailer selling through physical stores and an online shop in 8 countries. Built end to end – from SQL views and messy source files to a star-schema model, DAX and a three-page report – as a portfolio project for a move from finance into data analytics / BI.

**https://app.powerbi.com/view?r=eyJrIjoiNmI3MGE1NDAtODczNC00MGViLWEyZmYtNDYwN2E1MjU3NmVhIiwidCI6Ijc1YzJlNGQ0LWQwNGMtNGNlOS1hMGVhLWM5NzViZGM0MTdlYiIsImMiOjF9** (Publish to web, no sign-in needed)

![Executive overview](Docs/img/executive-overview.png)

| Budget vs actual | Receivables |
|---|---|
| ![Budget vs actual](Docs/img/budget-vs-actual.png) | ![Receivables](Docs/img/receivables.png) |

---

## Business questions

The report is written for a CFO, financial controllers and country managers. It answers:

- **How are we doing vs last year?** Net sales, gross margin, orders and units vs prior year; a price / volume / mix bridge; results by country.
- **Where and why are we missing the budget?** Variance by country, category and month; units and average selling price vs budget.
- **Are customers paying on time?** Receivables balance, overdue share, aging, DSO, the largest overdue customers and payments that could not be matched to an invoice.

## Key findings (2025)

- Net sales **$299.9M, −7.7% vs 2024**; gross margin % stable at 56.0%.
- **−13.7% vs budget.** Units are 5.4% below budget and the average selling price 8.8% below – most of the gap is price, not volume. The United States accounts for about 91% of the variance.
- Receivables **+17.8% year on year despite lower sales**; 45% of the balance is overdue and DSO rose from 53 to 60 days.
- The largest overdue balances mix two cases: recent invoices a few weeks past due (collection follow-up) and items unpaid for about a year or more (write-off review).

*All figures come from synthetic data – see [Data](#data).*

## Architecture

```
SQL Server views (schema pbi) ──┐
Excel budget file ──────────────┤
24 bank statement CSVs ─────────┼─► Power Query ─► star-schema model ─► DAX ─► report (PBIP + Git)
NBP exchange rate API ──────────┘
```

- **SQL** – profiling and data quality checks, a `pbi` view layer, budget generation and payment generation.
- **Power Query** – cleaning of the budget workbook and bank statements, NBP API calls through a custom function, staging queries with load disabled.
- **Model** – facts: Sales, Budget, Invoices, Payments, ExchangeRate; dimensions: Date, Customer, Product, Store; shared dimensions Country, Channel and Category connect actuals with budget.
- **DAX** – calculation groups (Comparison: AC / PY / Δ PY; Period View: Month / YTD / Full Year), a field parameter, semi-additive balance measures, aging through a disconnected table, DSO.

## Highlights

- **Bank statements with real-life problems.** 24 monthly CSV files in two formats (header rows and a footer total in the old one; semicolons, decimal commas and renamed columns in the new one), overlapping periods with **2,759 duplicate payments**, and invoice numbers written in **5 different formats** in the payment description. Combined in Power Query, deduplicated and matched to invoices; **328 payments** stay unapplied and are shown separately.
- **Budget workbook built for people, not machines.** Header rows, months in columns, grouping cells filled only once, subtotals, different category names, numbers stored as text – cleaned with one reusable function applied to every sheet.
- **Receivables as balances at a date.** Open and overdue balances, aging buckets, DSO and Average Days Delinquent are calculated for any month end, not as sums of a period.
- **Comparisons in one place.** Prior-year logic lives in a calculation group, so every measure gets PY, Δ PY and Δ PY % without duplicated code; differences stay blank when there is no prior year to compare with.
- **Exchange rates from the National Bank of Poland API**, with the rule "rate from the last business day before the transaction".

## Key design decisions

1. **One view layer in SQL (`pbi` schema)** – Power BI reads only from views, never from raw tables.
2. **Payments enter the model only through CSV files**, like a real bank export – they are generated in SQL but not read from the database.
3. **Unapplied payments do not close invoices** – they are reported separately instead of being guessed.
4. **Receivables are balances, not flows** – every receivables measure is calculated at the balance date (end of the selected month).
5. **DSO is based on the last three months** (average month-end balance ÷ invoices × days) and is blank when fewer than three months of data exist.
6. **Budget is compared through shared dimensions** (country, channel, category, date), not through the sales dimensions.
7. **Visuals tell the business story; data limitations are documented, not shown** – regularities that come from the data generator are described here and on the About page.

## Data

| Source | What it is |
|---|---|
| Sales | [Contoso Data Generator V2](https://www.sqlbi.com/tools/contoso-data-generator/) by SQLBI – SQL Server database, 1M orders, 2016–2025 |
| Budget 2024–2025 | generated in SQL from prior-year actuals and growth assumptions, delivered as an Excel file with formatting issues |
| Invoices | one invoice per order (2024–2025), payment terms 30 days (France and Italy 60) |
| Payments | generated in SQL (60% on time … 2% never paid), delivered as 24 monthly bank statement CSV files |
| USD/PLN rates | National Bank of Poland web API |

**All data is fictional.** Budget, invoices and payments were generated for this project, so some indicators are more regular than in a real company. Assumptions: every sale is invoiced, one payment per invoice, no partial payments, data as of 31 Dec 2025.

## Repository structure

```
SQL/      00 profiling · 01 data quality checks · 02 pbi views · 03 budget generation · 04 payments generation
PBI/      Power BI project (PBIP: report + semantic model in TMDL)
Data/     Budget/ – budget workbook · Payments/ – 24 bank statements
          payments_clean.csv – clean payment export (answer key)
          _generator/ – Python script that turns the clean export into bank statements
Docs/     screenshots
```

## How to run it

1. Restore the Contoso V2 database (1M orders) on SQL Server as `Contoso V2 1M`.
2. Run `SQL/02_pbi_views.sql`. Scripts `00` and `01` are optional (profiling and checks).
3. *(Optional – the generated files are already in `Data/`)* Run `03_budget_generation.sql` and `04_payments_generation.sql`; export the payments result to `Data/payments_clean.csv` and run
   `python Data/_generator/make_bank_statements.py Data/payments_clean.csv Data/Payments` (requires pandas).
4. Open `PBI/PortfolioProject.pbip` in Power BI Desktop and update:
   - parameters `pBudgetFilePath` and `pPaymentsFolderPath`,
   - the SQL Server name in the source step of the SQL queries.
5. Refresh.

## How this project was built

I used Claude (Anthropic) to draft the documentation, keep track of data limitations, design decisions, data quality issues tracking and reviewing my SQL, DAX and Power Query queries/code. I wrote the SQL, DAX and Power Query myself, with the exception of the Python script that generates the bank statements. The About page and this README were drafted with Claude and reviewed and edited by me.

## Roadmap

- Stores & LFL page – like-for-like sales of comparable stores
- IBCS-style sales bridge
- DirectQuery version on Azure SQL with aggregations and row-level security
- Full data quality log and design decision record in `Docs/`

---

**Author:** Wojciech Możdżeń · www.linkedin.com/in/wojciech-możdżeń-5920111bb
