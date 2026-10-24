/*
===============================================================================
Script Name : 01_create_database.sql
Description : Drops the existing DATAWAREHOUSE database (if present)
              and creates a new empty database.

WARNING:
    1. DROP DATABASE permanently deletes all schemas, tables, views,
       functions, and data within the database.
    2. Ensure a valid backup exists before executing this script.
    3. Execute this script while connected to another database
       (e.g., postgres), not DATAWAREHOUSE.
    4. DROP DATABASE cannot execute inside a transaction block.
    5. Active connections may prevent the database from being dropped.

Usage       : Intended for local development or environment resets.
===============================================================================
*/

-- Drop the existing database if it exists to allow a clean recreation.
DROP DATABASE IF EXISTS datawarehouse;
