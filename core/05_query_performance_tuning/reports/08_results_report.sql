/* =============================================================================
   08_results_report.sql
   Before/after comparison: the numbers for the README results table.
============================================================================= */

USE QueryTuning;
GO

CREATE OR ALTER VIEW perf.v_before_after
AS
SELECT s.scenario_code,
       s.title,
       b.median_ms                                                       AS before_ms,
       a.median_ms                                                       AS after_ms,
       CAST(b.median_ms / NULLIF(a.median_ms, 0) AS DECIMAL(10, 1))      AS speedup_x,
       b.logical_reads                                                   AS before_reads,
       a.logical_reads                                                   AS after_reads,
       CASE WHEN b.result_rows = a.result_rows
             AND b.result_checksum = a.result_checksum THEN 1 ELSE 0 END AS same_result
FROM perf.scenario AS s
INNER JOIN perf.benchmark_summary AS b ON b.scenario_code = s.scenario_code AND b.phase = 'before'
INNER JOIN perf.benchmark_summary AS a ON a.scenario_code = s.scenario_code AND a.phase = 'after';
GO

-- 1. Before vs after (median of the timed runs, MAXDOP 1)
SELECT scenario_code, before_ms, after_ms, CONCAT(speedup_x, 'x') AS speedup,
       before_reads, after_reads, same_result
FROM perf.v_before_after
ORDER BY scenario_code;

-- 2. Control experiments: index added, query not rewritten
SELECT scenario_code, phase, median_ms, logical_reads
FROM perf.benchmark_summary
WHERE scenario_code IN ('S1_NON_SARGABLE_DATE', 'S5_CASE_INSENSITIVE_EMAIL')
ORDER BY scenario_code, median_ms DESC;

-- 3. What the indexes cost: the filtered index against a full-width one
SELECT i.name AS index_name,
       CAST(SUM(ps.used_page_count) * 8 / 1024.0 AS DECIMAL(8, 2)) AS size_mb,
       SUM(ps.row_count) AS index_rows
FROM sys.indexes AS i
INNER JOIN sys.dm_db_partition_stats AS ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE i.name IN ('ix_orders_pending', 'ix_orders_customer_ts')
GROUP BY i.name;

-- 4. Read the saved plan of any query: click the XML in the grid to open it
--    as a graphical plan in SSMS.
SELECT scenario_code, phase, TRY_CAST(plan_xml AS XML) AS execution_plan
FROM perf.benchmark_summary
ORDER BY scenario_code, phase;
GO
