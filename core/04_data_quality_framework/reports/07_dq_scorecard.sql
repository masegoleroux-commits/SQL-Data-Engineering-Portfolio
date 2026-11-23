/* =============================================================================
   07_dq_scorecard.sql
   Views a dashboard (Power BI, Grafana) can read directly, plus the queries
   behind the screenshots in the README.
============================================================================= */

USE DataQuality;
GO

-- Latest result for every rule
CREATE OR ALTER VIEW dq.v_latest_results
AS
SELECT ru.rule_code, ru.quality_dimension, ru.target_table, ru.severity,
       r.status, r.failed_rows, r.total_rows, r.failed_pct, r.failed_sample, r.error_message,
       r.run_id, rn.started_at
FROM dq.rule AS ru
CROSS APPLY (SELECT TOP (1) res.*
             FROM dq.result AS res
             WHERE res.rule_id = ru.rule_id
             ORDER BY res.run_id DESC) AS r
INNER JOIN dq.run AS rn ON rn.run_id = r.run_id;
GO

-- Scorecard by quality dimension
CREATE OR ALTER VIEW dq.v_scorecard
AS
SELECT quality_dimension,
       COUNT(*)                                                       AS rules,
       SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END)               AS passed,
       SUM(CASE WHEN status <> 'PASS' THEN 1 ELSE 0 END)              AS not_passed,
       CAST(100.0 * SUM(CASE WHEN status = 'PASS' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 1)) AS rule_pass_pct,
       CAST(100 - 100.0 * SUM(failed_rows) / NULLIF(SUM(total_rows), 0) AS DECIMAL(6, 2))         AS row_quality_pct
FROM dq.v_latest_results
GROUP BY quality_dimension;
GO

-- How each rule moved between runs (LAG reads the previous run's value)
CREATE OR ALTER VIEW dq.v_rule_trend
AS
SELECT r.run_id,
       rn.run_label,
       ru.rule_code,
       r.failed_rows,
       LAG(r.failed_rows) OVER (PARTITION BY r.rule_id ORDER BY r.run_id) AS previous_failed_rows,
       r.status,
       CASE WHEN LAG(r.failed_rows) OVER (PARTITION BY r.rule_id ORDER BY r.run_id) IS NULL THEN 'first run'
            WHEN r.failed_rows < LAG(r.failed_rows) OVER (PARTITION BY r.rule_id ORDER BY r.run_id) THEN 'improved'
            WHEN r.failed_rows > LAG(r.failed_rows) OVER (PARTITION BY r.rule_id ORDER BY r.run_id) THEN 'got worse'
            ELSE 'no change' END AS trend
FROM dq.result AS r
INNER JOIN dq.run  AS rn ON rn.run_id  = r.run_id
INNER JOIN dq.rule AS ru ON ru.rule_id = r.rule_id;
GO

-- 1. Run history
SELECT run_id, run_label, rules_executed AS rules, rules_passed AS pass, rules_warned AS warn,
       rules_failed AS fail, rules_errored AS error, overall_status
FROM dq.run
ORDER BY run_id;

-- 2. Scorecard after remediation
SELECT * FROM dq.v_scorecard ORDER BY quality_dimension;

-- 3. Before and after, rules that changed
SELECT rule_code, previous_failed_rows AS before_fix, failed_rows AS after_fix, trend
FROM dq.v_rule_trend
WHERE run_label = N'After remediation' AND trend <> 'no change'
ORDER BY rule_code;

-- 4. Example of a failing-row sample, stored as JSON, shown as a table
SELECT j.customer_id, j.email
FROM dq.result AS r
INNER JOIN dq.rule AS ru ON ru.rule_id = r.rule_id
CROSS APPLY OPENJSON(r.failed_sample) WITH (customer_id INT, email NVARCHAR(150)) AS j
WHERE ru.rule_code = 'CUS_EMAIL_FORMAT'
  AND r.run_id = (SELECT MIN(run_id) FROM dq.run);
GO
