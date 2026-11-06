# SQL Data Warehouse | PostgreSQL

A SQL-based data warehouse project built with **PostgreSQL**, following a **Bronze → Silver → Gold** medallion architecture. Raw CRM and ERP data is integrated and transformed into a reporting-friendly **star schema** with customer and product dimensions and a sales fact view.

> **Documentation scope:** This README documents the Gold-layer views and their known Silver-layer dependencies using the project's actual SQL definitions. Column types in the catalog are *logical/expected types*; use PostgreSQL's `information_schema.columns` to confirm deployed types. Bronze and Silver column-level catalogs can be added separately when their complete DDL is available.

## 1. Architecture overview

```text
CRM and ERP source files
         │
         ▼
  BRONZE (ingestion)
  Raw source tables
         │
         ▼
  SILVER (cleansing)
  Standardized CRM and ERP tables
         │
         ▼
  GOLD (reporting views)
  ├── gold.dim_customers
  ├── gold.dim_products
  └── gold.fact_sales
         │
         ▼
  SQL analytics / BI reporting
```

| Layer | Role | Implementation |
|---|---|---|
| Bronze | Land raw source records | PostgreSQL source tables |
| Silver | Clean, normalize, integrate, and validate data | PostgreSQL tables and ETL SQL |
| Gold | Expose dimensional reporting model | PostgreSQL regular views |

**Important:** Gold objects in this project are **regular views**, not materialized tables. Their results are computed from Silver data when queried.

## 2. Gold star schema and relationships

```text
      gold.dim_customers                   gold.dim_products
      ─────────────────                   ─────────────────
      customer_key (derived)              product_key (derived)
      customer_number (CRM ID)            product_id (CRM product key)
                │                                  │
                │ customer_number                  │ product_id
                │ = sls_cust_id                   │ = sls_prd_key
                ▼                                  ▼
                       gold.fact_sales
                       ───────────────
                       order_number
                       customer_key
                       product_key
                       customer_id
                       sales_date
                       ship_date
                       due_date
                       sales
                       sales_quantity
                       sales_price
```

The fact view performs **LEFT JOINs** to its dimension views, so sales records without a matching dimension still appear, with a `NULL` dimension key. Successful one-to-one matches require unique customer and active-product business keys in the dimensions.

### Source-to-target lineage

| Gold object | Silver input | Join/filter logic |
|---|---|---|
| `gold.dim_customers` | `silver.crm_cust_info` (`cci`) | Primary customer source |
| `gold.dim_customers` | `silver.erp_cust_az12` (`eca`) | `cci.cst_key = eca.cid` (LEFT JOIN) |
| `gold.dim_customers` | `silver.erp_loc_a101` (`ela`) | `cci.cst_key = ela.cid` (LEFT JOIN) |
| `gold.dim_products` | `silver.crm_prd_info` (`cpi`) | Only `cpi.prd_end_dt IS NULL` |
| `gold.dim_products` | `silver.erp_px_cat_g1v2` (`epcgv`) | `cpi.cat_id = epcgv.id` (LEFT JOIN) |
| `gold.fact_sales` | `silver.crm_sales_details` (`csd`) | Primary transaction source |
| `gold.fact_sales` | `gold.dim_customers` (`dc`) | `csd.sls_cust_id = dc.customer_number` (LEFT JOIN) |
| `gold.fact_sales` | `gold.dim_products` (`dp`) | `csd.sls_prd_key = dp.product_id` (LEFT JOIN) |

---

## 3. Data catalog

### 3.1 `gold.dim_customers` — Customer dimension

**Purpose:** Provides consolidated customer identity, demographic, and geographical attributes for analytics.

**Intended grain:** One record per customer (`customer_number`), **provided** the CRM input and the ERP lookup values are unique on their respective join keys.

**Primary business identifier:** `customer_number` (from CRM `cust_id`).  
**Derived key:** `customer_key` (calculated with `ROW_NUMBER()`, not persisted).  
**Population:** All records from `silver.crm_cust_info`, subject to possible multiplication if the ERP joins have duplicates.

| Column | Logical type* | Source / transformation | Business definition |
|---|---|---|---|
| `customer_key` | BIGINT | `ROW_NUMBER() OVER (ORDER BY cci.cst_key, cci.cst_create_date, cci.cust_id)` | Dynamically assigned dimension row identifier; **not stable across source changes** |
| `customer_number` | INTEGER | `cci.cust_id` | CRM system's customer number; used in sales joins |
| `customer_id` | TEXT | `cci.cst_key` | CRM customer business key used to link ERP attributes |
| `first_name` | TEXT | `cci.cst_firstname` | Customer first name |
| `last_name` | TEXT | `cci.cst_lastname` | Customer last name |
| `marital_status` | TEXT | `cci.cst_marital_status` | Standardized marital status from Silver |
| `create_date` | DATE | `cci.cst_create_date` | Customer record creation date |
| `dob` | DATE | `eca.bdate` | Customer date of birth from ERP |
| `gender` | TEXT | `CASE` combining `cci.cst_gndr` and `eca.gen` | CRM gender, falling back to ERP when CRM is `NULL` or `n/a` (case/whitespace insensitive) |
| `country` | TEXT | `ela.cntry` | Customer country from ERP location |

**Gender rule:**

```sql
CASE
    WHEN cci.cst_gndr IS NULL
      OR LOWER(TRIM(cci.cst_gndr)) = 'n/a'
    THEN eca.gen
    ELSE cci.cst_gndr
END AS gender
```

**Quality expectations:** No null business identifiers; unique `customer_number` and `customer_id` if modeled as one row per customer; missing ERP matches and missing demographics should be reviewed.

### 3.2 `gold.dim_products` — Product dimension

**Purpose:** Exposes active products enriched with category, subcategory, and maintenance metadata.

**Intended grain:** One row per active CRM product, assuming the category lookup has at most one match per category ID and active product IDs are unique.

**Business identifier:** `product_id` (from `cpi.prd_key`).  
**Derived key:** `product_key` (dynamically assigned with `ROW_NUMBER()`).  
**Population filter:** `cpi.prd_end_dt IS NULL` (active records as defined by this project).

| Column | Logical type* | Source / transformation | Business definition |
|---|---|---|---|
| `product_key` | BIGINT | `ROW_NUMBER() OVER (ORDER BY cpi.prd_start_dt, cpi.prd_key, cpi.prd_id)` | Dynamically assigned product dimension row identifier |
| `product_num` | INTEGER | `cpi.prd_id` | Internal CRM product number |
| `product_id` | TEXT | `cpi.prd_key` | CRM product business key used in sales joins |
| `product_name` | TEXT | `cpi.prd_nm` | Product name |
| `category_id` | TEXT | `cpi.cat_id` | CRM category identifier |
| `category` | TEXT | `epcgv.cat` | ERP category name |
| `subcategory` | TEXT | `epcgv.subcat` | ERP subcategory name |
| `maintenance` | Source-defined | `epcgv.maintenance` | ERP product maintenance attribute |
| `product_cost` | NUMERIC | `cpi.prd_cost` | Product cost, not the sales transaction price |
| `product_line` | TEXT | `cpi.prd_line` | Product line classification |
| `product_start_date` | DATE | `cpi.prd_start_dt` | Date product record became effective |

**Active-product rule:**

```sql
WHERE cpi.prd_end_dt IS NULL
```

**Quality expectations:** Unique non-null `product_id` among active records, no negative cost values, and review products missing category enrichment. The fact view can produce `NULL` `product_key` for sales relating to products excluded by the active-only filter.

### 3.3 `gold.fact_sales` — Sales fact

**Purpose:** Represents Silver sales records with dimension lookups and numeric measures for reporting.

**Intended grain:** One row per record in `silver.crm_sales_details`, assuming both dimension join keys are unique. An `order_number` **may repeat** if multiple sales lines exist; this model does not establish an order-line identifier.

**Dimension references:** `customer_key` and `product_key` derived from Gold views.  
**Measures:** `sales`, `sales_quantity`, `sales_price`.  
**Date attributes:** `sales_date`, `ship_date`, `due_date`.

| Column | Logical type* | Source / transformation | Business definition |
|---|---|---|---|
| `order_number` | TEXT / source-defined | `csd.sls_ord_num` | Source sales order number |
| `customer_key` | BIGINT | `dc.customer_key` via `csd.sls_cust_id = dc.customer_number` | Dynamic reference to customer dimension; can be `NULL` |
| `product_key` | BIGINT | `dp.product_key` via `csd.sls_prd_key = dp.product_id` | Dynamic reference to active product dimension; can be `NULL` |
| `customer_id` | INTEGER | `csd.sls_cust_id` | Original source customer number retained for traceability |
| `sales_date` | DATE | `csd.sls_order_dt` | Date the sales order was placed |
| `ship_date` | DATE | `csd.sls_ship_dt` | Order shipment date |
| `due_date` | DATE | `csd.sls_due_dt` | Order due date |
| `sales` | NUMERIC | `csd.sls_sales` | Sales amount, prepared in Silver |
| `sales_quantity` | INTEGER / NUMERIC | `csd.sls_quantity` | Number of units sold |
| `sales_price` | NUMERIC | `csd.sls_price` | Unit sale price, prepared in Silver |

**Measure consistency expectation:** `sales ≈ sales_quantity × sales_price` with an acceptable rounding tolerance (the existing QA file uses `0.01`). This is a validation rule rather than an expression calculated in the Gold fact view.

**Quality expectations:** Check missing dimension matches, invalid or missing measures, unreasonable dates, and total sales / row counts against Silver.

\* *Logical types describe expected semantics and should not be taken as authoritative PostgreSQL DDL; view column types are inherited from source expressions. For exact types, run the catalog query below.*

### 3.4 Verify actual deployed column types

```sql
SELECT
    table_name,
    ordinal_position,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'gold'
  AND table_name IN ('dim_customers', 'dim_products', 'fact_sales')
ORDER BY table_name, ordinal_position;
```

> A column listed as nullable/non-nullable by PostgreSQL metadata is not a substitute for actual data-quality validation. Regular views do not enforce primary-key or foreign-key constraints.

---

## 4. Key design decisions and limitations

1. **View-based Gold layer:** Reporting queries read current Silver data; no separate Gold refresh job is required, but repeated transformations/joins can affect query performance.
2. **Dynamic surrogate keys:** `customer_key` and `product_key` use `ROW_NUMBER()` in views. They can shift when Silver data changes. They are suitable for dynamic joins within the current model but **must not be treated as permanent IDs** by external persisted tables or extracts.
3. **No enforced PK/FK constraints on views:** Relationships are defined by SQL join conditions and must be validated by tests.
4. **Potential one-to-many join inflation:** Duplicate CRM/ERP lookup keys can multiply dimension or fact rows and inflate sales totals.
5. **Active products only:** Closed/historical product rows are excluded from `dim_products`; historical sales for these products may have missing `product_key` values.
6. **Current-state model:** The Gold views do not implement Slowly Changing Dimension Type 2 history. Consider persistent dimensions with identity-generated keys for SCD Type 2 or stable downstream relationships.
7. **Column naming:** The customer identifier is spelled `customer_id` (not `cusotmer_id`) in the supplied GitHub SQL script.

## 5. Data quality validation

The project includes a separate read-only SQL file: **`quality_checks_gold.sql`**. Place it in `tests/` and execute it after creating the Gold views.

| Area | Validation | Expected outcome |
|---|---|---|
| Customers | Null `customer_number` / `customer_id` | Zero affected rows |
| Customers | Duplicate customer numbers and IDs | Zero duplicate groups |
| Customers | Missing ERP matches and gender fallback | Review exceptions; some missing attributes may be legitimate |
| Products | Null and duplicate product identifiers | Zero affected rows |
| Products | Missing category attributes | Review exceptions |
| Products | Negative product cost | Zero affected rows |
| Fact sales | Missing customer or product dimension keys | Investigate unmatched joins |
| Fact sales | Negative amounts, nonpositive quantities, inconsistent extended price | Zero invalid rows, subject to business rules |
| Fact sales | Invalid date order or missing sales dates | Review exceptions |
| Reconciliation | `COUNT(*)` in Silver sales vs Gold fact | Equal if dimension joins do not multiply rows |
| Reconciliation | `SUM(sls_sales)` vs `SUM(sales)` | Equal if fact join cardinality is correct |
| Reconciliation | Active products in Silver vs Gold dimension | Equal if category joins do not multiply rows |

**Example — duplicate customer numbers:**

```sql
SELECT customer_number, COUNT(*) AS record_count
FROM gold.dim_customers
GROUP BY customer_number
HAVING COUNT(*) > 1;
```

**Example — unmatched fact dimensions:**

```sql
SELECT * FROM gold.fact_sales WHERE customer_key IS NULL;
SELECT * FROM gold.fact_sales WHERE product_key IS NULL;
```

**Example — Silver-to-Gold row count:**

```sql
SELECT
    (SELECT COUNT(*) FROM silver.crm_sales_details) AS silver_sales_rows,
    (SELECT COUNT(*) FROM gold.fact_sales) AS gold_sales_rows;
```

## 6. How to run

**Prerequisites:** PostgreSQL; `silver` source tables already created and populated; permissions to create views in the `gold` schema.

1. Run your Bronze and Silver setup/load scripts in dependency order.
2. Run the Gold view script to create the schema and reporting views.
3. Run the data quality script; investigate any returned exceptions.
4. Query the views for analytics or connect a reporting application.

Using `psql` from the repository root (adjust connection arguments as needed):

```bash
psql -d your_database -v ON_ERROR_STOP=1 -f scripts/gold/gold_layer_views.sql
psql -d your_database -v ON_ERROR_STOP=1 -f tests/quality_checks_gold.sql
```

Sample analytics queries:

```sql
-- Total sales by country
SELECT
    dc.country,
    SUM(fs.sales) AS total_sales
FROM gold.fact_sales fs
LEFT JOIN gold.dim_customers dc
    ON fs.customer_key = dc.customer_key
GROUP BY dc.country
ORDER BY total_sales DESC;

-- Sales by product category
SELECT
    dp.category,
    SUM(fs.sales) AS total_sales
FROM gold.fact_sales fs
LEFT JOIN gold.dim_products dp
    ON fs.product_key = dp.product_key
GROUP BY dp.category
ORDER BY total_sales DESC;
```

## 7. Suggested repository structure

```text
SQL-Data-Warehouse/
├── README.md
├── datasets/
├── scripts/
│   ├── bronze/
│   │   ├── ddl_bronze.sql
│   │   └── load_bronze.sql
│   ├── silver/
│   │   ├── ddl_silver.sql
│   │   └── load_silver.sql
│   └── gold/
│       └── gold_layer_views.sql
└── tests/
    └── quality_checks_gold.sql
```

The Bronze/Silver filenames are suggested placeholders; adjust the tree to match the actual repository. The two existing Gold SQL files in this project are `gold_layer_views.sql` and `quality_checks_gold.sql`.

## 8. SQL implementation notes

- `CREATE OR REPLACE VIEW` updates existing view definitions, but PostgreSQL may reject a replacement that renames/reorders existing columns. If replacing an older view with `cusotmer_id`, use `ALTER VIEW gold.dim_customers RENAME COLUMN cusotmer_id TO customer_id;` before applying the new definition, if needed.
- The sample view definitions assume the Silver date columns are already compatible with PostgreSQL `DATE` types.
- If source records change between separate queries, results from the dynamic views may change. For reproducible reporting, consider transaction snapshots or persisted Gold tables.

---

**Project focus:** SQL ETL, medallion architecture, CRM/ERP integration, dimensional modeling, source-to-target mapping, data-quality validation, and PostgreSQL analytics.
