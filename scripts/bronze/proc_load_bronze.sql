
/*
===============================================================================
Script Name : proc_load_bronze.sql
Database    : datawarehouse
Schema      : bronze
Procedure   : bronze.load_bronze()
Author      : Sai Praveen

Description :
    This stored procedure performs a full refresh of the Bronze layer by
    ingesting raw CRM and ERP source data from CSV files into PostgreSQL.

    The procedure uses PostgreSQL's COPY command for bulk data ingestion
    and implements execution monitoring, row-count tracking, and
    exception handling.

Source Systems :
    1. CRM
       - crm_cust_info       : Customer master information
       - crm_prd_info        : Product master information
       - crm_sales_details   : Sales transaction details

    2. ERP
       - erp_cust_az12       : Customer demographic information
       - erp_loc_a101       : Customer geographical information
       - erp_px_cat_g1v2    : Product category information

Loading Strategy :
    1. Record the overall batch start time.
    2. Truncate existing records from each Bronze table.
    3. Load raw CSV data using PostgreSQL COPY.
    4. Capture the number of rows loaded using GET DIAGNOSTICS.
    5. Measure execution time for each table using clock_timestamp().
    6. Display load status, row counts, and execution durations.
    7. Capture SQL errors and terminate the batch if a load fails.
    8. Display total batch execution time upon successful completion.

Parameters :
    None.

    This procedure does not require input or output parameters.
    All source file paths and destination tables are predefined
    within the procedure.

Prerequisites :
    1. The 'datawarehouse' database must already exist.
    2. Connect to the 'datawarehouse' database before execution.
    3. The 'bronze' schema and all six target tables must exist.
    4. The CSV source files must be accessible to the PostgreSQL server.
    5. The executing database role must have the necessary table and
       server-side file access privileges.
    6. Source CSV columns must match the expected table structure
       and compatible PostgreSQL data types.

Execution :
    Execute the following command from DBeaver or another SQL client
    connected to the 'datawarehouse' database:

        CALL bronze.load_bronze();

    No parameters are required because the procedure is defined
    without arguments.

Execution Monitoring :
    The procedure displays informational messages using RAISE NOTICE.

    For each table, the following details are displayed:
        - Table name
        - Load status
        - Number of rows loaded
        - Execution duration in seconds

    Total batch execution time is displayed after successful completion.

Error Handling :
    PostgreSQL's EXCEPTION WHEN OTHERS block is used to capture errors.

    On failure, the procedure displays:
        - Failed table name
        - PostgreSQL SQLSTATE error code
        - Error message
        - Time elapsed before failure

    The error is re-raised to terminate execution.

    All table modifications performed within the exception-protected
    block are rolled back if a load fails.

WARNING :
    1. TRUNCATE permanently removes existing records when committed.
       This procedure is intended for full-refresh ingestion only.

    2. PostgreSQL COPY reads files from the database server's
       filesystem, not necessarily the SQL client's local machine.

    3. Hardcoded source file paths are environment-specific and
       must be updated when deploying to another environment.

    4. This procedure does not support incremental data loading.

    5. RAISE NOTICE messages provide runtime feedback but are not
       permanently stored in an audit table.

    6. TRUNCATE acquires an ACCESS EXCLUSIVE lock, which can block
       concurrent table access until the transaction completes.

    7. This procedure is intended for development and controlled
       batch processing. Production deployment requires appropriate
       scheduling, permissions, monitoring, and operational controls.

===============================================================================
*/

CREATE OR REPLACE PROCEDURE bronze.load_bronze()
LANGUAGE plpgsql
AS $$
DECLARE

    -- Timestamp used to calculate total batch execution time.
    v_batch_start_time TIMESTAMPTZ;

    -- Timestamp used to measure individual table loading duration.
    v_table_start_time TIMESTAMPTZ;

    -- Stores the number of records loaded by the most recent COPY.
    v_rows_loaded BIGINT;

    -- Tracks the table currently being processed for error reporting.
    v_current_table TEXT;

    -- Stores the PostgreSQL error message if an exception occurs.
    v_error_message TEXT;

    -- Stores the SQLSTATE error code associated with an exception.
    v_error_state TEXT;

BEGIN

    -- ========================================================================
    -- STEP 1: INITIALIZE BRONZE LAYER LOAD
    -- ========================================================================

    -- Capture the actual start time of the overall ETL batch.
    v_batch_start_time := clock_timestamp();

    RAISE NOTICE '----------------------------------------';
    RAISE NOTICE 'Bronze layer loading started';
    RAISE NOTICE '----------------------------------------';


    -- ========================================================================
    -- STEP 2: EXECUTE BRONZE DATA INGESTION
    -- ========================================================================
    -- The nested BEGIN ... EXCEPTION block handles failures during loading.
    -- If any table load fails, changes within this block are rolled back.
    -- ========================================================================

    BEGIN

        -- ====================================================================
        -- SECTION 1: CRM SOURCE DATA INGESTION
        -- ====================================================================


        -- --------------------------------------------------------------------
        -- Table       : bronze.crm_cust_info
        -- Source      : source_crm/cust_info.csv
        -- Description : Loads raw customer master information from CRM.
        -- Strategy    : Full refresh using TRUNCATE followed by COPY.
        -- --------------------------------------------------------------------

        v_current_table := 'bronze.crm_cust_info';
        v_table_start_time := clock_timestamp();

        RAISE NOTICE 'Loading % ...', v_current_table;

        -- Remove existing records before loading the latest source data.
        TRUNCATE TABLE bronze.crm_cust_info;

        -- Bulk-load CRM customer data into the Bronze table.
        COPY bronze.crm_cust_info (
            cust_id,
            cst_key,
            cst_firstname,
            cst_lastname,
            cst_marital_status,
            cst_gndr,
            cst_create_date
        )
        FROM '/Users/saipraveenjavvadi/Downloads/sql-data-warehouse-project/datasets/source_crm/cust_info.csv'
        WITH (
            FORMAT CSV,
            HEADER TRUE,
            DELIMITER ','
        );

        -- Capture records processed by COPY without an additional COUNT query.
        GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;

        -- Log the table's record count and execution duration.
        RAISE NOTICE 'SUCCESS | % | Rows: % | Duration: % seconds',
            v_current_table,
            v_rows_loaded,
            ROUND(
                EXTRACT(EPOCH FROM
                    (clock_timestamp() - v_table_start_time))::NUMERIC,
                3
            );


        -- --------------------------------------------------------------------
        -- Table       : bronze.crm_prd_info
        -- Source      : source_crm/prd_info.csv
        -- Description : Loads raw product master data, including product
        --               identifiers, costs, categories, and effective dates.
        -- Strategy    : Full refresh using TRUNCATE followed by COPY.
        -- --------------------------------------------------------------------

        v_current_table := 'bronze.crm_prd_info';
        v_table_start_time := clock_timestamp();

        RAISE NOTICE 'Loading % ...', v_current_table;

        -- Clear existing product records.
        TRUNCATE TABLE bronze.crm_prd_info;

        -- Bulk-load CRM product information.
        COPY bronze.crm_prd_info
        FROM '/Users/saipraveenjavvadi/Downloads/sql-data-warehouse-project/datasets/source_crm/prd_info.csv'
        WITH (
            FORMAT CSV,
            HEADER TRUE,
            DELIMITER ','
        );

        -- Retrieve the number of records loaded.
        GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;

        -- Log successful completion and load duration.
        RAISE NOTICE 'SUCCESS | % | Rows: % | Duration: % seconds',
            v_current_table,
            v_rows_loaded,
            ROUND(
                EXTRACT(EPOCH FROM
                    (clock_timestamp() - v_table_start_time))::NUMERIC,
                3
            );


        -- --------------------------------------------------------------------
        -- Table       : bronze.crm_sales_details
        -- Source      : source_crm/sales_details.csv
        -- Description : Loads raw sales transactions, including customer,
        --               product, order, quantity, and pricing information.
        -- Strategy    : Full refresh using TRUNCATE followed by COPY.
        -- Note        : Source date columns may require cleansing in Silver
        --               when invalid or nonstandard date values are present.
        -- --------------------------------------------------------------------

        v_current_table := 'bronze.crm_sales_details';
        v_table_start_time := clock_timestamp();

        RAISE NOTICE 'Loading % ...', v_current_table;

        -- Remove previously ingested sales transactions.
        TRUNCATE TABLE bronze.crm_sales_details;

        -- Bulk-load raw CRM sales transaction data.
        COPY bronze.crm_sales_details
        FROM '/Users/saipraveenjavvadi/Downloads/sql-data-warehouse-project/datasets/source_crm/sales_details.csv'
        WITH (
            FORMAT CSV,
            HEADER TRUE,
            DELIMITER ','
        );

        -- Capture the total number of records loaded.
        GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;

        -- Log successful completion and load duration.
        RAISE NOTICE 'SUCCESS | % | Rows: % | Duration: % seconds',
            v_current_table,
            v_rows_loaded,
            ROUND(
                EXTRACT(EPOCH FROM
                    (clock_timestamp() - v_table_start_time))::NUMERIC,
                3
            );


        -- ====================================================================
        -- SECTION 2: ERP SOURCE DATA INGESTION
        -- ====================================================================


        -- --------------------------------------------------------------------
        -- Table       : bronze.erp_cust_az12
        -- Source      : source_erp/CUST_AZ12.csv
        -- Description : Loads customer demographic attributes from ERP,
        --               including customer identifiers, birth dates,
        --               and gender information.
        -- Strategy    : Full refresh using TRUNCATE followed by COPY.
        -- --------------------------------------------------------------------

        v_current_table := 'bronze.erp_cust_az12';
        v_table_start_time := clock_timestamp();

        RAISE NOTICE 'Loading % ...', v_current_table;

        -- Remove existing customer demographic records.
        TRUNCATE TABLE bronze.erp_cust_az12;

        -- Bulk-load ERP customer demographic data.
        COPY bronze.erp_cust_az12
        FROM '/Users/saipraveenjavvadi/Downloads/sql-data-warehouse-project/datasets/source_erp/CUST_AZ12.csv'
        WITH (
            FORMAT CSV,
            HEADER TRUE,
            DELIMITER ','
        );

        -- Capture records loaded during the current COPY operation.
        GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;

        -- Log successful completion and execution duration.
        RAISE NOTICE 'SUCCESS | % | Rows: % | Duration: % seconds',
            v_current_table,
            v_rows_loaded,
            ROUND(
                EXTRACT(EPOCH FROM
                    (clock_timestamp() - v_table_start_time))::NUMERIC,
                3
            );


        -- --------------------------------------------------------------------
        -- Table       : bronze.erp_loc_a101
        -- Source      : source_erp/LOC_A101.csv
        -- Description : Loads customer location reference data, including
        --               customer identifiers and country information.
        -- Strategy    : Full refresh using TRUNCATE followed by COPY.
        -- --------------------------------------------------------------------

        v_current_table := 'bronze.erp_loc_a101';
        v_table_start_time := clock_timestamp();

        RAISE NOTICE 'Loading % ...', v_current_table;

        -- Clear previously loaded customer location records.
        TRUNCATE TABLE bronze.erp_loc_a101;

        -- Bulk-load ERP customer location data.
        COPY bronze.erp_loc_a101
        FROM '/Users/saipraveenjavvadi/Downloads/sql-data-warehouse-project/datasets/source_erp/LOC_A101.csv'
        WITH (
            FORMAT CSV,
            HEADER TRUE,
            DELIMITER ','
        );

        -- Capture the number of records loaded.
        GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;

        -- Log successful completion and execution duration.
        RAISE NOTICE 'SUCCESS | % | Rows: % | Duration: % seconds',
            v_current_table,
            v_rows_loaded,
            ROUND(
                EXTRACT(EPOCH FROM
                    (clock_timestamp() - v_table_start_time))::NUMERIC,
                3
            );


        -- --------------------------------------------------------------------
        -- Table       : bronze.erp_px_cat_g1v2
        -- Source      : source_erp/PX_CAT_G1V2.csv
        -- Description : Loads product category reference information,
        --               including categories, subcategories, and
        --               maintenance-related attributes.
        -- Strategy    : Full refresh using TRUNCATE followed by COPY.
        -- --------------------------------------------------------------------

        v_current_table := 'bronze.erp_px_cat_g1v2';
        v_table_start_time := clock_timestamp();

        RAISE NOTICE 'Loading % ...', v_current_table;

        -- Clear existing product category reference records.
        TRUNCATE TABLE bronze.erp_px_cat_g1v2;

        -- Bulk-load ERP product category information.
        COPY bronze.erp_px_cat_g1v2
        FROM '/Users/saipraveenjavvadi/Downloads/sql-data-warehouse-project/datasets/source_erp/PX_CAT_G1V2.csv'
        WITH (
            FORMAT CSV,
            HEADER TRUE,
            DELIMITER ','
        );

        -- Capture records processed by the COPY command.
        GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;

        -- Log successful completion and execution duration.
        RAISE NOTICE 'SUCCESS | % | Rows: % | Duration: % seconds',
            v_current_table,
            v_rows_loaded,
            ROUND(
                EXTRACT(EPOCH FROM
                    (clock_timestamp() - v_table_start_time))::NUMERIC,
                3
            );


    -- ========================================================================
    -- STEP 3: EXCEPTION HANDLING
    -- ========================================================================
    -- PostgreSQL equivalent of SQL Server's TRY/CATCH mechanism.
    --
    -- On failure:
    --     1. Capture PostgreSQL error details.
    --     2. Identify the table being processed.
    --     3. Display SQLSTATE and error message.
    --     4. Display elapsed time before failure.
    --     5. Re-throw the exception to terminate the batch.
    --
    -- All database changes within this nested block are rolled back.
    -- ========================================================================

    EXCEPTION
        WHEN OTHERS THEN

            -- Retrieve information about the caught SQL exception.
            GET STACKED DIAGNOSTICS
                v_error_message = MESSAGE_TEXT,
                v_error_state = RETURNED_SQLSTATE;

            -- Log error details for troubleshooting.
            RAISE WARNING '----------------------------------------';
            RAISE WARNING 'BRONZE LAYER LOAD FAILED';
            RAISE WARNING 'Failed Table: %', v_current_table;
            RAISE WARNING 'SQLSTATE: %', v_error_state;
            RAISE WARNING 'Error Message: %', v_error_message;

            -- Record elapsed time for the failed table operation.
            RAISE WARNING 'Duration Before Failure: % seconds',
                ROUND(
                    EXTRACT(EPOCH FROM
                        (clock_timestamp() - v_table_start_time))::NUMERIC,
                    3
                );

            RAISE WARNING '----------------------------------------';

            -- Re-raise the exception to stop execution and report failure.
            RAISE;

    END;


    -- ========================================================================
    -- STEP 4: OVERALL BATCH EXECUTION SUMMARY
    -- ========================================================================
    -- Executed only when all six Bronze tables are loaded successfully.
    -- Calculates the total elapsed time of the complete ingestion batch.
    -- ========================================================================

    RAISE NOTICE '----------------------------------------';
    RAISE NOTICE 'Bronze layer loading completed';

    RAISE NOTICE 'Total Execution Time: % seconds',
        ROUND(
            EXTRACT(EPOCH FROM
                (clock_timestamp() - v_batch_start_time))::NUMERIC,
            3
        );

    RAISE NOTICE '----------------------------------------';

END;
$$;


-- =============================================================================
-- END OF SCRIPT
-- =============================================================================
-- The stored procedure bronze.load_bronze() has been defined.
--
-- Execute the procedure separately using:
--
--     CALL bronze.load_bronze();
--
-- Parameters:
--     None.
--
-- Expected Behavior:
--     1. Performs a full refresh of six Bronze tables.
--     2. Displays individual table load counts and execution times.
--     3. Displays total execution time upon successful completion.
--     4. Raises an exception and rolls back the batch upon failure.
--
-- Note:
--     Running CREATE OR REPLACE PROCEDURE only creates or updates
--     the procedure definition. It does not execute the data load.
--
-- Next Step:
--     Validate Bronze tables before implementing Silver transformations.
-- =============================================================================
