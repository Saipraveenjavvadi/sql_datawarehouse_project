CREATE SCHEMA IF NOT EXISTS silver;

-- =============================================================================
-- 1. CRM SOURCE TABLES
-- =============================================================================

-- 1.1 Customer information
-- Stores cleansed customer attributes and standardized demographic values.
DROP TABLE IF EXISTS silver.crm_cust_info;

CREATE TABLE silver.crm_cust_info (
    cust_id             INTEGER,
    cst_key             TEXT,
    cst_firstname       TEXT,
    cst_lastname        TEXT,
    cst_marital_status  TEXT,
    cst_gndr            TEXT,
    cst_create_date     DATE,
    dwh_create_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE silver.crm_cust_info IS
    'Cleansed CRM customer records; customer attributes are standardized during the Silver load.';

-- 1.2 Product information
-- Includes the derived category key and product validity date range.
DROP TABLE IF EXISTS silver.crm_prd_info;

CREATE TABLE silver.crm_prd_info (
    prd_id              INTEGER,
    cat_id              TEXT,
    prd_key             TEXT,
    prd_nm              TEXT,
    prd_cost            DECIMAL(10, 2),
    prd_line            TEXT,
    prd_start_dt        DATE,
    prd_end_dt          DATE,
    dwh_create_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE silver.crm_prd_info IS
    'Cleansed CRM product records with derived category identifiers and product effective dates.';

-- 1.3 Sales details
-- Stores normalized transaction dates, quantities, prices, and sales amounts.
DROP TABLE IF EXISTS silver.crm_sales_details;

CREATE TABLE silver.crm_sales_details (
    sls_ord_num         TEXT,
    sls_prd_key         TEXT,
    sls_cust_id         INTEGER,
    sls_order_dt        DATE,
    sls_ship_dt         DATE,
    sls_due_dt          DATE,
    sls_sales           INTEGER,
    sls_quantity        INTEGER,
    sls_price           DECIMAL(10, 2),
    dwh_create_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE silver.crm_sales_details IS
    'Cleansed CRM sales transactions with normalized dates and monetary values.';

-- =============================================================================
-- 2. ERP SOURCE TABLES
-- =============================================================================

-- 2.1 ERP customer demographics
-- Standardizes ERP customer IDs, gender codes, and invalid future birth dates.
DROP TABLE IF EXISTS silver.erp_cust_az12;

CREATE TABLE silver.erp_cust_az12 (
    cid                 TEXT,
    bdate               DATE,
    gen                 TEXT,
    dwh_create_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE silver.erp_cust_az12 IS
    'Cleansed ERP customer demographics with standardized customer IDs and gender values.';

-- 2.2 ERP customer location
-- Standardizes customer identifiers and country names.
DROP TABLE IF EXISTS silver.erp_loc_a101;

CREATE TABLE silver.erp_loc_a101 (
    cid                 TEXT,
    cntry               TEXT,
    dwh_create_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE silver.erp_loc_a101 IS
    'Cleansed ERP customer country information.';

-- 2.3 ERP product category lookup
-- Provides category, subcategory, and maintenance descriptors.
DROP TABLE IF EXISTS silver.erp_px_cat_g1v2;

CREATE TABLE silver.erp_px_cat_g1v2 (
    id                  TEXT,
    cat                 TEXT,
    subcat              TEXT,
    maintenance         TEXT,
    dwh_create_date     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE silver.erp_px_cat_g1v2 IS
    'ERP product category and subcategory reference data.';

-- =============================================================================
-- 3. OPTIONAL POST-DEPLOYMENT CHECK
-- =============================================================================
-- Inspect the generated table definitions in PostgreSQL:
-- SELECT table_name, column_name, data_type, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'silver'
-- ORDER BY table_name, ordinal_position;
