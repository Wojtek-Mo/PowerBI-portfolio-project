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