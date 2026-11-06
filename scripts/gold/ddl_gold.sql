/*
===============================================================================
 Project      : SQL Data Warehouse | Medallion Architecture
 Script       : gold_layer_views.sql
 Layer        : Gold (Presentation / Star Schema)
 Database     : PostgreSQL
 Description  : Create customer and product dimension views and a sales fact view
 Dependencies : silver.crm_cust_info, silver.erp_cust_az12,
                silver.erp_loc_a101, silver.crm_prd_info,
                silver.erp_px_cat_g1v2, silver.crm_sales_details
 Execution    : psql -d <database_name> -f gold_layer_views.sql
 Notes        : - These are regular views (data is read from Silver at query time).
                - ROW_NUMBER() keys are dynamic, not persistent surrogate keys.
                - Fact view resolves dimension keys through business-key joins.
                - Source lookup keys must be unique for one-to-one dimension joins.
                - This script uses the corrected alias customer_id (not cusotmer_id).
===============================================================================
*/

CREATE SCHEMA IF NOT EXISTS gold;

-- =============================================================================
-- 1. Customer Dimension
-- Purpose: Consolidate customer profile, demographics and geographic attributes.
-- Grain  : One row per customer, provided ERP lookup keys are unique.
-- =============================================================================
CREATE OR REPLACE VIEW gold.dim_customers AS
SELECT
    ROW_NUMBER() OVER (
        ORDER BY cci.cst_key, cci.cst_create_date, cci.cust_id
    ) AS customer_key,
    cci.cust_id             AS customer_number,
    cci.cst_key             AS customer_id,
    cci.cst_firstname       AS first_name,
    cci.cst_lastname        AS last_name,
    cci.cst_marital_status  AS marital_status,
    cci.cst_create_date     AS create_date,
    eca.bdate               AS dob,
    CASE
        WHEN cci.cst_gndr IS NULL
          OR LOWER(TRIM(cci.cst_gndr)) = 'n/a'
        THEN eca.gen
        ELSE cci.cst_gndr
    END                     AS gender,
    ela.cntry               AS country
FROM silver.crm_cust_info AS cci
LEFT JOIN silver.erp_cust_az12 AS eca
    ON cci.cst_key = eca.cid
LEFT JOIN silver.erp_loc_a101 AS ela
    ON cci.cst_key = ela.cid;

COMMENT ON VIEW gold.dim_customers IS
'Customer dimension: combines CRM customer details with ERP demographics and location.';

-- =============================================================================
-- 2. Product Dimension
-- Purpose: Enrich active products with category and maintenance attributes.
-- Grain  : One row per active product, provided category lookup IDs are unique.
-- =============================================================================
CREATE OR REPLACE VIEW gold.dim_products AS
SELECT
    ROW_NUMBER() OVER (
        ORDER BY cpi.prd_start_dt, cpi.prd_key, cpi.prd_id
    ) AS product_key,
    cpi.prd_id        AS product_num,
    cpi.prd_key       AS product_id,
    cpi.prd_nm        AS product_name,
    cpi.cat_id        AS category_id,
    epcgv.cat         AS category,
    epcgv.subcat      AS subcategory,
    epcgv.maintenance AS maintenance,
    cpi.prd_cost      AS product_cost,
    cpi.prd_line      AS product_line,
    cpi.prd_start_dt  AS product_start_date
FROM silver.crm_prd_info AS cpi
LEFT JOIN silver.erp_px_cat_g1v2 AS epcgv
    ON cpi.cat_id = epcgv.id
WHERE cpi.prd_end_dt IS NULL;

COMMENT ON VIEW gold.dim_products IS
'Product dimension: active CRM products enriched with ERP category metadata.';

-- =============================================================================
-- 3. Sales Fact
-- Purpose: Expose sales transactions with customer and product dimension keys.
-- Grain  : One row per Silver sales record, if dimension keys are unique.
-- =============================================================================
CREATE OR REPLACE VIEW gold.fact_sales AS
SELECT
    csd.sls_ord_num   AS order_number,
    dc.customer_key   AS customer_key,
    dp.product_key    AS product_key,
    csd.sls_cust_id   AS customer_id,
    csd.sls_order_dt  AS sales_date,
    csd.sls_ship_dt   AS ship_date,
    csd.sls_due_dt    AS due_date,
    csd.sls_sales     AS sales,
    csd.sls_quantity  AS sales_quantity,
    csd.sls_price     AS sales_price
FROM silver.crm_sales_details AS csd
LEFT JOIN gold.dim_customers AS dc
    ON csd.sls_cust_id = dc.customer_number
LEFT JOIN gold.dim_products AS dp
    ON csd.sls_prd_key = dp.product_id;

COMMENT ON VIEW gold.fact_sales IS
'Sales fact: Silver sales records enriched with dynamic Gold dimension keys.';
