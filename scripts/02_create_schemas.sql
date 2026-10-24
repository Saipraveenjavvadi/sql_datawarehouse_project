/*
===============================================================================
Script Name : 02_create_schemas.sql
Description : Creates Bronze, Silver, and Gold schemas within the
              previously created datawarehouse database.

Prerequisites:
    1. Ensure the datawarehouse database has been created successfully
       using the 01_create_database.sql script.
    2. Connect the SQL editor to the datawarehouse database before
       executing this script.
    3. Ensure the database user has CREATE privileges on the database.

Schema Architecture:
    Bronze : Raw data ingested from source systems with minimal transformations.
    Silver : Cleaned, validated, and transformed data ready for further processing.
    Gold   : Business-ready, aggregated, and curated data for analytics and reporting.

Notes:
    1. IF NOT EXISTS prevents errors when a schema already exists.
    2. Existing schemas and their objects remain unchanged.
    3. PostgreSQL does not support USE DATABASE. The database must be
       selected through the connection before executing this script.
===============================================================================
*/

-- Verify that the active connection points to the datawarehouse database.
-- Expected Result: datawarehouse
SELECT current_database();

-- Create the Bronze schema to store raw data ingested from source systems.
CREATE SCHEMA IF NOT EXISTS bronze;

-- Create the Silver schema to store cleaned and transformed data.
CREATE SCHEMA IF NOT EXISTS silver;

-- Create the Gold schema to store business-ready data for analytics and reporting.
CREATE SCHEMA IF NOT EXISTS gold;

-- Verify that all three schemas were created successfully.
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('bronze', 'silver', 'gold')
ORDER BY schema_name;
