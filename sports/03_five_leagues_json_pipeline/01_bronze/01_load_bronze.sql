/* =============================================================================
   01_load_bronze.sql
   Bronze layer: the landing file holds one JSON document per line, one per
   league per season (30 lines). Each line is loaded whole into a single
   NVARCHAR(MAX) column. Nothing is parsed here, so a broken document can
   never stop the load; it is caught in silver.

   FIELDTERMINATOR is a tab: compact JSON never contains a raw tab (tabs
   inside strings are escaped as \t), so each line lands in one column.
   CODEPAGE 65001 keeps accented names such as Atlético and Köln intact.
============================================================================= */

USE FootballLeagues;
GO

DROP TABLE IF EXISTS bronze.api_landing;
CREATE TABLE bronze.api_landing (
    raw_document  NVARCHAR(MAX)  NULL
);

BULK INSERT bronze.api_landing
FROM '$(DataPath)\api_landing.jsonl'
WITH (FIELDTERMINATOR = '\t', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'api_landing', COUNT(*) FROM bronze.api_landing;
GO
