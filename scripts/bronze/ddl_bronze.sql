
/*
===============================================================================
Script Name : ddl_bronze.sql
Database    : datawarehouse
Schema      : bronze
Author      : Sai Praveen

Description :
    This script creates the Bronze layer tables for the Data Warehouse
    project using PostgreSQL.

    The Bronze layer serves as the raw data ingestion layer, storing
    source data from CRM and ERP systems with minimal transformation.

Source Systems :
    1. CRM - Customer Information, Product Information, Sales Details
    2. ERP - Customer Demographics, Location, Product Categories

Prerequisites :
    1. The 'datawarehouse' database must already exist.
    2. Connect to the 'datawarehouse' database before execution.
    3. The 'bronze' schema must already exist.
    4. The executing user must have the required DDL privileges.

WARNING :
    - This script uses DROP TABLE IF EXISTS before creating each table.
    - Re-execution permanently removes existing table data.
    - Intended for initial setup or controlled development resets.
    - Do not execute against production without reviewing dependencies
      and ensuring appropriate backups are available.

===============================================================================
*/


-- =============================================================================
-- SECTION 1: CRM SOURCE TABLES
-- =============================================================================
-- Purpose:
--     Create Bronze tables to store raw customer, product, and sales data
--     extracted from the CRM source system.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Table       : bronze.crm_cust_info
-- Source File : source_crm/cust_info.csv
-- Description : Stores raw customer master data, including customer identifiers,
--               names, marital status, gender, and account creation date.
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS bronze.crm_cust_info;

CREATE TABLE bronze.crm_cust_info (
    cust_id             INT,
    cst_key             TEXT,
    cst_firstname       TEXT,
    cst_lastname        TEXT,
    cst_marital_status  TEXT,
    cst_gndr            TEXT,
    cst_create_date     DATE
);


-- -----------------------------------------------------------------------------
-- Table       : bronze.crm_prd_info
-- Source File : source_crm/prd_info.csv
-- Description : Stores raw product master data, including product identifiers,
--               product names, costs, product lines, and effective dates.
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS bronze.crm_prd_info;

CREATE TABLE bronze.crm_prd_info (
    prd_id        INT,
    prd_key       TEXT,
    prd_nm        TEXT,
    prd_cost      DECIMAL(10,2),
    prd_line      TEXT,
    prd_start_dt  DATE,
    prd_end_dt    DATE
);


-- -----------------------------------------------------------------------------
-- Table       : bronze.crm_sales_details
-- Source File : source_crm/sales_details.csv
-- Description : Stores raw sales transactions, including order identifiers,
--               product and customer references, order dates, shipping dates,
--               quantities, sales amounts, and unit prices.
--
-- Note        : sls_order_dt is stored as TEXT to preserve source date values
--               such as YYYYMMDD and invalid placeholders such as '0'.
--               Date cleansing and standardization will occur in Silver.
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS bronze.crm_sales_details;

CREATE TABLE bronze.crm_sales_details (
    sls_ord_num   TEXT,
    sls_prd_key   TEXT,
    sls_cust_id   INT,
    sls_order_dt  TEXT,
    sls_ship_dt   DATE,
    sls_due_dt    DATE,
    sls_sales     INT,
    sls_quantity  INT,
    sls_price     DECIMAL(10,2)
);


-- =============================================================================
-- SECTION 2: ERP SOURCE TABLES
-- =============================================================================
-- Purpose:
--     Create Bronze tables to store customer demographic information,
--     geographical data, and product category classifications received
--     from the ERP source system.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- Table       : bronze.erp_cust_az12
-- Source File : source_erp/CUST_AZ12.csv
-- Description : Stores customer demographic information, including customer
--               identifiers, birth dates, and gender attributes.
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS bronze.erp_cust_az12;

CREATE TABLE bronze.erp_cust_az12 (
    CID    TEXT,
    BDATE  DATE,
    GEN    TEXT
);


-- -----------------------------------------------------------------------------
-- Table       : bronze.erp_loc_a101
-- Source File : source_erp/LOC_A101.csv
-- Description : Stores customer location information, including customer
--               identifiers and associated country details.
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS bronze.erp_loc_a101;

CREATE TABLE bronze.erp_loc_a101 (
    CID    TEXT,
    CNTRY  TEXT
);


-- -----------------------------------------------------------------------------
-- Table       : bronze.erp_px_cat_g1v2
-- Source File : source_erp/PX_CAT_G1V2.csv
-- Description : Stores product category reference data, including category,
--               subcategory, and maintenance-related attributes.
-- -----------------------------------------------------------------------------

DROP TABLE IF EXISTS bronze.erp_px_cat_g1v2;

CREATE TABLE bronze.erp_px_cat_g1v2 (
    ID           TEXT,
    CAT          TEXT,
    SUBCAT       TEXT,
    MAINTENANCE  TEXT
);


-- =============================================================================
-- END OF SCRIPT
-- =============================================================================
-- All six Bronze layer tables have been defined.
--
-- Next Step:
--     Execute the Bronze layer ingestion procedure:
--         CALL bronze.load_bronze();
--
-- Note:
--     This script creates table structures only.
--     CSV ingestion is handled separately by the Bronze loading procedure.
-- =============================================================================
