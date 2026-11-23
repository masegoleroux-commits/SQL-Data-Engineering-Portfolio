/* =============================================================================
   03_create_rule_templates.sql
   Procedures that WRITE the SQL for common checks and register it.

   Safe dynamic SQL
   ----------------
   QUOTENAME(name)        wraps an identifier in [ ] and escapes any ] inside,
                          so a column called  Order Date  stays one name.
   QUOTENAME(text, '''')  wraps a value in quotes and doubles any quote inside
                          (O'Brien -> 'O''Brien').
   Allowed-value lists are stored in dq.accepted_value and read by the rule
   at run time, so user-supplied values never become part of the SQL text.
   Never build SQL by gluing raw input together with + : that is how SQL
   injection happens.
============================================================================= */

USE DataQuality;
GO

/* ---- Upsert a rule (used by every template) ------------------------------ */
CREATE OR ALTER PROCEDURE dq.usp_register_rule
    @rule_code        VARCHAR(50),
    @dimension        VARCHAR(20),
    @target_table     NVARCHAR(256),
    @description      NVARCHAR(300),
    @failing_rows_sql NVARCHAR(MAX),
    @total_rows_sql   NVARCHAR(MAX),
    @severity         VARCHAR(5)    = 'ERROR',
    @threshold_pct    DECIMAL(5, 2) = 0
AS
BEGIN
    SET NOCOUNT ON;

    MERGE dq.rule AS t
    USING (SELECT @rule_code AS rule_code) AS s
        ON t.rule_code = s.rule_code
    WHEN MATCHED THEN
        UPDATE SET quality_dimension = @dimension, target_table = @target_table, description = @description,
                   failing_rows_sql = @failing_rows_sql, total_rows_sql = @total_rows_sql,
                   severity = @severity, threshold_pct = @threshold_pct
    WHEN NOT MATCHED THEN
        INSERT (rule_code, quality_dimension, target_table, description, failing_rows_sql, total_rows_sql, severity, threshold_pct)
        VALUES (@rule_code, @dimension, @target_table, @description, @failing_rows_sql, @total_rows_sql, @severity, @threshold_pct);
END;
GO

/* ---- NOT NULL ----------------------------------------------------------- */
CREATE OR ALTER PROCEDURE dq.usp_add_not_null_rule
    @rule_code VARCHAR(50), @schema SYSNAME, @table SYSNAME, @column SYSNAME,
    @severity VARCHAR(5) = 'ERROR', @threshold_pct DECIMAL(5, 2) = 0
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @obj NVARCHAR(300) = QUOTENAME(@schema) + N'.' + QUOTENAME(@table),
            @desc NVARCHAR(300) = @column + N' must not be NULL',
            @fail NVARCHAR(MAX), @total NVARCHAR(MAX);

    SET @fail  = N'SELECT * FROM ' + @obj + N' WHERE ' + QUOTENAME(@column) + N' IS NULL';
    SET @total = N'SELECT COUNT(*) FROM ' + @obj;

    EXEC dq.usp_register_rule @rule_code, 'Completeness', @obj, @desc, @fail, @total, @severity, @threshold_pct;
END;
GO

/* ---- UNIQUE (one or more key columns, comma separated) ------------------- */
CREATE OR ALTER PROCEDURE dq.usp_add_unique_rule
    @rule_code VARCHAR(50), @schema SYSNAME, @table SYSNAME, @key_columns NVARCHAR(400),
    @severity VARCHAR(5) = 'ERROR'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @obj  NVARCHAR(300) = QUOTENAME(@schema) + N'.' + QUOTENAME(@table),
            @cols NVARCHAR(MAX),
            @desc NVARCHAR(300) = N'(' + @key_columns + N') must be unique',
            @fail NVARCHAR(MAX), @total NVARCHAR(MAX);

    SELECT @cols = STRING_AGG(QUOTENAME(LTRIM(RTRIM(value))), N', ')
    FROM STRING_SPLIT(@key_columns, N',');

    SET @fail  = N'SELECT ' + @cols + N', COUNT(*) AS copies FROM ' + @obj
               + N' GROUP BY ' + @cols + N' HAVING COUNT(*) > 1';
    SET @total = N'SELECT COUNT(*) FROM (SELECT DISTINCT ' + @cols + N' FROM ' + @obj + N') AS k';

    EXEC dq.usp_register_rule @rule_code, 'Uniqueness', @obj, @desc, @fail, @total, @severity, 0;
END;
GO

/* ---- ACCEPTED VALUES (pipe separated, case-sensitive) ------------------- */
-- The comparison uses a binary collation. With SQL Server's usual
-- case-insensitive collation 'gauteng' = 'Gauteng' is TRUE, which would
-- let badly typed values through.
CREATE OR ALTER PROCEDURE dq.usp_add_accepted_values_rule
    @rule_code VARCHAR(50), @schema SYSNAME, @table SYSNAME, @column SYSNAME,
    @values NVARCHAR(MAX), @severity VARCHAR(5) = 'ERROR'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @obj  NVARCHAR(300) = QUOTENAME(@schema) + N'.' + QUOTENAME(@table),
            @desc NVARCHAR(300) = @column + N' must be one of: ' + REPLACE(@values, N'|', N', '),
            @fail NVARCHAR(MAX), @total NVARCHAR(MAX);

    DELETE FROM dq.accepted_value WHERE rule_code = @rule_code;
    INSERT INTO dq.accepted_value (rule_code, accepted_value)
    SELECT DISTINCT @rule_code, LTRIM(RTRIM(value)) FROM STRING_SPLIT(@values, N'|');

    SET @fail = N'SELECT * FROM ' + @obj + N' AS t WHERE t.' + QUOTENAME(@column) + N' IS NOT NULL'
              + N' AND NOT EXISTS (SELECT 1 FROM dq.accepted_value AS a'
              + N' WHERE a.rule_code = ' + QUOTENAME(@rule_code, '''')
              + N' AND a.accepted_value COLLATE Latin1_General_BIN2 = t.' + QUOTENAME(@column) + N' COLLATE Latin1_General_BIN2'
              -- '=' ignores trailing spaces, so compare lengths as well
              + N' AND DATALENGTH(a.accepted_value) = DATALENGTH(t.' + QUOTENAME(@column) + N'))';
    SET @total = N'SELECT COUNT(*) FROM ' + @obj;

    EXEC dq.usp_register_rule @rule_code, 'Validity', @obj, @desc, @fail, @total, @severity, 0;
END;
GO

/* ---- RELATIONSHIP (foreign key that the raw tables do not enforce) ------ */
-- NOT EXISTS is the safe orphan test. NOT IN returns no rows at all if the
-- parent column contains a single NULL.
CREATE OR ALTER PROCEDURE dq.usp_add_relationship_rule
    @rule_code VARCHAR(50),
    @child_schema SYSNAME,  @child_table SYSNAME,  @child_column SYSNAME,
    @parent_schema SYSNAME, @parent_table SYSNAME, @parent_column SYSNAME,
    @severity VARCHAR(5) = 'ERROR'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @child  NVARCHAR(300) = QUOTENAME(@child_schema)  + N'.' + QUOTENAME(@child_table),
            @parent NVARCHAR(300) = QUOTENAME(@parent_schema) + N'.' + QUOTENAME(@parent_table),
            @desc   NVARCHAR(300) = CONCAT(N'every ', @child_table, N'.', @child_column, N' must exist in ', @parent_table, N'.', @parent_column),
            @fail NVARCHAR(MAX), @total NVARCHAR(MAX);

    SET @fail = N'SELECT c.* FROM ' + @child + N' AS c WHERE c.' + QUOTENAME(@child_column) + N' IS NOT NULL'
              + N' AND NOT EXISTS (SELECT 1 FROM ' + @parent + N' AS p WHERE p.' + QUOTENAME(@parent_column)
              + N' = c.' + QUOTENAME(@child_column) + N')';
    SET @total = N'SELECT COUNT(*) FROM ' + @child;

    EXEC dq.usp_register_rule @rule_code, 'Integrity', @child, @desc, @fail, @total, @severity, 0;
END;
GO

/* ---- RANGE (limits read from dq.setting or given as numbers) ------------- */
CREATE OR ALTER PROCEDURE dq.usp_add_range_rule
    @rule_code VARCHAR(50), @schema SYSNAME, @table SYSNAME, @column SYSNAME,
    @min DECIMAL(18, 4), @max DECIMAL(18, 4), @severity VARCHAR(5) = 'ERROR'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @obj  NVARCHAR(300) = QUOTENAME(@schema) + N'.' + QUOTENAME(@table),
            @desc NVARCHAR(300) = CONCAT(@column, N' must be between ', @min, N' and ', @max),
            @fail NVARCHAR(MAX), @total NVARCHAR(MAX);

    -- numbers are converted with CONVERT, not taken from free text
    SET @fail  = N'SELECT * FROM ' + @obj + N' WHERE ' + QUOTENAME(@column) + N' NOT BETWEEN '
               + CONVERT(NVARCHAR(40), @min) + N' AND ' + CONVERT(NVARCHAR(40), @max);
    SET @total = N'SELECT COUNT(*) FROM ' + @obj;

    EXEC dq.usp_register_rule @rule_code, 'Validity', @obj, @desc, @fail, @total, @severity, 0;
END;
GO
