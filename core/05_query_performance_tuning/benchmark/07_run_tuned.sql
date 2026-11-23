/* =============================================================================
   07_run_tuned.sql
   Measures every TUNED query under the same settings as the baseline, plus
   one control experiment.
============================================================================= */

USE QueryTuning;
GO

SET NOCOUNT ON;

DECLARE @code VARCHAR(40), @sql NVARCHAR(MAX);

DECLARE s CURSOR LOCAL FAST_FORWARD FOR
    SELECT scenario_code, tuned_sql FROM perf.scenario ORDER BY scenario_code;

OPEN s;
FETCH NEXT FROM s INTO @code, @sql;
WHILE @@FETCH_STATUS = 0
BEGIN
    PRINT CONCAT('Tuned: ', @code);
    EXEC perf.usp_benchmark @scenario_code = @code, @phase = 'after', @sql = @sql;
    FETCH NEXT FROM s INTO @code, @sql;
END;
CLOSE s;
DEALLOCATE s;

-- Control experiment: the ORIGINAL S1 query now that the index exists.
-- It is still slow, which proves the rewrite mattered, not just the index.
SELECT @sql = slow_sql FROM perf.scenario WHERE scenario_code = 'S1_NON_SARGABLE_DATE';
EXEC perf.usp_benchmark @scenario_code = 'S1_NON_SARGABLE_DATE', @phase = 'index, no rewrite', @sql = @sql;

-- Same control for S5: LOWER(email) cannot use the new email index either
SELECT @sql = slow_sql FROM perf.scenario WHERE scenario_code = 'S5_CASE_INSENSITIVE_EMAIL';
EXEC perf.usp_benchmark @scenario_code = 'S5_CASE_INSENSITIVE_EMAIL', @phase = 'index, no rewrite', @sql = @sql;
GO
