/* =============================================================================
   06_test_framework.sql
   Tests the checker itself. A data quality tool that misses problems, or
   reports ones that are not there, is worse than none because people trust it.

   1. Detection     run 1 found exactly the known defects, rule by rule
   2. Remediation   run 2 has no ERROR-severity failures
   3. Nothing lost  remaining rows + quarantined rows = rows originally loaded
   4. Resilience    a broken rule is logged as ERROR and the run carries on
   5. Safety        an allowed value containing a quote cannot break a rule
============================================================================= */

USE DataQuality;
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS #results;
CREATE TABLE #results (test_id INT IDENTITY(1, 1), test_name VARCHAR(120), expected VARCHAR(20), actual VARCHAR(20));

DECLARE @run1 INT = (SELECT MIN(run_id) FROM dq.run WHERE run_label = 'Initial load'),
        @run2 INT = (SELECT MAX(run_id) FROM dq.run WHERE run_label = 'After remediation');

/* ---- 1. Detection ------------------------------------------------------- */
INSERT INTO #results (test_name, expected, actual)
SELECT 'Run 1 finds the known defects: ' + k.rule_code,
       CAST(k.expected_failed AS VARCHAR(20)),
       CAST(r.failed_rows AS VARCHAR(20))
FROM (VALUES ('CUS_EMAIL_NOT_NULL', 12), ('CUS_NAME_NOT_NULL', 0), ('PRD_CATEGORY_NOT_NULL', 2),
             ('ORD_DATE_NOT_NULL', 0),   ('CUS_ID_UNIQUE', 4),     ('PRD_ID_UNIQUE', 0),
             ('ORD_ID_UNIQUE', 0),       ('ITM_PK_UNIQUE', 0),     ('CUS_PROVINCE_VALID', 5),
             ('ORD_STATUS_VALID', 2),    ('ITM_QTY_POSITIVE', 4),  ('ITM_PRICE_RANGE', 3),
             ('CUS_EMAIL_FORMAT', 8),    ('ORD_DATE_NOT_FUTURE', 3), ('ORD_CUSTOMER_FK', 7),
             ('ITM_ORDER_FK', 0),        ('ITM_PRODUCT_FK', 0),    ('ORD_TOTAL_RECONCILES', 6),
             ('ORD_HAS_LINES', 0),       ('ORD_FRESHNESS', 0)) AS k (rule_code, expected_failed)
LEFT JOIN dq.rule   AS ru ON ru.rule_code = k.rule_code
LEFT JOIN dq.result AS r  ON r.rule_id = ru.rule_id AND r.run_id = @run1
ORDER BY k.rule_code;

INSERT INTO #results (test_name, expected, actual)
SELECT 'Run 1: missing emails WARN (2.4% > 1% tolerance)', 'WARN',
       (SELECT r.status FROM dq.result AS r INNER JOIN dq.rule AS ru ON ru.rule_id = r.rule_id
        WHERE ru.rule_code = 'CUS_EMAIL_NOT_NULL' AND r.run_id = @run1);

/* ---- 2. Remediation ----------------------------------------------------- */
INSERT INTO #results (test_name, expected, actual)
SELECT 'Run 2: no ERROR-severity rule fails', '0', CAST(COUNT(*) AS VARCHAR(20))
FROM dq.result AS r
INNER JOIN dq.rule AS ru ON ru.rule_id = r.rule_id
WHERE r.run_id = @run2 AND ru.severity = 'ERROR' AND r.status <> 'PASS';

INSERT INTO #results (test_name, expected, actual)
SELECT 'Run 2: overall WARN (lost emails cannot be recovered)', 'WARN',
       (SELECT overall_status FROM dq.run WHERE run_id = @run2);

/* ---- 3. Nothing lost ---------------------------------------------------- */
INSERT INTO #results (test_name, expected, actual)
SELECT 'customers: remaining + quarantined = 504 loaded', '504',
       CAST((SELECT COUNT(*) FROM raw_sales.customers)
          + (SELECT COUNT(*) FROM dq.quarantine WHERE source_table = N'raw_sales.customers') AS VARCHAR(20));

INSERT INTO #results (test_name, expected, actual)
SELECT 'orders: remaining + quarantined = 3000 loaded', '3000',
       CAST((SELECT COUNT(*) FROM raw_sales.orders)
          + (SELECT COUNT(*) FROM dq.quarantine WHERE source_table = N'raw_sales.orders') AS VARCHAR(20));

INSERT INTO #results (test_name, expected, actual)
SELECT 'order_items: remaining + quarantined = 6000 loaded', '6000',
       CAST((SELECT COUNT(*) FROM raw_sales.order_items)
          + (SELECT COUNT(*) FROM dq.quarantine WHERE source_table = N'raw_sales.order_items') AS VARCHAR(20));

INSERT INTO #results (test_name, expected, actual)
SELECT 'every quarantined row is valid JSON', '0',
       CAST((SELECT COUNT(*) FROM dq.quarantine WHERE ISJSON(row_data) = 0) AS VARCHAR(20));

/* ---- 4. Resilience ------------------------------------------------------ */
EXEC dq.usp_register_rule 'TEST_BROKEN_RULE', 'Validity', N'[raw_sales].[orders]', N'deliberately broken',
     N'SELECT * FROM raw_sales.orders WHERE no_such_column = 1', N'SELECT COUNT(*) FROM raw_sales.orders';

DECLARE @broken_rule INT = (SELECT rule_id FROM dq.rule WHERE rule_code = 'TEST_BROKEN_RULE'),
        @run3 INT;

EXEC dq.usp_run_checks @run_label = N'Resilience test', @run_id = @run3 OUTPUT;

INSERT INTO #results (test_name, expected, actual)
SELECT 'Broken rule is recorded as ERROR', 'ERROR',
       (SELECT status FROM dq.result WHERE run_id = @run3 AND rule_id = @broken_rule);

INSERT INTO #results (test_name, expected, actual)
SELECT 'Broken rule did not stop the other rules',
       CAST((SELECT COUNT(*) FROM dq.rule WHERE is_active = 1) AS VARCHAR(20)),
       CAST((SELECT rules_executed FROM dq.run WHERE run_id = @run3) AS VARCHAR(20));

INSERT INTO #results (test_name, expected, actual)
SELECT 'Error message is captured', 'yes',
       CASE WHEN (SELECT error_message FROM dq.result WHERE run_id = @run3 AND rule_id = @broken_rule)
                 LIKE '%no_such_column%' THEN 'yes' ELSE 'no' END;

DELETE FROM dq.run    WHERE run_id  = @run3;
DELETE FROM dq.result WHERE rule_id = @broken_rule;
DELETE FROM dq.rule   WHERE rule_id = @broken_rule;

/* ---- 5. Safety ---------------------------------------------------------- */
EXEC dq.usp_add_accepted_values_rule 'TEST_QUOTE_SAFE', 'raw_sales', 'customers', 'full_name',
     N'O''Brien|x''); DROP TABLE raw_sales.orders; --';

DECLARE @sql NVARCHAR(MAX) = (SELECT N'SELECT @n = COUNT(*) FROM (' + failing_rows_sql + N') AS f'
                              FROM dq.rule WHERE rule_code = 'TEST_QUOTE_SAFE'),
        @n BIGINT, @safe VARCHAR(3) = 'no';
BEGIN TRY
    EXEC sys.sp_executesql @sql, N'@n BIGINT OUTPUT', @n = @n OUTPUT;
    IF OBJECT_ID(N'raw_sales.orders') IS NOT NULL SET @safe = 'yes';
END TRY
BEGIN CATCH
    SET @safe = 'no';
END CATCH;

INSERT INTO #results (test_name, expected, actual)
VALUES ('Quotes in allowed values cannot inject SQL', 'yes', @safe);

DELETE FROM dq.accepted_value WHERE rule_code = 'TEST_QUOTE_SAFE';
DELETE FROM dq.rule           WHERE rule_code = 'TEST_QUOTE_SAFE';

/* ---- Results ------------------------------------------------------------ */
SELECT test_id, test_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM #results
ORDER BY test_id;

IF EXISTS (SELECT 1 FROM #results WHERE actual IS NULL OR expected <> actual)
    THROW 50004, 'Framework tests failed. See the results grid.', 1;
GO
