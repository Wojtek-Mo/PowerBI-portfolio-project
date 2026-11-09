--=====================
--Creating a pbi schema
--=====================
USE [Contoso V2 1M]

GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'pbi')
	EXEC('CREATE SCHEMA pbi');
GO

SELECT name 
FROM sys.schemas
WHERE name = 'pbi';

GO

--dimProduct view

CREATE OR ALTER VIEW pbi.DimProduct AS

	SELECT
		ProductKey,
		Brand,
		ProductName,
		CategoryKey,
		CategoryName,
		SubCategoryKey,
		SubCategoryName
	FROM Data.Product

GO

SELECT *
FROM pbi.DimProduct;

GO

--dimCustomer view

CREATE OR ALTER VIEW pbi.DimCustomer AS

	SELECT
		CustomerKey,
		CONCAT(GivenName,' ',Surname) CustomerName,
		Continent,
		Country CountryCode,
		CountryFull CountryName,
		State,
		City
	FROM Data.Customer

GO

SELECT *
FROM pbi.DimCustomer;

GO

--dimStore view

CREATE OR ALTER VIEW pbi.DimStore AS 

	SELECT
		StoreKey,
		StoreCode,
		CountryCode,
		CountryName,
		State,
		OpenDate,
		CloseDate,
		Description,
		SquareMeters,
		CASE
			WHEN CountryName = 'Online' THEN 'Online' ELSE 'Store' END SalesChannel,
		CASE 
			WHEN CloseDate IS NULL THEN 'Open'
			WHEN CloseDate IS NOT NULL AND Status = 'Restructured' THEN 'Restructured'
			ELSE 'Closed' END Status
	FROM Data.Store

GO

SELECT
	Status,
	COUNT(*) CountStores
FROM pbi.DimStore
GROUP BY Status;

GO

--FactSales view

CREATE OR ALTER VIEW pbi.FactSales AS

	SELECT
		OrderKey,
		LineNumber,
		CustomerKey,
		StoreKey,
		ProductKey,
		OrderDate,
		DeliveryDate,
		Quantity,
		UnitPrice,
		NetPrice,
		UnitCost,
		CurrencyCode,
		ExchangeRate
	FROM Data.Sales

GO

SELECT *
FROM pbi.FactSales

GO

--DimDate view

CREATE OR ALTER VIEW pbi.DimDate AS

	SELECT
		[Date],
		[Quarter],
		YearQuarter,
		YearQuarterNumber,
		YearMonthShort,
		YearMonthNumber,
		[Year],
		[Month],
		MonthShort,
		MonthNumber,
		DayOfWeekShort,
		DayOfWeekNumber,
		CASE WHEN [Year] = 2016 THEN 'Partial Year' ELSE 'Full Year' END FullYearFlag
	FROM Data.Date
	WHERE [Date] BETWEEN '2016-01-01' AND '2025-12-31'

GO


SELECT *
FROM pbi.DimDate;


--===============================================
--Creating additional views for helper dimensions
--===============================================

GO

CREATE OR ALTER VIEW pbi.DimCountry AS

	SELECT 
		DISTINCT CountryName
	FROM pbi.DimCustomer

GO

CREATE OR ALTER VIEW pbi.DimChannel AS

	SELECT
		DISTINCT SalesChannel
	FROM pbi.DimStore

GO

CREATE OR ALTER VIEW pbi.DimCategory AS

	SELECT
		DISTINCT CategoryName
	FROM pbi.DimProduct

GO

SELECT *
FROM pbi.DimCategory

SELECT *
FROM pbi.DimChannel

SELECT *
FROM pbi.DimCountry;

GO
--==================================================
--Creating FactPayments view for payments generation
--==================================================

--Setting up payment terms for each country and creating invoices table wit due dates

CREATE OR ALTER VIEW pbi.FactInvoices AS 

WITH PaymentTerms (Country, DaysNo) AS (
	
	SELECT *
	FROM
		(VALUES
			('United States', 30),
			('Canada', 30),
			('Australia', 30),
			('United Kingdom', 30),
			('Germany', 30),
			('Netherlands', 30),
			('France', 60),
			('Italy', 60)
			) v (Country, DaysNo)
),

OrderTotals AS (
	
	SELECT
		OrderKey,
		CustomerKey,
		OrderDate InvoiceDate,
		SUM(NetPrice * Quantity) InvoiceAmount
	FROM pbi.FactSales
	WHERE
		OrderDate BETWEEN '2024-01-01' AND '2025-12-31'
	GROUP BY 
		OrderKey,
		CustomerKey,
		OrderDate
),

Invoices AS (

	SELECT
		ot.OrderKey,
		ot.CustomerKey,
		dc.CountryName,
		ot.InvoiceDate,
		DATEADD(Day, pt.DaysNo, ot.InvoiceDate) DueDate,
		ot.InvoiceAmount
	FROM OrderTotals ot
	LEFT JOIN pbi.DimCustomer dc
	ON ot.CustomerKey = dc.CustomerKey
	LEFT JOIN PaymentTerms pt
	ON dc.CountryName = pt.Country
)

SELECT
	OrderKey,
	CustomerKey,
	InvoiceDate,
	DueDate,
	InvoiceAmount
FROM Invoices;

GO


--Testing invoices table 

 SELECT DISTINCT
	COUNT(*) [RowCount],
	COUNT(OrderKey) OrderKeyCount,
	SUM(InvoiceAmount) TotalInvoiceAmount,
	SUM (CASE WHEN DueDate IS NULL THEN 1 ELSE 0 END) MissingDueDate
FROM pbi.FactInvoices; 


SELECT
	COUNT(DISTINCT OrderKey) OrderKeyCountReference
FROM pbi.FactSales
WHERE OrderDate BETWEEN '2024-01-01' AND '2025-12-31';

SELECT
	fi.OrderKey,
	dc.CountryName,
	fi.InvoiceDate,
	fi.DueDate,
	DATEDIFF(Day, fi.InvoiceDate, fi.DueDate) NumberOfDays
FROM pbi.FactInvoices fi
LEFT JOIN pbi.DimCustomer dc
ON fi.CustomerKey = dc.CustomerKey
WHERE 
	(DATEDIFF(Day, InvoiceDate, DueDate) <> 60
	AND CountryName IN ('Italy', 'France'))
	OR
	(DATEDIFF(Day, InvoiceDate, DueDate) <> 30
	AND CountryName NOT IN ('Italy', 'France'));