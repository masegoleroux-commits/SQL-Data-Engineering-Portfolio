/* =============================================================================
   01_load_bronze.sql
   Bronze layer: each file loaded as delivered. Every column is text, so a
   bad value can never stop the load; problems are found and handled in
   silver, where they can be counted and explained.

   The folder comes from the SQLCMD variable DataPath set in run_all.sql.
   SQL Server reads the files with its own service account, so that account
   needs read access to the folder.
============================================================================= */

USE MarathonResults;
GO

DROP TABLE IF EXISTS bronze.boston_marathon_2016;
CREATE TABLE bronze.boston_marathon_2016 (
    bib                          NVARCHAR(200) NULL,
    name                         NVARCHAR(200) NULL,
    age                          NVARCHAR(200) NULL,
    m_f                          NVARCHAR(200) NULL,
    city                         NVARCHAR(200) NULL,
    state                        NVARCHAR(200) NULL,
    country                      NVARCHAR(200) NULL,
    citizen                      NVARCHAR(200) NULL,
    unnamed_column               NVARCHAR(200) NULL,   -- blank header in the source file
    c_5k                         NVARCHAR(200) NULL,
    c_10k                        NVARCHAR(200) NULL,
    c_15k                        NVARCHAR(200) NULL,
    c_20k                        NVARCHAR(200) NULL,
    half                         NVARCHAR(200) NULL,
    c_25k                        NVARCHAR(200) NULL,
    c_30k                        NVARCHAR(200) NULL,
    c_35k                        NVARCHAR(200) NULL,
    c_40k                        NVARCHAR(200) NULL,
    pace                         NVARCHAR(200) NULL,
    proj_time                    NVARCHAR(200) NULL,
    official_time                NVARCHAR(200) NULL,
    overall                      NVARCHAR(200) NULL,
    gender                       NVARCHAR(200) NULL,
    division                     NVARCHAR(200) NULL
);

BULK INSERT bronze.boston_marathon_2016
FROM '$(DataPath)\boston_marathon_2016.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'boston_marathon_2016', COUNT(*) FROM bronze.boston_marathon_2016;
GO
