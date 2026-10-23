-- Run after importing the original CSV into retail_transactions.
-- Requires the eight original column names and M/D/YY date text.
-- Run once in a database without these views already present.

CREATE VIEW retail_source AS
SELECT
    InvoiceNo,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Country
FROM retail_transactions;

CREATE VIEW retail_distinct AS
SELECT DISTINCT *
FROM retail_source;

CREATE VIEW net_product_candidates AS
SELECT
    InvoiceNo,
    UPPER(StockCode) AS StockCode,
    Description,
    CAST(Quantity AS REAL) AS Quantity,
    InvoiceDate,
    CAST(UnitPrice AS REAL) AS UnitPrice,
    CustomerID,
    Country,
    CAST(Quantity AS REAL) * CAST(UnitPrice AS REAL) AS LineAmount
FROM retail_source
WHERE UPPER(StockCode) NOT IN (
    'B', 'POST', 'DOT', 'M', 'BANK CHARGES', 'D'
)
AND CAST(UnitPrice AS REAL) > 0
AND (
    (CAST(Quantity AS REAL) > 0 AND InvoiceNo NOT LIKE 'C%')
    OR
    (CAST(Quantity AS REAL) < 0 AND InvoiceNo LIKE 'C%')
);

CREATE VIEW monthly_net_sales AS WITH date_parts AS (
    SELECT
        LineAmount,
        SUBSTR(InvoiceDate, 1, INSTR(InvoiceDate, '/') - 1)
            AS month_number,
        SUBSTR(InvoiceDate, INSTR(InvoiceDate, '/') + 1)
            AS date_remainder
    FROM net_product_candidates
),
monthly_rows AS (
    SELECT
        LineAmount,
        '20' ||
        SUBSTR(date_remainder, INSTR(date_remainder, '/') + 1, 2)
        || '-' ||
        PRINTF('%02d', CAST(month_number AS INTEGER))
            AS sales_month
    FROM date_parts
)
SELECT
    sales_month,
    ROUND(SUM(LineAmount), 2) AS net_sales
FROM monthly_rows
GROUP BY sales_month
ORDER BY sales_month;

CREATE VIEW retail_dates AS
WITH parts AS (
    SELECT
        InvoiceDate,
        SUBSTR(InvoiceDate, 1, INSTR(InvoiceDate, '/') - 1)
            AS month_part,
        SUBSTR(InvoiceDate, INSTR(InvoiceDate, '/') + 1)
            AS remainder
    FROM retail_source
),
parsed AS (
    SELECT
        InvoiceDate,
        CAST(month_part AS INTEGER) AS month_number,
        CAST(
            SUBSTR(remainder, 1, INSTR(remainder, '/') - 1)
            AS INTEGER
        ) AS day_number,
        2000 + CAST(
            SUBSTR(remainder, INSTR(remainder, '/') + 1, 2)
            AS INTEGER
        ) AS year_number
    FROM parts
)
SELECT DISTINCT
    InvoiceDate,
    PRINTF(
        '%04d-%02d-%02d',
        year_number, month_number, day_number
    ) AS invoice_day
FROM parsed;

CREATE VIEW customer_cohorts AS
SELECT
    p.CustomerID,
    MIN(d.invoice_day) AS first_observed_purchase,
    SUBSTR(MIN(d.invoice_day), 1, 7) AS cohort_month
FROM net_product_candidates AS p
JOIN retail_dates AS d
    ON p.InvoiceDate = d.InvoiceDate
WHERE p.Quantity > 0
  AND p.InvoiceNo NOT LIKE 'C%'
  AND p.CustomerID IS NOT NULL
  AND TRIM(p.CustomerID) <> ''
GROUP BY p.CustomerID;

CREATE VIEW customer_purchase_months AS
SELECT DISTINCT
    p.CustomerID,
    SUBSTR(d.invoice_day, 1, 7) AS purchase_month
FROM net_product_candidates AS p
JOIN retail_dates AS d
    ON p.InvoiceDate = d.InvoiceDate
WHERE p.Quantity > 0
  AND p.InvoiceNo NOT LIKE 'C%'
  AND p.CustomerID IS NOT NULL
  AND TRIM(p.CustomerID) <> '';

CREATE VIEW cohort_next_month_repeat AS
SELECT
    c.cohort_month,
    COUNT(*) AS cohort_customers,
    COUNT(p.CustomerID) AS returned_next_month,
    ROUND(
        100.0 * COUNT(p.CustomerID) / COUNT(*),
        2
    ) AS next_month_repeat_pct
FROM customer_cohorts AS c
LEFT JOIN customer_purchase_months AS p
    ON c.CustomerID = p.CustomerID
   AND p.purchase_month = STRFTIME(
       '%Y-%m',
       c.cohort_month || '-01',
       '+1 month'
   )
WHERE c.cohort_month <= '2011-10'
GROUP BY c.cohort_month
ORDER BY c.cohort_month;