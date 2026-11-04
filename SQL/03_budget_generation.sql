--================================================================================
--1. Summarizing sales table with countries, sales channel and category for budget
--================================================================================

WITH budget AS (

SELECT 
	YEAR(OrderDate) [Year],
	MONTH(OrderDate) [Month],
	cst.CountryName,
	str.SalesChannel,
	prd.CategoryName,
	SUM(NetPrice * Quantity) NetSales,
	SUM(Quantity) Quantity
FROM pbi.FactSales fsl
LEFT JOIN pbi.DimStore str
ON fsl.StoreKey = str.StoreKey
LEFT JOIN pbi.DimProduct prd
ON fsl.ProductKey = prd.ProductKey
LEFT JOIN pbi.DimCustomer cst
ON fsl.CustomerKey = cst.CustomerKey
WHERE
	YEAR(OrderDate) IN (2023, 2024)
GROUP BY
	YEAR(OrderDate),
	MONTH(OrderDate),
	cst.CountryName,
	str.SalesChannel,
	prd.CategoryName

)

SELECT
	*
FROM budget
ORDER BY
	Year,
	Month,
	CountryName,
	SalesChannel,
	CategoryName;


--===================================================================================================================================
--2. Creating budget assumption tables, connecting it to budget base and adding noise factor with CHECKSUM
--===================================================================================================================================

WITH CategoryAssumptions (BudgetYear, CategoryName, VolumeGrowth, PriceChange) AS (

SELECT * 
FROM
	(VALUES
		(2024, 'Audio', -0.22, 0.01),
		(2024, 'TV and Video', -0.24, -0.02),
		(2024, 'Computers', -0.23, 0.01),
		(2024, 'Cameras and camcorders', -0.28, 0.02),
		(2024, 'Cell phones', -0.21, 0.03),
		(2024, 'Music, Movies and Audio Books', -0.31, 0.00),
		(2024, 'Games and Toys', -0.22, 0.02),
		(2024, 'Home Appliances', -0.23, 0.03),
		(2025, 'Audio', 0.04, 0.02),
		(2025, 'TV and Video', 0.02, -0.01),
		(2025, 'Computers', 0.04, 0.02),
		(2025, 'Cameras and camcorders', -0.02, 0.02),
		(2025, 'Cell phones', 0.05, 0.03),
		(2025, 'Music, Movies and Audio Books', -0.05, 0.00),
		(2025, 'Games and Toys', 0.04, 0.02),
		(2025, 'Home Appliances', 0.03, 0.02)
		) v (BudgetYear, CategoryName, VolumeGrowth, PriceChange)
),

ChannelGrowth (SalesChannel, ExtraVolumeGrowth) AS (

SELECT *
FROM 
	(VALUES
		('Online', 0.04),
		('Store', 0.00)
		) v (SalesChannel, ExtraVolumeGrowth)
),

BudgetBase AS (

SELECT 
	YEAR(OrderDate) [Year],
	YEAR(OrderDate) + 1 BudgetYear,
	MONTH(OrderDate) [Month],
	cst.CountryName,
	str.SalesChannel,
	prd.CategoryName,
	SUM(NetPrice * Quantity) NetSales,
	SUM(Quantity) Quantity
FROM pbi.FactSales fsl
LEFT JOIN pbi.DimStore str
ON fsl.StoreKey = str.StoreKey
LEFT JOIN pbi.DimProduct prd
ON fsl.ProductKey = prd.ProductKey
LEFT JOIN pbi.DimCustomer cst
ON fsl.CustomerKey = cst.CustomerKey
WHERE
	YEAR(OrderDate) IN (2023, 2024)
GROUP BY
	YEAR(OrderDate),
	MONTH(OrderDate),
	cst.CountryName,
	str.SalesChannel,
	prd.CategoryName

),

BudgetAfterAssumptions AS (
SELECT
	bb.BudgetYear,
	bb.[Month],
	bb.CountryName,
	bb.SalesChannel,
	bb.CategoryName,
	Quantity * (1 + VolumeGrowth) * (1 + ExtraVolumeGrowth) UnitsBURaw,
	(NetSales / Quantity) * (1 + PriceChange) BudgetPrice,
	(ABS(CHECKSUM(bb.BudgetYear, bb.[Month], bb.CountryName, bb.SalesChannel, bb.CategoryName) % 61) - 30) / 1000.0 NoiseFactor
FROM BudgetBase bb
LEFT JOIN CategoryAssumptions ca
ON bb.CategoryName = ca.CategoryName AND bb.BudgetYear = ca.BudgetYear
LEFT JOIN ChannelGrowth cg
ON bb.SalesChannel = cg.SalesChannel
)
--=======================================
--4. Introducing noise factor in quantity
--=======================================

SELECT
	BudgetYear,
	[Month],
	CountryName,
	SalesChannel,
	CategoryName,
	CAST(ROUND(UnitsBURaw * (1 + NoiseFactor), 0) AS int) UnitsBU,
	ROUND(ROUND(UnitsBURaw * (1 + NoiseFactor), 0) * BudgetPrice, 0) NetSalesBU
FROM BudgetAfterAssumptions;