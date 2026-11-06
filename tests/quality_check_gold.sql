FROM gold.fact_sales AS f
LEFT JOIN gold.dim_products AS p
    ON f.product_key = p.product_key
WHERE f.product_key IS NULL OR p.product_key IS NULL;

-- The original customer ID carried by the fact should agree with its mapped
-- customer dimension record (even if surrogate key numbering changes).
SELECT
    'FACT_CUSTOMER_BUSINESS_KEY_MATCH' AS check_name,
    COUNT(*) AS failing_rows,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM gold.fact_sales AS f
LEFT JOIN gold.dim_customers AS c
    ON f.customer_key = c.customer_key
WHERE c.customer_key IS NULL
   OR f.customer_id IS DISTINCT FROM c.customer_number;

-- ==========================================================================
-- 05. FACT_SALES: numerical measures and date integrity
-- ==========================================================================
SELECT
    'SALES_MEASURE_QUALITY' AS check_name,
    COUNT(*) FILTER (WHERE sales IS NULL OR sales <= 0) AS missing_or_nonpositive_sales,
    COUNT(*) FILTER (WHERE sales_quantity IS NULL OR sales_quantity <= 0) AS missing_or_nonpositive_quantities,
    COUNT(*) FILTER (WHERE sales_price IS NULL OR sales_price <= 0) AS missing_or_nonpositive_prices,
    CASE
        WHEN COUNT(*) FILTER (
            WHERE sales IS NULL OR sales <= 0
               OR sales_quantity IS NULL OR sales_quantity <= 0
               OR sales_price IS NULL OR sales_price <= 0
        ) = 0 THEN 'PASS' ELSE 'FAIL'
    END AS status
FROM gold.fact_sales;

-- Allow a 0.01 currency-unit tolerance for rounding in Silver.
SELECT
    'SALES_EQUALS_QUANTITY_TIMES_PRICE' AS check_name,
    COUNT(*) FILTER (
        WHERE sales IS NOT NULL
          AND sales_quantity IS NOT NULL
          AND sales_price IS NOT NULL
          AND ABS(sales::numeric - (sales_quantity::numeric * sales_price::numeric)) > 0.01
    ) AS mismatched_sales,
    CASE
        WHEN COUNT(*) FILTER (
            WHERE sales IS NOT NULL
              AND sales_quantity IS NOT NULL
              AND sales_price IS NOT NULL
              AND ABS(sales::numeric - (sales_quantity::numeric * sales_price::numeric)) > 0.01
        ) = 0 THEN 'PASS' ELSE 'FAIL'
    END AS status
FROM gold.fact_sales;

-- NULL ship/due dates are reported separately, not automatically failed:
-- depending on the business process, they may be acceptable.
SELECT
    'DATE_COMPLETENESS_DIAGNOSTIC' AS check_name,
    COUNT(*) FILTER (WHERE sales_date IS NULL) AS missing_order_dates,
    COUNT(*) FILTER (WHERE ship_date IS NULL) AS missing_ship_dates,
    COUNT(*) FILTER (WHERE due_date IS NULL) AS missing_due_dates
FROM gold.fact_sales;

SELECT
    'SALES_DATE_SEQUENCE' AS check_name,
    COUNT(*) FILTER (
        WHERE (ship_date IS NOT NULL AND sales_date IS NOT NULL AND ship_date < sales_date)
           OR (due_date IS NOT NULL AND sales_date IS NOT NULL AND due_date < sales_date)
    ) AS failing_rows,
    CASE WHEN COUNT(*) FILTER (
        WHERE (ship_date IS NOT NULL AND sales_date IS NOT NULL AND ship_date < sales_date)
           OR (due_date IS NOT NULL AND sales_date IS NOT NULL AND due_date < sales_date)
    ) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM gold.fact_sales;

-- ==========================================================================
-- 06. AGGREGATE RECONCILIATION: Silver vs Gold sales values
-- ==========================================================================
-- This compares exact sums and highlights duplicated/missing rows from joins.
-- If Silver measures are nullable, SUM ignores NULL in both data sets.
WITH totals AS (
    SELECT
        (SELECT SUM(sls_sales::numeric) FROM silver.crm_sales_details) AS silver_sales,
        (SELECT SUM(sales::numeric) FROM gold.fact_sales) AS gold_sales,
        (SELECT SUM(sls_quantity::numeric) FROM silver.crm_sales_details) AS silver_quantity,
        (SELECT SUM(sales_quantity::numeric) FROM gold.fact_sales) AS gold_quantity
)
SELECT
    'SALES_TOTAL_RECONCILIATION' AS check_name,
    silver_sales,
    gold_sales,
    silver_quantity,
    gold_quantity,
    CASE WHEN silver_sales IS NOT DISTINCT FROM gold_sales
           AND silver_quantity IS NOT DISTINCT FROM gold_quantity
         THEN 'PASS' ELSE 'FAIL' END AS status
FROM totals;

-- ==========================================================================
-- 07. DIAGNOSTICS: run these to investigate FAIL outcomes
-- ==========================================================================
-- Customers duplicated by the ERP joins or source data.
SELECT customer_number, COUNT(*) AS duplicate_count
FROM gold.dim_customers
GROUP BY customer_number
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC, customer_number
LIMIT 50;

-- Products duplicated by source or category joins.
SELECT product_id, COUNT(*) AS duplicate_count
FROM gold.dim_products
GROUP BY product_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC, product_id
LIMIT 50;

-- Example sales with unresolved foreign keys.
SELECT order_number, customer_id, customer_key, product_key, sales_date
FROM gold.fact_sales
WHERE customer_key IS NULL OR product_key IS NULL
LIMIT 50;

-- Example sales with inconsistent amounts.
SELECT order_number, sales, sales_quantity, sales_price,
       sales_quantity::numeric * sales_price::numeric AS expected_sales
FROM gold.fact_sales
WHERE sales IS NOT NULL
  AND sales_quantity IS NOT NULL
