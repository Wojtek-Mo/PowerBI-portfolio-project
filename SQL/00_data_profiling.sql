--======================
--Initial data profiling
--======================


--==================================
--1.Colum names and data types check
--==================================

SELECT
	TABLE_NAME,
	COLUMN_NAME,
	DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'Data'
ORDER BY TABLE_NAME, ORDINAL_POSITION;

--===================
--2. Table Rows Count
--===================

SELECT
	'Sales' AS TableName,
	COUNT(*) AS RowsCount
FROM Data.Sales

UNION ALL

SELECT
	'Currency Exchange',
	COUNT(*) AS RowsCountCurrencyExchange
FROM Data.CurrencyExchange

UNION ALL

SELECT
	'Customer',
	COUNT(*) AS RowsCountCustomer
FROM Data.Customer

UNION ALL

SELECT
	'Date',
	COUNT(*) AS RowsCountDate
FROM Data.[Date]

UNION ALL

SELECT
	'OrderRows',
	COUNT(*) AS RowsCountOrderRows
FROM Data.OrderRows

UNION ALL

SELECT
	'Orders',
	COUNT(*) AS RowsCountOrders
FROM Data.Orders

UNION ALL

SELECT
	'Product',
	COUNT(*) AS RowsCountProduct
FROM Data.Product

UNION ALL

SELECT 
	'Store',
	COUNT(*) RowsCountStore
FROM Data.Store;

--Count for Sales table and OrderRows table is the same, they match and are both more granular version of Orders table, broken down by LineItems

--=========================================
--3. Date range check for custom date table
--=========================================

SELECT
	MIN(OrderDate) AS FirstDate,
	MAX (OrderDate) AS LastDate,
	DATEDIFF(Day, MIN(OrderDate), MAX(OrderDate)) + 1 SpanInDays --Added +1 to cover for the last day
FROM Data.Orders;

--Date range is 2016-05-18 to 2025-12-31 so 3515 days

--===========================================================
--4. Distinct Currencies check and Sales Table currency check
--===========================================================

SELECT
	CurrencyCode,
	COUNT(*) AS RowsCount,
	MIN(ExchangeRate) AS MinRate,
	MAX(ExchangeRate) AS MaxRate
FROM Data.Sales
GROUP BY CurrencyCode
ORDER BY RowsCount DESC;


SELECT
	ProductKey,
	CurrencyCode,
	AVG(UnitPrice) AvgUnitPrice,
	AVG(NetPrice) AvgNetPrice,
	AVG(UnitCost) AvgUnitCost
FROM Data.Sales
GROUP BY ProductKey, CurrencyCode
ORDER BY ProductKey, CurrencyCode;

--Despite the currency code attribute in each row the avg values match between currencies, hence Sales tables is in USD entirely.

--=====================================================
--5. Store table exploration for like-for-like analisys
--=====================================================

--5.1 Working out the online storekey and its share in total sales

SELECT *
FROM Data.Store
WHERE CountryName = 'Online';



DECLARE @OnlineStoreKey INT = (
    SELECT StoreKey
    FROM Data.Store
    WHERE CountryName = 'Online'
);

WITH OnlineSalesShare AS (
    SELECT
        SUM(NetPrice * Quantity) AS TotalSales,
        (
            SELECT SUM(NetPrice * Quantity)
            FROM Data.Sales
            WHERE StoreKey = @OnlineStoreKey
        ) AS TotalOnlineSales
    FROM Data.Sales
)
SELECT
    ROUND(TotalSales, 2) AS TotalSales,
    ROUND(TotalOnlineSales, 2) AS TotalOnlineSales,
    ROUND(CAST(TotalOnlineSales AS FLOAT) / TotalSales * 100, 2) AS OnlineSharePct
FROM OnlineSalesShare;

--Online storekey 999999 and 38.96% share in total sales


--5.2 Status, open/close date

SELECT
	Status,
	COUNT(StoreKey) AS StoresCount,
	COUNT(CloseDate) AS ClosedStores,
	MIN(OpenDate) AS FirstOpenDate,
	MAX(OpenDate) AS LastOpenDate,
	MIN(CloseDate) AS FirstCloseDate,
	MAX(CloseDate) AS LastCloseDate
FROM Data.Store
WHERE CountryName <> 'Online'
GROUP BY Status;

--One store has no close status but does have a close date, working out which one

SELECT
	StoreKey,
	Description,
	Status,
	CloseDate
FROM Data.Store
WHERE 
	Status IS NULL
	AND CloseDate IS NOT NULL;
	
--Most likely an inconsistency, will use CloseDate as definite sign of store closure

--5.3 Checking if RESTRUCTURING status creates new StoreKey under the same StoreCode


WITH StoreVersions AS
(
	SELECT
		StoreCode,
		StoreKey,
		Status,
		OpenDate,
		CloseDate,
		COUNT(*) OVER(PARTITION BY StoreCode) AS KeysPerCode,
		LAG(CloseDate) OVER(PARTITION BY StoreCode ORDER BY OpenDate) AS PrevCloseDate
	FROM Data.Store
	WHERE StoreKey <> 999999
)

SELECT
	*,
	DATEDIFF(Day, PrevCloseDate, OpenDate) AS DaysSincePrevClose
FROM StoreVersions
WHERE KeysPerCode > 1
ORDER BY StoreCode, OpenDate;

--All restructured stores have their next version opened

--5.4 First and Last Sale in any Store

WITH StoreSalesFlags AS
(
	SELECT
		st.StoreKey,
		st.OpenDate,
		MIN(sa.OrderDate) FirstSaleDate,
		st.CloseDate,
		MAX(sa.OrderDate) LastSaleDate,
		CASE
			WHEN MIN(sa.OrderDate) < OpenDate THEN 1
			ELSE 0
		END SalesBeforeOpenFlag,
		CASE
			WHEN MAX(sa.OrderDate) > CloseDate THEN 1
			ELSE 0
		END SalesAfterCloseFlag
	FROM Data.Store AS st
	LEFT JOIN Data.Sales AS sa
	ON st.StoreKey = sa.StoreKey
	GROUP BY st.StoreKey, st.OpenDate, st.CloseDate	
)	
SELECT
	SUM(SalesBeforeOpenFlag) SalesBeforeOpenCheck,
	SUM(SalesAfterCloseFlag) SalesAfterCloseCheck
FROM StoreSalesFlags;

--5.5 Stores by country

--Working out if any of the stores were relocated to another country after the restructuring

SELECT
	StoreCode,
	COUNT(DISTINCT CountryName) CountCountries
FROM Data.Store
WHERE StoreKey <> 999999
GROUP BY StoreCode
HAVING COUNT(DISTINCT CountryName) > 1
ORDER BY CountCountries DESC;

--Checking if CountryCodes are consistant with CountryNames

SELECT
	CountryCode,
	COUNT(DISTINCT CountryName) AS NamesPerCode
FROM Data.Store
GROUP BY CountryCode
HAVING COUNT(DISTINCT CountryName) > 1;
	
--Stores and active stores by Country and CountryCode

SELECT
	CountryName,
	CountryCode,
	COUNT(DISTINCT StoreKey) AllStores,
	COUNT(CASE WHEN CloseDate IS NULL THEN StoreKey END) AS ActiveStores
FROM Data.Store
WHERE StoreKey <> 999999
GROUP BY CountryName, CountryCode;


--Checking if store in any given country uses single currency

SELECT
    st.CountryName AS StoreCountry,
    sa.CurrencyCode,
    COUNT(*) AS SalesRows
FROM Data.Sales AS sa
INNER JOIN Data.Store AS st 
ON st.StoreKey = sa.StoreKey
GROUP BY st.CountryName, sa.CurrencyCode
ORDER BY StoreCountry, SalesRows DESC;

SELECT
	sc.Country,
	sa.CurrencyCode,
	COUNT(*) AS SalesRows
FROM Data.Sales AS sa
INNER JOIN Data.Customer AS sc
ON sa.CustomerKey = sc.CustomerKey
GROUP BY sc.Country, sa.CurrencyCode
ORDER BY SalesRows DESC;

--=====================
--6. Clients by country
--=====================

--Working out weather we have any clients without purchases

SELECT
	c.Country,
	COUNT(DISTINCT c.CustomerKey) CountCustomers,
	COUNT(DISTINCT o.CustomerKey) MadePurchase
FROM Data.Customer AS c
LEFT JOIN Data.Orders AS o
ON o.CustomerKey = c.CustomerKey
GROUP BY c.Country
ORDER BY CountCustomers DESC;

--======================
--7. Product by category
--======================


SELECT
	CategoryName,
	SubCategoryName,
	COUNT(*) AS CountProducts
FROM Data.Product
GROUP BY CategoryName, SubCategoryName
ORDER BY CategoryName, SubCategoryName;

--Checking if hierarchy is consistant

SELECT
	p.ProductKey
FROM Data.Product AS p
LEFT JOIN Data.Sales AS s
ON p.ProductKey = s.ProductKey
WHERE s.ProductKey IS NULL
