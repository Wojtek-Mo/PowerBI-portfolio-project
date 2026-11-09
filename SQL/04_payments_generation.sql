USE [Contoso V2 1M]

GO
--=========================
--Payments table generation
--=========================

DROP TABLE IF EXISTS #Payments;

WITH InvoiceBuckets AS (

SELECT
	*,
	ABS(CHECKSUM(OrderKey, CustomerKey) % 100) Bucket,
	ABS(CHECKSUM(OrderKey, CustomerKey, InvoiceDate)) DayNo
FROM pbi.FactInvoices
),

PaymentDelays AS (

	SELECT
		*,
		CASE
			WHEN Bucket <= 59 THEN -10 + DayNo % 11  
			WHEN Bucket <= 79 THEN   1 + DayNo % 30  
			WHEN Bucket <= 89 THEN  31 + DayNo % 30 
			WHEN Bucket <= 94 THEN  61 + DayNo % 30    
			WHEN Bucket <= 97 THEN  91 + DayNo % 90   
		END DelayDays,
		CASE
			WHEN Bucket <= 59 THEN 'On time'
			WHEN Bucket <= 79 THEN '1-30'
			WHEN Bucket <= 89 THEN '31-60'
			WHEN Bucket <= 94 THEN '61-90'
			WHEN Bucket <= 97 THEN '91-180'
			ELSE 'Never paid'
		END DelayGroup
	FROM InvoiceBuckets
),

Payments AS (

SELECT
	*,
	CASE WHEN DATEADD(Day, DelayDays, DueDate) <= '2025-12-31' THEN DATEADD(Day, DelayDays, DueDate) ELSE NULL END PaymentDate
FROM PaymentDelays

)

--Saving Payments to a temp table for testing

SELECT * INTO #Payments FROM Payments


--testing payments table

-- invoice count and end-of-data cutoff
SELECT
	COUNT(*) InvoiceCount,           
	MAX(PaymentDate) MaxPaymentDate 
FROM #Payments;

-- reference amounts: paid vs open (to reconcile with CSV files and FactPayments)
SELECT
	SUM(CASE WHEN PaymentDate IS NOT NULL THEN InvoiceAmount END) PaidAmount,
	SUM(CASE WHEN PaymentDate IS NULL THEN InvoiceAmount END) OpenAmount,
	SUM(InvoiceAmount) TotalAmount   
FROM #Payments;

-- overdue open invoices at end of 2025, by delay group
SELECT
	DelayGroup,
	COUNT(*) InvoiceCount            
FROM #Payments
WHERE
	DueDate < '2025-12-31'
	AND PaymentDate IS NULL
GROUP BY DelayGroup
ORDER BY DelayGroup;


--final query to get output for CSV files

SELECT
	ROW_NUMBER() OVER (ORDER BY PaymentDate, OrderKey) TransactionId,
	PaymentDate BookingDate,
	CAST(ROUND(InvoiceAmount, 2) AS DECIMAL(19, 2)) Amount,
	'USD' Currency,
	dc.CustomerName PayerName,
	CONCAT('Payment for invoice INV-', OrderKey) Description
FROM #Payments pm
LEFT JOIN pbi.DimCustomer dc
ON pm.CustomerKey = dc.CustomerKey
WHERE PaymentDate IS NOT NULL
ORDER BY TransactionId





