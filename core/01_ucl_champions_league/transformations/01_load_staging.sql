/* =============================================================================
   01_load_staging.sql
   Loads the four CSV files in data/raw/ into the stg_ tables.

   The folder comes from the SQLCMD variable DataPath set in run_all.sql.
   The path is read by the SQL Server service, so it has to be a location
   the service account can see (C:\SQL_Boulevard\... works; a folder in
   your user profile or OneDrive usually does not).

   Files are UTF-8 (player names such as Éder Militão, Beşiktaş), hence
   CODEPAGE 65001. FORMAT = 'CSV' needs SQL Server 2017 or later.
   Each BULK INSERT runs through EXEC: some SSMS set-ups check every batch
   on the client before sending it, and that checker rejects the CODEPAGE
   option. Inside EXEC the statement reaches SQL Server unchanged.
   Each table is truncated first, so the script can be re-run safely.
============================================================================= */

USE UCL;
GO

SET NOCOUNT ON;

TRUNCATE TABLE dbo.stg_attacking;
EXEC (N'BULK INSERT dbo.stg_attacking FROM ''$(DataPath)\attacking.csv'' WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', TABLOCK);');

TRUNCATE TABLE dbo.stg_defending;
EXEC (N'BULK INSERT dbo.stg_defending FROM ''$(DataPath)\defending.csv'' WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', TABLOCK);');

TRUNCATE TABLE dbo.stg_distribution;
EXEC (N'BULK INSERT dbo.stg_distribution FROM ''$(DataPath)\distribution.csv'' WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', TABLOCK);');

TRUNCATE TABLE dbo.stg_disciplinary;
EXEC (N'BULK INSERT dbo.stg_disciplinary FROM ''$(DataPath)\disciplinary.csv'' WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', TABLOCK);');

-- Expected: 176 / 627 / 608 / 584
SELECT 'stg_attacking'    AS table_name, COUNT(*) AS row_count FROM dbo.stg_attacking
UNION ALL
SELECT 'stg_defending',                  COUNT(*)              FROM dbo.stg_defending
UNION ALL
SELECT 'stg_distribution',               COUNT(*)              FROM dbo.stg_distribution
UNION ALL
SELECT 'stg_disciplinary',               COUNT(*)              FROM dbo.stg_disciplinary;
GO
