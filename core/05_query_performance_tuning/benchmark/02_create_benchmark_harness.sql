/* =============================================================================
   02_create_benchmark_harness.sql
   A repeatable way to MEASURE queries instead of guessing.

   perf.usp_benchmark @scenario, @phase, @sql, @runs
     1. runs the query once to warm the cache (not recorded)
     2. runs it @runs more times, recording elapsed time and logical reads
        (logical reads = 8 KB pages touched; far more stable than time)
     3. stores a checksum of the result rows, so the tuned query can be
        proven to return exactly what the slow one did
     4. saves the execution plan from the plan cache, so tests can check
        which index the optimiser actually used
     5. keeps the MEDIAN time (one slow outlier does not distort it)

   Each query runs as  SELECT * INTO #sink FROM (<query>) AS q  so all rows
   are produced without flooding SSMS with result grids.
============================================================================= */

USE QueryTuning;
GO

DROP TABLE IF EXISTS perf.benchmark_summary;
DROP TABLE IF EXISTS perf.benchmark_run;
DROP TABLE IF EXISTS perf.scenario;
DROP TABLE IF EXISTS perf.business_parameter;
GO

-- Settings for the benchmark and the pass mark for the tests
CREATE TABLE perf.business_parameter (
    param_name    VARCHAR(50)    NOT NULL PRIMARY KEY,
    param_value   DECIMAL(10, 2) NOT NULL,
    description   NVARCHAR(200)  NOT NULL
);
INSERT INTO perf.business_parameter VALUES
    ('benchmark_runs',      5,  N'Timed runs per query (after one warm-up run)'),
    ('min_speedup',         2,  N'A tuned query must be at least this many times faster to pass'),
    ('max_reads_ratio',     0.5, N'Tuned logical reads must be at most this share of the original');

CREATE TABLE perf.scenario (
    scenario_code   VARCHAR(40)    NOT NULL PRIMARY KEY,
    title           NVARCHAR(100)  NOT NULL,
    problem         NVARCHAR(400)  NOT NULL,
    fix             NVARCHAR(400)  NOT NULL,
    slow_sql        NVARCHAR(MAX)  NOT NULL,
    tuned_sql       NVARCHAR(MAX)  NOT NULL,
    expected_index  SYSNAME        NULL        -- index the tuned plan should use
);

CREATE TABLE perf.benchmark_run (
    scenario_code   VARCHAR(40)    NOT NULL,
    phase           VARCHAR(30)    NOT NULL,
    run_no          TINYINT        NOT NULL,
    elapsed_ms      DECIMAL(12, 3) NOT NULL,
    logical_reads   BIGINT         NOT NULL,
    CONSTRAINT pk_benchmark_run PRIMARY KEY (scenario_code, phase, run_no)
);

CREATE TABLE perf.benchmark_summary (
    scenario_code   VARCHAR(40)    NOT NULL,
    phase           VARCHAR(30)    NOT NULL,
    median_ms       DECIMAL(12, 3) NOT NULL,
    logical_reads   BIGINT         NOT NULL,
    result_rows     INT            NOT NULL,
    result_checksum INT            NULL,
    plan_xml        NVARCHAR(MAX)  NULL,
    measured_at     DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT pk_benchmark_summary PRIMARY KEY (scenario_code, phase)
);
GO

CREATE OR ALTER PROCEDURE perf.usp_benchmark
    @scenario_code VARCHAR(40),
    @phase         VARCHAR(30),
    @sql           NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @runs   INT = (SELECT param_value FROM perf.business_parameter WHERE param_name = 'benchmark_runs'),
            @marker NVARCHAR(100) = CONCAT(N'/* bench:', @scenario_code, N':', @phase, N' */'),
            @stmt   NVARCHAR(MAX),
            @i      INT = 0,
            @t0     DATETIME2(7),
            @reads0 BIGINT,
            @reads1 BIGINT,
            @rows   INT,
            @chk    INT;

    DELETE FROM perf.benchmark_run     WHERE scenario_code = @scenario_code AND phase = @phase;
    DELETE FROM perf.benchmark_summary WHERE scenario_code = @scenario_code AND phase = @phase;

    -- The marker comment makes the statement easy to find in the plan cache.
    -- MAXDOP 1 keeps timings comparable across machines with different core counts.
    SET @stmt = @marker + N' SELECT * INTO #sink FROM (' + @sql + N') AS q OPTION (MAXDOP 1);'
              + N' SELECT @rows = COUNT(*), @chk = CHECKSUM_AGG(BINARY_CHECKSUM(*)) FROM #sink;';

    WHILE @i <= @runs          -- run 0 is the warm-up
    BEGIN
        SELECT @reads0 = logical_reads FROM sys.dm_exec_requests WHERE session_id = @@SPID;
        SET @t0 = SYSDATETIME();

        EXEC sys.sp_executesql @stmt, N'@rows INT OUTPUT, @chk INT OUTPUT', @rows = @rows OUTPUT, @chk = @chk OUTPUT;

        IF @i > 0
        BEGIN
            SELECT @reads1 = logical_reads FROM sys.dm_exec_requests WHERE session_id = @@SPID;
            INSERT INTO perf.benchmark_run (scenario_code, phase, run_no, elapsed_ms, logical_reads)
            VALUES (@scenario_code, @phase, @i,
                    DATEDIFF_BIG(MICROSECOND, @t0, SYSDATETIME()) / 1000.0,
                    @reads1 - @reads0);
        END;
        SET @i += 1;
    END;

    -- Median with PERCENTILE_CONT (a window function, so TOP (1) picks one row)
    DECLARE @median DECIMAL(12, 3), @min_reads BIGINT, @plan NVARCHAR(MAX);

    SELECT TOP (1)
           @median    = PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY elapsed_ms) OVER (),
           @min_reads = MIN(logical_reads) OVER ()
    FROM perf.benchmark_run
    WHERE scenario_code = @scenario_code AND phase = @phase;

    SELECT TOP (1) @plan = CAST(qp.query_plan AS NVARCHAR(MAX))
    FROM sys.dm_exec_query_stats AS qs
    CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS st
    CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) AS qp
    WHERE st.text LIKE @marker + N'%'
    ORDER BY qs.last_execution_time DESC;

    INSERT INTO perf.benchmark_summary (scenario_code, phase, median_ms, logical_reads, result_rows, result_checksum, plan_xml)
    VALUES (@scenario_code, @phase, @median, @min_reads, @rows, @chk, @plan);

    SELECT scenario_code, phase, median_ms, logical_reads, result_rows
    FROM perf.benchmark_summary
    WHERE scenario_code = @scenario_code AND phase = @phase;
END;
GO
