FROM silver.crm_sales_details
WHERE sls_sales IS NOT NULL
  AND sls_quantity IS NOT NULL
  AND sls_price IS NOT NULL
  AND ABS(sls_sales::numeric - (sls_quantity * sls_price)) > 0.01;

-- 03F. Sales customer ID should exist in Silver CRM customer dimension.
SELECT s.*
FROM silver.crm_sales_details AS s
LEFT JOIN silver.crm_cust_info AS c ON c.cust_id = s.sls_cust_id
WHERE s.sls_cust_id IS NOT NULL AND c.cust_id IS NULL;

-- 03G. Sales product key should exist in Silver CRM product history.
SELECT s.*
FROM silver.crm_sales_details AS s
WHERE s.sls_prd_key IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM silver.crm_prd_info AS p
      WHERE p.prd_key = s.sls_prd_key
  );

-- ============================================================================
-- 04. ERP CUSTOMER: normalized identifiers, dates and gender
-- ============================================================================

-- 04A. Missing or repeated ERP customer IDs.
SELECT * FROM silver.erp_cust_az12 WHERE NULLIF(BTRIM(cid), '') IS NULL;
SELECT cid, COUNT(*) AS duplicate_count
FROM silver.erp_cust_az12
GROUP BY cid HAVING COUNT(*) > 1;

-- 04B. NAS prefix should have been removed.
SELECT * FROM silver.erp_cust_az12 WHERE cid LIKE 'NAS%';

-- 04C. Future birth dates should have been cleared; null dates may be allowed.
SELECT * FROM silver.erp_cust_az12 WHERE bdate > CURRENT_DATE;

-- 04D. Standardized genders only.
SELECT * FROM silver.erp_cust_az12
WHERE gen IS NULL OR gen NOT IN ('Male', 'Female', 'n/a');

-- ============================================================================
-- 05. ERP LOCATION: keys, uniqueness and country normalization
-- ============================================================================

-- 05A. Missing customer IDs, or IDs that still contain hyphens.
SELECT * FROM silver.erp_loc_a101
WHERE NULLIF(BTRIM(cid), '') IS NULL OR cid LIKE '%-%';

-- 05B. Expect one location per customer only if source grain guarantees it.
SELECT cid, COUNT(*) AS duplicate_count
FROM silver.erp_loc_a101
GROUP BY cid HAVING COUNT(*) > 1;

-- 05C. Null/blank/non-standardized country values.
SELECT * FROM silver.erp_loc_a101
WHERE NULLIF(BTRIM(cntry), '') IS NULL
   OR cntry <> BTRIM(cntry)
   OR UPPER(cntry) IN ('US', 'USA', 'DE');

-- ============================================================================
-- 06. ERP PRODUCT CATEGORY: required attributes and duplicate category IDs
-- ============================================================================

-- 06A. Required category identifiers and hierarchy labels.
SELECT * FROM silver.erp_px_cat_g1v2
WHERE NULLIF(BTRIM(id), '') IS NULL
   OR NULLIF(BTRIM(cat), '') IS NULL
   OR NULLIF(BTRIM(subcat), '') IS NULL;

-- 06B. Duplicate category IDs.
SELECT id, COUNT(*) AS duplicate_count
FROM silver.erp_px_cat_g1v2
GROUP BY id HAVING COUNT(*) > 1;

-- ============================================================================
-- 07. CROSS-SOURCE INTEGRITY: source keys and category references
-- ============================================================================

-- 07A. ERP customer IDs without a corresponding CRM customer key.
SELECT e.cid
FROM silver.erp_cust_az12 AS e
WHERE e.cid IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM silver.crm_cust_info AS c WHERE c.cst_key = e.cid
  );

-- 07B. ERP location IDs without a corresponding CRM customer key.
SELECT l.cid
FROM silver.erp_loc_a101 AS l
WHERE l.cid IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM silver.crm_cust_info AS c WHERE c.cst_key = l.cid
  );

-- 07C. CRM product categories missing from ERP category reference.
SELECT DISTINCT p.cat_id
FROM silver.crm_prd_info AS p
WHERE p.cat_id IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM silver.erp_px_cat_g1v2 AS e WHERE e.id = p.cat_id
  );

-- ============================================================================
-- 08. LOAD METADATA: audit timestamp should always be populated
-- ============================================================================

SELECT 'crm_cust_info' AS table_name, COUNT(*) AS missing_audit_rows
FROM silver.crm_cust_info WHERE dwh_create_date IS NULL
UNION ALL
SELECT 'crm_prd_info', COUNT(*) FROM silver.crm_prd_info WHERE dwh_create_date IS NULL
UNION ALL
SELECT 'crm_sales_details', COUNT(*) FROM silver.crm_sales_details WHERE dwh_create_date IS NULL
UNION ALL
SELECT 'erp_cust_az12', COUNT(*) FROM silver.erp_cust_az12 WHERE dwh_create_date IS NULL
UNION ALL
SELECT 'erp_loc_a101', COUNT(*) FROM silver.erp_loc_a101 WHERE dwh_create_date IS NULL
UNION ALL
SELECT 'erp_px_cat_g1v2', COUNT(*) FROM silver.erp_px_cat_g1v2 WHERE dwh_create_date IS NULL;

-- ============================================================================
-- 09. ROW COUNT SUMMARY: inspect counts; there is no universal minimum count
-- ============================================================================

SELECT 'crm_cust_info' AS table_name, COUNT(*) AS row_count FROM silver.crm_cust_info
UNION ALL
SELECT 'crm_prd_info', COUNT(*) FROM silver.crm_prd_info
UNION ALL
