/* =============================================================================
   02_create_dq_framework.sql
   A metadata-driven data quality engine.

   Each check is a ROW in dq.rule holding a query that returns the FAILING
   rows. One procedure, dq.usp_run_checks, loops over the active rules, runs
   each query with dynamic SQL and records:
     how many rows failed, the % failed, PASS / WARN / FAIL / ERROR,
     and a JSON sample of the bad rows so an analyst can see them at once.

   Adding a check means adding a row. No code change, no deployment.

   dq.setting holds the framework's own business parameters
   (sample size, freshness limit).
============================================================================= */

USE DataQuality;
GO

IF SCHEMA_ID(N'dq') IS NULL EXEC (N'CREATE SCHEMA dq AUTHORIZATION dbo;');
GO

DROP TABLE IF EXISTS dq.quarantine;
DROP TABLE IF EXISTS dq.result;
DROP TABLE IF EXISTS dq.run;
DROP TABLE IF EXISTS dq.accepted_value;
DROP TABLE IF EXISTS dq.rule;
DROP TABLE IF EXISTS dq.setting;
GO

/* ---- Business parameters for the framework ------------------------------ */
CREATE TABLE dq.setting (
    setting_name    VARCHAR(50)     NOT NULL,
    setting_value   DECIMAL(12, 2)  NOT NULL,
    description     NVARCHAR(200)   NOT NULL,
    CONSTRAINT pk_dq_setting PRIMARY KEY (setting_name)
);

INSERT INTO dq.setting VALUES
    ('sample_rows',       5,  N'Failing rows saved as a JSON example per rule'),
    ('freshness_hours',   24, N'A table older than this many hours fails the freshness check'),
    ('max_price',         50000, N'Highest believable unit price (rand)'),
    ('max_quantity',      1000,  N'Highest believable quantity on one order line');

/* ---- Rule registry ------------------------------------------------------ */
CREATE TABLE dq.rule (
    rule_id           INT IDENTITY(1, 1) NOT NULL,
    rule_code         VARCHAR(50)    NOT NULL,
    quality_dimension VARCHAR(20)    NOT NULL,
    target_table      NVARCHAR(256)  NOT NULL,
    description       NVARCHAR(300)  NOT NULL,
    severity          VARCHAR(5)     NOT NULL CONSTRAINT df_rule_severity DEFAULT ('ERROR'),
    threshold_pct     DECIMAL(5, 2)  NOT NULL CONSTRAINT df_rule_threshold DEFAULT (0),   -- tolerated failure %
    failing_rows_sql  NVARCHAR(MAX)  NOT NULL,   -- SELECT that returns the bad rows
    total_rows_sql    NVARCHAR(MAX)  NOT NULL,   -- SELECT COUNT(*) for the denominator
    is_active         BIT            NOT NULL CONSTRAINT df_rule_active DEFAULT (1),
    created_at        DATETIME2(0)   NOT NULL CONSTRAINT df_rule_created DEFAULT SYSDATETIME(),
    CONSTRAINT pk_dq_rule PRIMARY KEY (rule_id),
    CONSTRAINT uq_dq_rule_code UNIQUE (rule_code),
    CONSTRAINT ck_dq_rule_dimension CHECK (quality_dimension IN
        ('Completeness', 'Uniqueness', 'Validity', 'Consistency', 'Integrity', 'Timeliness')),
    CONSTRAINT ck_dq_rule_severity CHECK (severity IN ('ERROR', 'WARN')),
    CONSTRAINT ck_dq_rule_threshold CHECK (threshold_pct BETWEEN 0 AND 100)
);

-- Lists of allowed values live in a table, not inside the SQL text, so a
-- value containing a quote can never break or inject into a rule.
CREATE TABLE dq.accepted_value (
    rule_code       VARCHAR(50)    NOT NULL,
    accepted_value  NVARCHAR(100)  NOT NULL,
    CONSTRAINT pk_dq_accepted_value PRIMARY KEY (rule_code, accepted_value)
);

/* ---- Runs and results --------------------------------------------------- */
CREATE TABLE dq.run (
    run_id          INT IDENTITY(1, 1) NOT NULL,
    run_label       NVARCHAR(100)  NULL,
    started_at      DATETIME2(3)   NOT NULL CONSTRAINT df_run_started DEFAULT SYSDATETIME(),
    finished_at     DATETIME2(3)   NULL,
    rules_executed  INT NULL, rules_passed INT NULL, rules_warned INT NULL,
    rules_failed    INT NULL, rules_errored INT NULL,
    overall_status  VARCHAR(5)     NULL,
    CONSTRAINT pk_dq_run PRIMARY KEY (run_id)
);

CREATE TABLE dq.result (
    run_id          INT            NOT NULL,
    rule_id         INT            NOT NULL,
    total_rows      BIGINT         NULL,
    failed_rows     BIGINT         NULL,
    failed_pct      DECIMAL(7, 3)  NULL,
    status          VARCHAR(5)     NOT NULL,
    failed_sample   NVARCHAR(MAX)  NULL,     -- JSON
    error_message   NVARCHAR(2000) NULL,
    duration_ms     INT            NULL,
    CONSTRAINT pk_dq_result PRIMARY KEY (run_id, rule_id),
    CONSTRAINT fk_dq_result_run  FOREIGN KEY (run_id)  REFERENCES dq.run (run_id) ON DELETE CASCADE,
    CONSTRAINT fk_dq_result_rule FOREIGN KEY (rule_id) REFERENCES dq.rule (rule_id),
    CONSTRAINT ck_dq_result_status CHECK (status IN ('PASS', 'WARN', 'FAIL', 'ERROR')),
    CONSTRAINT ck_dq_result_json CHECK (failed_sample IS NULL OR ISJSON(failed_sample) = 1)
);

/* ---- Quarantine: removed rows are kept as JSON, never thrown away -------- */
CREATE TABLE dq.quarantine (
    quarantine_id   BIGINT IDENTITY(1, 1) NOT NULL,
    source_table    NVARCHAR(256)  NOT NULL,
    rule_code       VARCHAR(50)    NOT NULL,
    row_data        NVARCHAR(MAX)  NOT NULL,
    quarantined_at  DATETIME2(0)   NOT NULL CONSTRAINT df_quarantine_at DEFAULT SYSDATETIME(),
    CONSTRAINT pk_dq_quarantine PRIMARY KEY (quarantine_id),
    CONSTRAINT ck_dq_quarantine_json CHECK (ISJSON(row_data) = 1)
);
GO

/* ---- The engine --------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dq.usp_run_checks
    @run_label  NVARCHAR(100) = NULL,
    @dimension  VARCHAR(20)   = NULL,     -- run one quality dimension only
    @run_id     INT           = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @sample_rows INT = (SELECT setting_value FROM dq.setting WHERE setting_name = 'sample_rows');

    INSERT INTO dq.run (run_label) VALUES (@run_label);
    SET @run_id = SCOPE_IDENTITY();

    DECLARE @rule_id INT, @failing_sql NVARCHAR(MAX), @total_sql NVARCHAR(MAX),
            @severity VARCHAR(5), @threshold DECIMAL(5, 2),
            @total BIGINT, @failed BIGINT, @pct DECIMAL(7, 3), @status VARCHAR(5),
            @sample NVARCHAR(MAX), @sql NVARCHAR(MAX), @t0 DATETIME2(3);

    DECLARE rule_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT rule_id, failing_rows_sql, total_rows_sql, severity, threshold_pct
        FROM dq.rule
        WHERE is_active = 1
          AND (@dimension IS NULL OR quality_dimension = @dimension)
        ORDER BY rule_id;

    OPEN rule_cursor;
    FETCH NEXT FROM rule_cursor INTO @rule_id, @failing_sql, @total_sql, @severity, @threshold;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @t0 = SYSDATETIME();

        -- A broken rule is logged as ERROR and the loop carries on:
        -- one bad rule must never stop the others from running.
        BEGIN TRY
            SET @sql = N'SELECT @n = (' + @total_sql + N');';
            EXEC sys.sp_executesql @sql, N'@n BIGINT OUTPUT', @n = @total OUTPUT;

            SET @sql = N'SELECT @n = COUNT_BIG(*) FROM (' + @failing_sql + N') AS f;';
            EXEC sys.sp_executesql @sql, N'@n BIGINT OUTPUT', @n = @failed OUTPUT;

            SET @sql = N'SELECT @s = (SELECT TOP (@k) * FROM (' + @failing_sql + N') AS f FOR JSON PATH, INCLUDE_NULL_VALUES);';
            EXEC sys.sp_executesql @sql, N'@k INT, @s NVARCHAR(MAX) OUTPUT', @k = @sample_rows, @s = @sample OUTPUT;

            SET @pct = CASE WHEN @total > 0 THEN 100.0 * @failed / @total ELSE 0 END;

            SET @status = CASE WHEN @failed = 0           THEN 'PASS'
                               WHEN @pct <= @threshold    THEN 'PASS'
                               WHEN @severity = 'WARN'    THEN 'WARN'
                               ELSE 'FAIL' END;

            INSERT INTO dq.result (run_id, rule_id, total_rows, failed_rows, failed_pct, status, failed_sample, duration_ms)
            VALUES (@run_id, @rule_id, @total, @failed, @pct, @status, @sample, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()));
        END TRY
        BEGIN CATCH
            INSERT INTO dq.result (run_id, rule_id, status, error_message, duration_ms)
            VALUES (@run_id, @rule_id, 'ERROR',
                    CONCAT(ERROR_NUMBER(), N': ', ERROR_MESSAGE()),
                    DATEDIFF(MILLISECOND, @t0, SYSDATETIME()));
        END CATCH;

        FETCH NEXT FROM rule_cursor INTO @rule_id, @failing_sql, @total_sql, @severity, @threshold;
    END;

    CLOSE rule_cursor;
    DEALLOCATE rule_cursor;

    UPDATE r
    SET finished_at    = SYSDATETIME(),
        rules_executed = s.n,
        rules_passed   = s.pass,
        rules_warned   = s.warn,
        rules_failed   = s.fail,
        rules_errored  = s.err,
        overall_status = CASE WHEN s.fail + s.err > 0 THEN 'FAIL'
                              WHEN s.warn > 0          THEN 'WARN'
                              ELSE 'PASS' END
    FROM dq.run AS r
    CROSS APPLY (SELECT COUNT(*)                                          AS n,
                        SUM(CASE WHEN status = 'PASS'  THEN 1 ELSE 0 END) AS pass,
                        SUM(CASE WHEN status = 'WARN'  THEN 1 ELSE 0 END) AS warn,
                        SUM(CASE WHEN status = 'FAIL'  THEN 1 ELSE 0 END) AS fail,
                        SUM(CASE WHEN status = 'ERROR' THEN 1 ELSE 0 END) AS err
                 FROM dq.result WHERE run_id = @run_id) AS s
    WHERE r.run_id = @run_id;

    SELECT run_id, run_label, rules_executed, rules_passed, rules_warned, rules_failed, rules_errored, overall_status
    FROM dq.run WHERE run_id = @run_id;
END;
GO
