--==================
--Data quality check
--==================


--=======================
--1. Missing values check
--=======================

--1.1 Fact Table
SELECT
	'Sales' TableName,
	COUNT(*) - COUNT(OrderKey) OrderKeyNulls,
	COUNT(*) - COUNT(LineNumber) LineNumberNulls,
	COUNT(*) - COUNT(OrderDate) OrderDateNulls,
	COUNT(*) - COUNT(DeliveryDate) DeliveryDateNulls,
	COUNT(*) - COUNT(CustomerKey) CustomerKeyNulls,
	COUNT(*) - COUNT(StoreKey) StoreKeyNulls,
	COUNT(*) - COUNT(ProductKey) ProductKeyNulls,
	COUNT(*) - COUNT(Quantity) QuantityNulls,
	COUNT(*) - COUNT(UnitPrice) UnitPriceNulls,
	COUNT(*) - COUNT(NetPrice) NetPriceNulls,
	COUNT(*) - COUNT(UnitCost) UnitCostNulls,
	COUNT(*) - COUNT(CurrencyCode) CurrencyCodeNulls,
	COUNT(*) - COUNT(ExchangeRate) ExchangeRateNulls
FROM Data.Sales;

--Summary: Results 0 in each column, no NULLs in sales table

--1.2 Customer
SELECT
    'Customer' TableName,
    COUNT(*) - COUNT(CustomerKey) CustomerKeyNulls,
    COUNT(*) - COUNT(Country) CountryNulls
FROM Data.Customer;

--Summary: No NULLs in CustomerKey and Country

--1.3 Product
SELECT
    'Product' TableName,
    COUNT(*) - COUNT(ProductKey) ProductKeyNulls,
    COUNT(*) - COUNT(CategoryKey) CategoryKeyNulls,
    COUNT(*) - COUNT(SubCategoryKey) SubCategoryKeyNulls,
    COUNT(*) - COUNT(CategoryName) CategoryNameNulls,
    COUNT(*) - COUNT(SubCategoryName) SubCategoryNameNulls
FROM Data.Product;

--Summary: No NULLs in ProductKey, CategoryKey, SubCategoryKey, CategoryName, SubCategoryName

--1.4 Store (CloseDate and Status intentionally not checked: NULL means open store)

SELECT
    'Store' TableName,
    COUNT(*) - COUNT(StoreKey) StoreKeyNulls,
    COUNT(*) - COUNT(StoreCode) StoreCodeNulls,
    COUNT(*) - COUNT(OpenDate) OpenDateNulls,
    COUNT(*) - COUNT(CountryCode) CountryCodeNulls,
    COUNT(*) - COUNT(CountryName) CountryNameNulls
FROM Data.Store;
	
--Summary: No NULLs in StoreKey, StoreCode, OpenDate, CountryCode, CountryName

--1.5 Summary check
SELECT
    'Sales: rows with NULL in any required column' CheckName,
    COUNT(*) AS FailedRows
FROM Data.Sales
WHERE OrderKey IS NULL
   OR LineNumber IS NULL
   OR OrderDate IS NULL
   OR CustomerKey IS NULL
   OR StoreKey IS NULL
   OR ProductKey IS NULL
   OR Quantity IS NULL
   OR UnitPrice IS NULL
   OR NetPrice IS NULL
   OR UnitCost IS NULL
   OR CurrencyCode IS NULL
   OR ExchangeRate IS NULL;
	

--====================================================
--2. Checking if primary keys are unique in each table
--====================================================
WITH CustomerDup AS (
    SELECT 
        CustomerKey, 
        COUNT(*) Occurrences
    FROM Data.Customer
    GROUP BY CustomerKey
    HAVING COUNT(*) > 1
),
ProductDup AS (
    SELECT 
        ProductKey,
        COUNT(*) Occurrences
    FROM Data.Product
    GROUP BY ProductKey
    HAVING COUNT(*) > 1
),
StoreDup AS (
    SELECT 
        StoreKey, 
        COUNT(*) Occurrences
    FROM Data.Store
    GROUP BY StoreKey
    HAVING COUNT(*) > 1
),
OrderDup AS (
    SELECT 
        OrderKey, 
        COUNT(*) Occurrences
    FROM Data.Orders
    GROUP BY OrderKey
    HAVING COUNT(*) > 1
),
SalesLineDup AS (
    SELECT 
        OrderKey, 
        LineNumber, 
        COUNT(*) Occurrences
    FROM Data.Sales
    GROUP BY OrderKey, LineNumber
    HAVING COUNT(*) > 1
),
OrderRowsLineDup AS (
    SELECT 
        OrderKey, 
        LineNumber, 
        COUNT(*) Occurrences
    FROM Data.OrderRows
    GROUP BY OrderKey, LineNumber
    HAVING COUNT(*) > 1
)
SELECT
    (SELECT COUNT(*) FROM CustomerDup) CustomerKeyDuplicates,
    (SELECT COUNT(*) FROM ProductDup) ProductKeyDuplicates,
    (SELECT COUNT(*) FROM StoreDup) StoreKeyDuplicates,
    (SELECT COUNT(*) FROM OrderDup) OrderKeyDuplicates,
    (SELECT COUNT(*) FROM SalesLineDup) SalesOrderLineDuplicates,
    (SELECT COUNT(*) FROM OrderRowsLineDup) OrderRowsOrderLineDuplicates;

--Summary: All Key columns have unique values

--====================
--3. Orphaned records
--====================


--Checking for orphaned records in sales table for dimensions

SELECT
    SUM(CASE WHEN st.StoreKey IS NULL THEN 1 ELSE 0 END) OrphanedSalesStore,
    SUM(CASE WHEN pr.ProductKey IS NULL THEN 1 ELSE 0 END) OrphanedSalesProduct,
    SUM(CASE WHEN cu.CustomerKey IS NULL THEN 1 ELSE 0 END) OrphanedSalesCustomer
FROM Data.Sales sa
LEFT JOIN Data.Store st
ON sa.StoreKey = st.StoreKey
LEFT JOIN Data.Product pr
ON sa.ProductKey = pr.ProductKey
LEFT JOIN Data.Customer  cu
ON sa.CustomerKey = cu.CustomerKey;


--Cross checking orders with sales for orphaned records (both directions)

SELECT
    sa.OrderKey OrphanedSalesOrder
FROM Data.Sales sa
LEFT JOIN Data.Orders o
ON sa.OrderKey = o.OrderKey
WHERE o.OrderKey IS NULL;

SELECT
    o.OrderKey OrphanedOrderSales
FROM Data.Orders o
LEFT JOIN Data.Sales sa
ON o.OrderKey = sa.OrderKey
WHERE sa.OrderKey IS NULL;


--Summary: No orphaned records in any od the dimensions, sales vs orders also consistent

--================
--4. Sales values 
--================

SELECT
    SUM(CASE WHEN Quantity <= 0 THEN 1 ELSE 0 END) QuantityCheck,
    SUM(CASE WHEN UnitPrice <= 0 THEN 1 ELSE 0 END) UnitPriceCheck,
    SUM(CASE WHEN NetPrice <= 0 THEN 1 ELSE 0 END) NetPriceCheck,
    SUM(CASE WHEN UnitCost <= 0 THEN 1 ELSE 0 END) UnitCostCheck,
    SUM(CASE WHEN ExchangeRate <= 0 THEN 1 ELSE 0 END) ExchangeRateCheck,
    SUM(CASE WHEN NetPrice > UnitPrice THEN 1 ELSE 0 END) NegativeDiscountCheck,
    SUM(CASE WHEN ExchangeRate <> 1 AND CurrencyCode = 'USD' THEN 1 ELSE 0 END) USDRateCheck,
    SUM(CASE WHEN UnitCost > NetPrice THEN 1 ELSE 0 END) SalesBelowCostInfo
FROM Data.Sales;

--Summary: No negative or zero quantity, no negative unit price, netprice or unitcost, no negative exchangerate, no negative discount, amounts in USD

--============
--5.Date logic
--============

--Check delivery before ordering

SELECT
    SUM(CASE WHEN OrderDate > DeliveryDate THEN 1 ELSE 0 END) DeliveryBeforeOrderFlag
FROM Data.Sales;

--Summary: No delivery dates before order dates

--Check store closing date before opening date

SELECT
    SUM(CASE WHEN OpenDate > CloseDate THEN 1 ELSE 0 END) CloseBeforeOpenFlag
FROM Data.Store;

--Summary: No store close date before store open date

--Checking sales outside of store open period

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

--Summary: No sales outside of store open period

--Checking inactive stores (no sales for last 90days)


SELECT
    COUNT(DISTINCT StoreKey) InactiveStoresFlag
FROM
    (SELECT
        st.StoreKey,
        MAX(OrderDate) LastSaleDate 
    FROM Data.Store st
    LEFT JOIN Data.Sales sa
    ON sa.StoreKey = st.StoreKey
    WHERE st.CloseDate IS NULL
    GROUP BY st.StoreKey
    HAVING 
        MAX(OrderDate) < (SELECT DATEADD(Day, -90, MAX(OrderDate)) FROM Data.Sales)
        OR MAX(OrderDate) IS NULL) sub;

--Summary: No inactive stores

--==========================================
--6. Sales table vs Orders table consistnecy
--==========================================

SELECT 
    COUNT(sa.OrderKey) FailedFlag
FROM Data.Sales sa
LEFT JOIN Data.Orders o 
ON sa.OrderKey = o.OrderKey
WHERE
    sa.CustomerKey <> o.CustomerKey
    OR sa.StoreKey <> o.StoreKey
    OR sa.OrderDate <> o.OrderDate
    OR sa.DeliveryDate <> o.DeliveryDate
    OR sa.CurrencyCode <> o.CurrencyCode;

--Summary: sales vs order tables are consistant

--=========================
--7. Dimensions consistency
--=========================

--Category/Subcategory consistency

SELECT
    COUNT(*) SubCategoryFlag
FROM
    (SELECT
        SubCategoryKey,
        COUNT(DISTINCT CategoryKey) CategoryCount
    FROM Data.Product
    GROUP BY SubCategoryKey
    HAVING COUNT(DISTINCT CategoryKey) > 1) sub;

--Summary: No inconsistencies in category hierarchy

--Subcategory/SubcategoryName consistency

SELECT
    COUNT(*) NameFlag
FROM
    (SELECT
        SubCategoryKey,
        COUNT(DISTINCT SubCategoryName) NameCount
    FROM Data.Product
    GROUP BY SubCategoryKey
    HAVING COUNT(DISTINCT SubCategoryName) > 1) sub;

--Summary: No inconsistencies in subcategory naming

--CountryCode/CountryName consistency

SELECT
    COUNT(*) CountryFlag
FROM
    (SELECT
        CountryCode,
	    COUNT(DISTINCT CountryName) NamesPerCode
    FROM Data.Store
    GROUP BY CountryCode
    HAVING COUNT(DISTINCT CountryName) > 1) sub;

--Summary: No inconsistencies in CountryCode/CountryName relation

--Store in more than one country

SELECT
    COUNT(*) StoreFlag
FROM 
    (SELECT
        StoreCode,
        COUNT(DISTINCT CountryCode) CountryCount
    FROM Data.Store
    GROUP BY StoreCode
    HAVING COUNT(DISTINCT CountryCode) > 1) sub;

--Summary: No store is in more than one country