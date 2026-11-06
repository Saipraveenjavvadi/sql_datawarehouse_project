
-- ============================================================
-- Procedure : silver.load_silver()
-- Purpose   : Load and transform data from Bronze to Silver
-- Database  : PostgreSQL
-- Load Type : Full Refresh (TRUNCATE + INSERT)
--
-- Source Tables:
--   1. bronze.crm_cust_info
--   2. bronze.crm_prd_info
--   3. bronze.crm_sales_details
--   4. bronze.erp_cust_az12
--   5. bronze.erp_loc_a101
--   6. bronze.erp_px_cat_g1v2
--
-- Target Tables:
--   Corresponding tables under the silver schema
--
-- Execution:
--   CALL silver.load_silver();
--
-- Parameters:
--   None
--
-- Note:
--   All loads are transactional. If an error occurs,
--   the procedure raises an exception and changes
--   made by this CALL are rolled back.
-- ============================================================

CREATE OR REPLACE PROCEDURE silver.load_silver()
LANGUAGE plpgsql
AS $$
DECLARE
    v_batch_start_time TIMESTAMPTZ;
    v_table_start_time TIMESTAMPTZ;
    v_rows_loaded BIGINT;
    v_total_rows BIGINT := 0;
    v_current_table TEXT;
    v_error_message TEXT;
    v_error_state TEXT;

BEGIN
    -- Capture overall batch start time
    v_batch_start_time := clock_timestamp();

    RAISE NOTICE '========================================';
    RAISE NOTICE 'Silver Layer Loading Started';
    RAISE NOTICE 'Start Time: %', v_batch_start_time;
    RAISE NOTICE '========================================';

    -- ========================================================
    -- 1. LOAD CRM CUSTOMER INFORMATION
    -- ========================================================

    v_current_table := 'silver.crm_cust_info';
    v_table_start_time := clock_timestamp();

    RAISE NOTICE 'Loading table: %', v_current_table;

    TRUNCATE TABLE silver.crm_cust_info;

    INSERT INTO silver.crm_cust_info (
        cust_id,
        cst_key,
        cst_firstname,
        cst_lastname,
        cst_marital_status,
        cst_gndr,
        cst_create_date
    )
    SELECT
        cust_id,
        cst_key,
        TRIM(cst_firstname) AS cst_firstname,
        TRIM(cst_lastname) AS cst_lastname,

        -- Standardize marital status
        CASE
            WHEN UPPER(TRIM(cst_marital_status)) = 'M'
                THEN 'Married'
            WHEN UPPER(TRIM(cst_marital_status)) = 'S'
                THEN 'Single'
            ELSE 'n/a'
        END AS cst_marital_status,

        -- Standardize gender
        CASE
            WHEN UPPER(TRIM(cst_gndr)) = 'M'
                THEN 'Male'
            WHEN UPPER(TRIM(cst_gndr)) = 'F'
                THEN 'Female'
            ELSE 'n/a'
        END AS cst_gndr,

        cst_create_date

    FROM (
        -- Retain the latest record for each customer
        SELECT
            *,
            ROW_NUMBER() OVER (
                PARTITION BY cust_id
                ORDER BY cst_create_date DESC
            ) AS flag_by_createdate
        FROM bronze.crm_cust_info
        WHERE cust_id IS NOT NULL
    ) AS t

    WHERE flag_by_createdate = 1;

    GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;
    v_total_rows := v_total_rows + v_rows_loaded;

    RAISE NOTICE 'Completed: % | Rows: % | Duration: %',
        v_current_table,
        v_rows_loaded,
        clock_timestamp() - v_table_start_time;


    -- ========================================================
    -- 2. LOAD CRM PRODUCT INFORMATION
    -- ========================================================

    v_current_table := 'silver.crm_prd_info';
    v_table_start_time := clock_timestamp();

    RAISE NOTICE 'Loading table: %', v_current_table;

    TRUNCATE TABLE silver.crm_prd_info;

    INSERT INTO silver.crm_prd_info (
        prd_id,
        cat_id,
        prd_key,
        prd_nm,
        prd_cost,
        prd_line,
        prd_start_dt,
        prd_end_dt
    )
    SELECT
        prd_id,

        -- Extract category identifier
        REPLACE(
            SUBSTRING(prd_key FROM 1 FOR 5),
            '-',
            '_'
        ) AS cat_id,

        -- Extract product identifier
        SUBSTRING(prd_key FROM 7) AS prd_key,

        prd_nm,

        -- Replace missing product cost with zero
        COALESCE(prd_cost, 0) AS prd_cost,

        -- Standardize product line
        CASE UPPER(TRIM(prd_line))
            WHEN 'M' THEN 'Mountain'
            WHEN 'R' THEN 'Road'
            WHEN 'S' THEN 'Other Sales'
            WHEN 'T' THEN 'Touring'
            ELSE 'n/a'
        END AS prd_line,

        prd_start_dt::date AS prd_start_dt,

        -- Calculate historical product end date
        -- as one day before the next version starts
        (
            LEAD(prd_start_dt::date) OVER (
                PARTITION BY prd_key
                ORDER BY prd_start_dt
            ) - 1
        ) AS prd_end_dt

    FROM bronze.crm_prd_info;

    GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;
    v_total_rows := v_total_rows + v_rows_loaded;

    RAISE NOTICE 'Completed: % | Rows: % | Duration: %',
        v_current_table,
        v_rows_loaded,
        clock_timestamp() - v_table_start_time;


    -- ========================================================
    -- 3. LOAD CRM SALES DETAILS
    -- ========================================================

    v_current_table := 'silver.crm_sales_details';
    v_table_start_time := clock_timestamp();

    RAISE NOTICE 'Loading table: %', v_current_table;

    TRUNCATE TABLE silver.crm_sales_details;

    INSERT INTO silver.crm_sales_details (
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,
        sls_order_dt,
        sls_ship_dt,
        sls_due_dt,
        sls_sales,
        sls_quantity,
        sls_price
    )

    WITH normalized_sales AS (
        SELECT
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            sls_order_dt,
            sls_ship_dt,
            sls_due_dt,
            sls_sales,
            sls_quantity,

            -- Normalize price before calculating sales
            CASE
                WHEN sls_price IS NOT NULL
                     AND sls_price <> 0
                    THEN ABS(sls_price)

                WHEN sls_sales > 0
                     AND sls_quantity > 0
                    THEN sls_sales::numeric
                         / NULLIF(sls_quantity, 0)

                ELSE NULL
            END AS corrected_price

        FROM bronze.crm_sales_details
    )

    SELECT
        sls_ord_num,
        sls_prd_key,
        sls_cust_id,

        -- Convert YYYYMMDD order date to DATE
        CASE
            WHEN TRIM(sls_order_dt::text)
                 ~ '^[0-9]{8}$'
                 AND sls_order_dt::text <> '00000000'
            THEN TO_DATE(
                sls_order_dt::text,
                'YYYYMMDD'
            )
            ELSE NULL
        END AS sls_order_dt,

        sls_ship_dt,
		sls_due_dt,

        -- Correct inconsistent sales amounts
        CASE
            WHEN sls_sales IS NULL
                 OR sls_sales <= 0
                 OR (
                     corrected_price IS NOT NULL
                     AND sls_quantity > 0
                     AND sls_sales <>
                         sls_quantity * corrected_price
                 )
            THEN
                CASE
                    WHEN sls_quantity > 0
                         AND corrected_price IS NOT NULL
                    THEN sls_quantity * corrected_price
                    ELSE NULL
                END
            ELSE sls_sales
        END AS sls_sales,

        sls_quantity,

        -- Use normalized unit price
        corrected_price AS sls_price

    FROM normalized_sales;

    GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;
    v_total_rows := v_total_rows + v_rows_loaded;

    RAISE NOTICE 'Completed: % | Rows: % | Duration: %',
        v_current_table,
        v_rows_loaded,
        clock_timestamp() - v_table_start_time;


    -- ========================================================
    -- 4. LOAD ERP CUSTOMER INFORMATION
    -- ========================================================

    v_current_table := 'silver.erp_cust_az12';
    v_table_start_time := clock_timestamp();

    RAISE NOTICE 'Loading table: %', v_current_table;

    TRUNCATE TABLE silver.erp_cust_az12;

    INSERT INTO silver.erp_cust_az12 (
        cid,
        bdate,
        gen
    )
    SELECT

        -- Remove NAS prefix from customer ID
        CASE
            WHEN cid LIKE 'NAS%'
                THEN SUBSTRING(cid FROM 4)
            ELSE cid
        END AS cid,

        -- Reject future birth dates
        CASE
            WHEN bdate > CURRENT_DATE
                THEN NULL
            ELSE bdate
        END AS bdate,

        -- Standardize gender values
        CASE
            WHEN UPPER(TRIM(gen)) IN ('M', 'MALE')
                THEN 'Male'
            WHEN UPPER(TRIM(gen)) IN ('F', 'FEMALE')
                THEN 'Female'
            ELSE 'n/a'
        END AS gen

    FROM bronze.erp_cust_az12;

    GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;
    v_total_rows := v_total_rows + v_rows_loaded;

    RAISE NOTICE 'Completed: % | Rows: % | Duration: %',
        v_current_table,
        v_rows_loaded,
        clock_timestamp() - v_table_start_time;


    -- ========================================================
    -- 5. LOAD ERP CUSTOMER LOCATION
    -- ========================================================

    v_current_table := 'silver.erp_loc_a101';
    v_table_start_time := clock_timestamp();

    RAISE NOTICE 'Loading table: %', v_current_table;

    TRUNCATE TABLE silver.erp_loc_a101;

    INSERT INTO silver.erp_loc_a101 (
        cid,
        cntry
    )
    SELECT

        -- Remove hyphens from customer ID
        REPLACE(cid, '-', '') AS cid,

        -- Standardize country names
        CASE
            WHEN UPPER(TRIM(cntry)) = 'DE'
                THEN 'Germany'

            WHEN UPPER(TRIM(cntry)) IN ('USA', 'US')
                THEN 'United States'

            WHEN NULLIF(TRIM(cntry), '') IS NULL
                THEN 'n/a'

            ELSE TRIM(cntry)
        END AS cntry

    FROM bronze.erp_loc_a101;

    GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;
    v_total_rows := v_total_rows + v_rows_loaded;

    RAISE NOTICE 'Completed: % | Rows: % | Duration: %',
        v_current_table,
        v_rows_loaded,
        clock_timestamp() - v_table_start_time;


    -- ========================================================
    -- 6. LOAD ERP PRODUCT CATEGORY
    -- ========================================================

    v_current_table := 'silver.erp_px_cat_g1v2';
    v_table_start_time := clock_timestamp();

    RAISE NOTICE 'Loading table: %', v_current_table;

    TRUNCATE TABLE silver.erp_px_cat_g1v2;

    INSERT INTO silver.erp_px_cat_g1v2 (
        id,
        cat,
        subcat,
        maintenance
    )
    SELECT
        id,
        cat,
        subcat,
        maintenance

    FROM bronze.erp_px_cat_g1v2;

    GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;
    v_total_rows := v_total_rows + v_rows_loaded;

    RAISE NOTICE 'Completed: % | Rows: % | Duration: %',
        v_current_table,
        v_rows_loaded,
        clock_timestamp() - v_table_start_time;


    -- ========================================================
    -- BATCH COMPLETION
    -- ========================================================

    RAISE NOTICE '========================================';
    RAISE NOTICE 'Silver Layer Loading Completed';
    RAISE NOTICE 'Total Rows Loaded: %', v_total_rows;
    RAISE NOTICE 'Total Duration: %',
        clock_timestamp() - v_batch_start_time;
    RAISE NOTICE '========================================';


EXCEPTION
    WHEN OTHERS THEN

        GET STACKED DIAGNOSTICS
            v_error_message = MESSAGE_TEXT,
            v_error_state = RETURNED_SQLSTATE;

        RAISE NOTICE '========================================';
        RAISE NOTICE 'Silver Layer Loading Failed';
        RAISE NOTICE 'Failed Table: %', v_current_table;
        RAISE NOTICE 'SQLSTATE: %', v_error_state;
        RAISE NOTICE 'Error Message: %', v_error_message;
        RAISE NOTICE '========================================';

        -- Re-raise the error to roll back the failed load
        RAISE;

END;
$$;


-- ============================================================
-- EXECUTION EXAMPLE
-- ============================================================

-- Run the Silver layer ETL procedure
CALL silver.load_silver();


-- ============================================================
-- POST-LOAD VALIDATION
-- ============================================================

-- Verify record counts across all Silver tables

SELECT 'crm_cust_info' AS table_name, COUNT(*) AS row_count
FROM silver.crm_cust_info

UNION ALL

SELECT 'crm_prd_info', COUNT(*)
FROM silver.crm_prd_info

UNION ALL

SELECT 'crm_sales_details', COUNT(*)
FROM silver.crm_sales_details

UNION ALL

SELECT 'erp_cust_az12', COUNT(*)
FROM silver.erp_cust_az12

UNION ALL

SELECT 'erp_loc_a101', COUNT(*)
FROM silver.erp_loc_a101

UNION ALL

SELECT 'erp_px_cat_g1v2', COUNT(*)
FROM silver.erp_px_cat_g1v2;
