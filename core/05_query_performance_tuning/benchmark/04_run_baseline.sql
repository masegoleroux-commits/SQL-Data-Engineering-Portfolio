/* =============================================================================
   04_run_baseline.sql
   Measures every SLOW query on the untuned tables (primary keys only).
   Measure before changing anything, or you cannot prove the change helped.
============================================================================= */

USE QueryTuning;
GO

SET NOCOUNT ON;

DECLARE @code VARCHAR(40), @sql NVARCHAR(MAX);

DECLARE s CURSOR LOCAL FAST_FORWARD FOR
    SELECT scenario_code, slow_sql FROM perf.scenario ORDER BY scenario_code;

OPEN s;
FETCH NEXT FROM s INTO @code, @sql;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT CONCAT('Baseline: ', @code);
    EXEC perf.usp_benchmark @scenario_code = @code, @phase = 'before', @sql = @sql;
    FETCH NEXT FROM s INTO @code, @sql;
END;
CLOSE s;
DEALLOCATE s;

SELECT scenario_code, median_ms, logical_reads, result_rows
FROM perf.benchmark_summary
WHERE phase = 'before'
ORDER BY scenario_code;
GO
