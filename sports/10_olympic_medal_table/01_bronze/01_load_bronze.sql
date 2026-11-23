/* =============================================================================
   01_load_bronze.sql
   Bronze layer: each file loaded as delivered. Every column is text, so a
   bad value can never stop the load; problems are found and handled in
   silver, where they can be counted and explained.

   The folder comes from the SQLCMD variable DataPath set in run_all.sql.
   SQL Server reads the files with its own service account, so that account
   needs read access to the folder.
============================================================================= */

USE OlympicMedals;
GO

DROP TABLE IF EXISTS bronze.noc_regions;
CREATE TABLE bronze.noc_regions (
    noc                          NVARCHAR(200) NULL,
    region                       NVARCHAR(200) NULL,
    notes                        NVARCHAR(200) NULL
);

-- this file ends its lines with a carriage return only (old Mac style),
-- not a line feed, so the row terminator is 0x0d
BULK INSERT bronze.noc_regions
FROM '$(DataPath)\noc_regions.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0d', TABLOCK);

DROP TABLE IF EXISTS bronze.athlete_events_1992_2016;
CREATE TABLE bronze.athlete_events_1992_2016 (
    id                           NVARCHAR(200) NULL,
    name                         NVARCHAR(200) NULL,
    sex                          NVARCHAR(200) NULL,
    age                          NVARCHAR(200) NULL,
    height                       NVARCHAR(200) NULL,
    weight                       NVARCHAR(200) NULL,
    team                         NVARCHAR(200) NULL,
    noc                          NVARCHAR(200) NULL,
    games                        NVARCHAR(200) NULL,
    year                         NVARCHAR(200) NULL,
    season                       NVARCHAR(200) NULL,
    city                         NVARCHAR(200) NULL,
    sport                        NVARCHAR(200) NULL,
    event                        NVARCHAR(200) NULL,
    medal                        NVARCHAR(200) NULL
);

BULK INSERT bronze.athlete_events_1992_2016
FROM '$(DataPath)\athlete_events_1992_2016.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'noc_regions', COUNT(*) FROM bronze.noc_regions UNION ALL
SELECT 'bronze', 'athlete_events_1992_2016', COUNT(*) FROM bronze.athlete_events_1992_2016;
GO
