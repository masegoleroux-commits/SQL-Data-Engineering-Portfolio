/* =============================================================================
   05_quarantine_and_fix.sql
   Acts on what the first run found. Three ways to handle a bad row:

   FIX         the correct value can be worked out
               (trim and upper-case a status, map 'GP' to 'Gauteng',
               recalculate an order total from its lines)
   NULL OUT    the value is wrong and cannot be recovered, but the row is
               still useful (a malformed email). Completeness then warns.
   QUARANTINE  the row cannot be trusted (orphan order, future date,
               negative quantity). It moves to dq.quarantine as JSON, so
               nothing is lost and it can be replayed once fixed.

   Rows are removed with DELETE ... OUTPUT, which hands back exactly the
   rows deleted. Everything runs in one transaction.

   In a production pipeline raw would stay untouched and the fixes would
   land in a curated layer. Fixing raw in place keeps this demo short.
============================================================================= */

USE DataQuality;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @max_qty   DECIMAL(18, 4) = (SELECT setting_value FROM dq.setting WHERE setting_name = 'max_quantity'),
        @max_price DECIMAL(18, 4) = (SELECT setting_value FROM dq.setting WHERE setting_name = 'max_price');

BEGIN TRANSACTION;

/* 1. Exact duplicate customers: keep the first copy ----------------------- */
DROP TABLE IF EXISTS #removed_customers;
CREATE TABLE #removed_customers (customer_id INT, full_name NVARCHAR(100), email NVARCHAR(150),
                                 province NVARCHAR(50), created_at DATETIME2(0));

WITH ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY created_at) AS rn
    FROM raw_sales.customers
)
DELETE FROM ranked
OUTPUT deleted.customer_id, deleted.full_name, deleted.email, deleted.province, deleted.created_at
    INTO #removed_customers
WHERE rn > 1;

INSERT INTO dq.quarantine (source_table, rule_code, row_data)
SELECT N'raw_sales.customers', 'CUS_ID_UNIQUE',
       (SELECT r.customer_id, r.full_name, r.email, r.province, r.created_at FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
FROM #removed_customers AS r;

/* 2. Province: FIX through a mapping table; unknown becomes NULL ---------- */
DECLARE @province_map TABLE (raw_value NVARCHAR(50) PRIMARY KEY, clean_value NVARCHAR(50) NULL);
INSERT INTO @province_map VALUES
    (N'gp', N'Gauteng'), (N'gauteng', N'Gauteng'), (N'w. cape', N'Western Cape'),
    (N'wc', N'Western Cape'), (N'kzn', N'KwaZulu-Natal'), (N'unknown', NULL);

UPDATE c
SET    c.province = m.clean_value
FROM raw_sales.customers AS c
INNER JOIN @province_map AS m ON m.raw_value = LOWER(LTRIM(RTRIM(c.province)))
WHERE c.province COLLATE Latin1_General_BIN2 <> ISNULL(m.clean_value, N'') COLLATE Latin1_General_BIN2;

/* 3. Malformed emails: NULL OUT (same test as the CUS_EMAIL_FORMAT rule) --- */
UPDATE raw_sales.customers
SET    email = NULL
WHERE email IS NOT NULL
  AND (   email NOT LIKE '%_@_%._%' OR email LIKE '%@%@%' OR email LIKE '% %'
       OR email LIKE '%..%' OR email LIKE '%@.%' OR email LIKE '%.@%' OR email LIKE '%.');

/* 4. Products without a category: FIX with an explicit default ------------ */
UPDATE raw_sales.products SET category = N'Uncategorised' WHERE category IS NULL;

/* 5. Order status: FIX formatting first ---------------------------------- */
UPDATE raw_sales.orders
SET    status = UPPER(LTRIM(RTRIM(status)))
WHERE status COLLATE Latin1_General_BIN2 <> UPPER(LTRIM(RTRIM(status))) COLLATE Latin1_General_BIN2
   OR DATALENGTH(status) <> DATALENGTH(LTRIM(RTRIM(status)));

/* 6. QUARANTINE untrustworthy orders and their lines ---------------------- */
DROP TABLE IF EXISTS #bad_orders;
SELECT o.order_id,
       CASE WHEN NOT EXISTS (SELECT 1 FROM raw_sales.customers AS c WHERE c.customer_id = o.customer_id) THEN 'ORD_CUSTOMER_FK'
            WHEN o.order_date > CAST(SYSDATETIME() AS DATE) THEN 'ORD_DATE_NOT_FUTURE'
            ELSE 'ORD_STATUS_VALID' END AS rule_code
INTO #bad_orders
FROM raw_sales.orders AS o
WHERE NOT EXISTS (SELECT 1 FROM raw_sales.customers AS c WHERE c.customer_id = o.customer_id)
   OR o.order_date > CAST(SYSDATETIME() AS DATE)
   OR o.status NOT IN (N'COMPLETE', N'SHIPPED', N'RETURNED', N'CANCELLED');

DROP TABLE IF EXISTS #removed_items;
CREATE TABLE #removed_items (order_id INT, line_no INT, product_id INT, quantity INT, unit_price DECIMAL(10, 2));

DELETE i
OUTPUT deleted.order_id, deleted.line_no, deleted.product_id, deleted.quantity, deleted.unit_price INTO #removed_items
FROM raw_sales.order_items AS i
INNER JOIN #bad_orders AS b ON b.order_id = i.order_id;

INSERT INTO dq.quarantine (source_table, rule_code, row_data)
SELECT N'raw_sales.order_items', b.rule_code,
       (SELECT r.order_id, r.line_no, r.product_id, r.quantity, r.unit_price FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
FROM #removed_items AS r
INNER JOIN #bad_orders AS b ON b.order_id = r.order_id;

DROP TABLE IF EXISTS #removed_orders;
CREATE TABLE #removed_orders (order_id INT, customer_id INT, order_date DATE, status NVARCHAR(20),
                              order_total DECIMAL(12, 2), loaded_at DATETIME2(0));

DELETE o
OUTPUT deleted.order_id, deleted.customer_id, deleted.order_date, deleted.status, deleted.order_total, deleted.loaded_at
    INTO #removed_orders
FROM raw_sales.orders AS o
INNER JOIN #bad_orders AS b ON b.order_id = o.order_id;

INSERT INTO dq.quarantine (source_table, rule_code, row_data)
SELECT N'raw_sales.orders', b.rule_code,
       (SELECT r.order_id, r.customer_id, r.order_date, r.status, r.order_total, r.loaded_at FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
FROM #removed_orders AS r
INNER JOIN #bad_orders AS b ON b.order_id = r.order_id;

/* 7. QUARANTINE impossible line items ------------------------------------- */
TRUNCATE TABLE #removed_items;

DELETE FROM raw_sales.order_items
OUTPUT deleted.order_id, deleted.line_no, deleted.product_id, deleted.quantity, deleted.unit_price INTO #removed_items
WHERE quantity NOT BETWEEN 1 AND @max_qty
   OR unit_price NOT BETWEEN 1 AND @max_price;

INSERT INTO dq.quarantine (source_table, rule_code, row_data)
SELECT N'raw_sales.order_items',
       CASE WHEN r.quantity NOT BETWEEN 1 AND @max_qty THEN 'ITM_QTY_POSITIVE' ELSE 'ITM_PRICE_RANGE' END,
       (SELECT r.order_id, r.line_no, r.product_id, r.quantity, r.unit_price FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
FROM #removed_items AS r;

/* 8. Orders left with no lines after step 7 -------------------------------- */
TRUNCATE TABLE #removed_orders;

DELETE o
OUTPUT deleted.order_id, deleted.customer_id, deleted.order_date, deleted.status, deleted.order_total, deleted.loaded_at
    INTO #removed_orders
FROM raw_sales.orders AS o
WHERE NOT EXISTS (SELECT 1 FROM raw_sales.order_items AS i WHERE i.order_id = o.order_id);

INSERT INTO dq.quarantine (source_table, rule_code, row_data)
SELECT N'raw_sales.orders', 'ORD_HAS_LINES',
       (SELECT r.order_id, r.customer_id, r.order_date, r.status, r.order_total, r.loaded_at FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
FROM #removed_orders AS r;

/* 9. Header totals: FIX by recalculating from the lines -------------------- */
UPDATE o
SET    o.order_total = l.line_total
FROM raw_sales.orders AS o
INNER JOIN (SELECT order_id, SUM(quantity * unit_price) AS line_total
            FROM raw_sales.order_items GROUP BY order_id) AS l ON l.order_id = o.order_id
WHERE o.order_total <> l.line_total OR o.order_total IS NULL;

COMMIT TRANSACTION;

-- What went to quarantine
SELECT COALESCE(source_table, N'All tables') AS source_table,
       COALESCE(rule_code, 'All rules')       AS rule_code,
       COUNT(*)                               AS rows_quarantined
FROM dq.quarantine
GROUP BY ROLLUP (source_table, rule_code)
ORDER BY GROUPING(source_table), source_table, GROUPING(rule_code), rule_code;
GO
