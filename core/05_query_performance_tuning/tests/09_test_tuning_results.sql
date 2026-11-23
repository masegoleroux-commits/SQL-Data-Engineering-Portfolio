/* =============================================================================
   09_test_tuning_results.sql
   A faster wrong answer is worthless. These tests prove:
     1. every tuned query returns exactly the same rows as the slow one
     2. it is at least min_speedup times faster AND reads far fewer pages
        (reads are checked as well because timings vary between machines)
     3. the optimiser really uses the index designed for it
============================================================================= */

USE QueryTuning;
GO

SET NOCOUNT ON;

DECLARE @min_speedup DECIMAL(10, 2) = (SELECT param_value FROM perf.business_parameter WHERE param_name = 'min_speedup'),
        @max_ratio   DECIMAL(10, 2) = (SELECT param_value FROM perf.business_parameter WHERE param_name = 'max_reads_ratio');

DROP TABLE IF EXISTS #results;
CREATE TABLE #results (test_id INT IDENTITY(1, 1), test_name VARCHAR(120), passed BIT, detail NVARCHAR(200));

-- 1. Same answer
INSERT INTO #results (test_name, passed, detail)
SELECT scenario_code + ': same rows as the original', same_result, N'row count and checksum match'
FROM perf.v_before_after;

-- 2. Faster and lighter
INSERT INTO #results (test_name, passed, detail)
SELECT scenario_code + ': faster',
       CASE WHEN speedup_x >= @min_speedup THEN 1 ELSE 0 END,
       CONCAT(before_ms, N' ms -> ', after_ms, N' ms')
FROM perf.v_before_after;

INSERT INTO #results (test_name, passed, detail)
SELECT scenario_code + ': reads fewer pages',
       CASE WHEN after_reads <= before_reads * @max_ratio THEN 1 ELSE 0 END,
       CONCAT(before_reads, N' -> ', after_reads, N' logical reads')
FROM perf.v_before_after;

-- 3. Right plan: the expected index appears in the tuned plan
INSERT INTO #results (test_name, passed, detail)
SELECT s.scenario_code + ': plan uses ' + s.expected_index,
       CASE WHEN CHARINDEX(QUOTENAME(s.expected_index), b.plan_xml) > 0 THEN 1 ELSE 0 END,
       N'index name found in the cached execution plan'
FROM perf.scenario AS s
INNER JOIN perf.benchmark_summary AS b ON b.scenario_code = s.scenario_code AND b.phase = 'after'
WHERE s.expected_index IS NOT NULL;

-- Covering indexes: no key lookup back to the table
INSERT INTO #results (test_name, passed, detail)
SELECT b.scenario_code + ': no key lookups',
       CASE WHEN CHARINDEX(N'Lookup="1"', b.plan_xml) = 0 THEN 1 ELSE 0 END,
       N'covering index answers the query on its own'
FROM perf.benchmark_summary AS b
WHERE b.phase = 'after'
  AND b.scenario_code IN ('S1_NON_SARGABLE_DATE', 'S2_CUSTOMER_HISTORY', 'S3_COVERING_INDEX', 'S4_PENDING_QUEUE');

-- Controls: with the index in place but the query NOT rewritten, SQL Server
-- can only scan (a narrow index scan is cheaper than a table scan, but it
-- is still a scan). The rewritten query must read at least 5x fewer pages
-- than the un-rewritten one: the rewrite is what turns a scan into a seek.
INSERT INTO #results (test_name, passed, detail)
SELECT a.scenario_code + ': index alone is not enough (control)',
       CASE WHEN c.logical_reads >= a.logical_reads * 5 THEN 1 ELSE 0 END,
       CONCAT(c.logical_reads, N' reads with index but no rewrite, ', a.logical_reads, N' after rewrite')
FROM perf.benchmark_summary AS a
INNER JOIN perf.benchmark_summary AS c
    ON c.scenario_code = a.scenario_code AND c.phase = 'index, no rewrite'
WHERE a.phase = 'after';

SELECT test_id, test_name, CASE WHEN passed = 1 THEN 'PASS' ELSE 'FAIL' END AS result, detail
FROM #results
ORDER BY test_id;

IF EXISTS (SELECT 1 FROM #results WHERE passed = 0 OR passed IS NULL)
    THROW 50005, 'Tuning tests failed. See the results grid.', 1;
GO
