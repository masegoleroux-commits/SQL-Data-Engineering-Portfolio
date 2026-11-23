/* =============================================================================
   01_database_and_schemas.sql
   MarathonResults database with one schema per layer of the pipeline.

   ops     load log, cleaning log, quarantine, business parameters
   bronze  source data as delivered, every column stored as text
   silver  typed, cleaned and standardised rows
   gold    star schema and marts for reporting
   ml      features and model output
============================================================================= */

IF DB_ID(N'MarathonResults') IS NULL
    CREATE DATABASE MarathonResults;
GO

USE MarathonResults;
GO

IF SCHEMA_ID(N'ops')    IS NULL EXEC (N'CREATE SCHEMA ops');
IF SCHEMA_ID(N'bronze') IS NULL EXEC (N'CREATE SCHEMA bronze');
IF SCHEMA_ID(N'silver') IS NULL EXEC (N'CREATE SCHEMA silver');
IF SCHEMA_ID(N'gold')   IS NULL EXEC (N'CREATE SCHEMA gold');
IF SCHEMA_ID(N'ml')     IS NULL EXEC (N'CREATE SCHEMA ml');
GO

DROP TABLE IF EXISTS ops.load_log;
CREATE TABLE ops.load_log (
    layer        VARCHAR(10)   NOT NULL,
    table_name   VARCHAR(60)   NOT NULL,
    row_count    INT           NOT NULL,
    loaded_at    DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
);

DROP TABLE IF EXISTS ops.cleaning_log;
CREATE TABLE ops.cleaning_log (
    step_no        INT            NOT NULL,
    table_name     VARCHAR(60)    NOT NULL,
    step_name      VARCHAR(200)   NOT NULL,
    rows_affected  INT            NOT NULL,
    logged_at      DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME()
);

DROP TABLE IF EXISTS ops.quarantine;
CREATE TABLE ops.quarantine (
    source_table   VARCHAR(60)    NOT NULL,
    record_key     VARCHAR(60)    NOT NULL,
    rule_code      VARCHAR(40)    NOT NULL,
    detail         VARCHAR(400)   NULL,
    logged_at      DATETIME2(0)   NOT NULL DEFAULT SYSDATETIME()
);
GO
