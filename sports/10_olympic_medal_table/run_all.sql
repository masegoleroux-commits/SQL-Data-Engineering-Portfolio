/* =============================================================================
   run_all.sql  (SQL Server, SSMS)
   Olympic medal table
   1. Query > SQLCMD Mode must be switched on.
   2. Set RepoPath to this project's folder and DataPath to its data\raw
      folder. Paths must not contain spaces and are written WITHOUT quotes.
   3. Execute (F5). The run stops at the first error or failed check.
============================================================================= */

:setvar RepoPath C:\SQL_Boulevard\sports\10_olympic_medal_table
:setvar DataPath C:\SQL_Boulevard\sports\10_olympic_medal_table\data\raw
:on error exit

SET NOCOUNT ON;
GO

PRINT 'Setup';
:r $(RepoPath)\00_setup\01_database_and_schemas.sql
:r $(RepoPath)\00_setup\02_business_parameters.sql
PRINT 'Bronze';
:r $(RepoPath)\01_bronze\01_load_bronze.sql
PRINT 'Silver';
:r $(RepoPath)\02_silver\01_build_silver.sql
PRINT 'Gold';
:r $(RepoPath)\03_gold\01_build_star_schema.sql
PRINT 'Quality';
:r $(RepoPath)\04_quality\01_quality_checks.sql
PRINT 'Analysis';
:r $(RepoPath)\05_analysis\01_analysis.sql
PRINT 'Model';
:r $(RepoPath)\06_ml\01_medal_forecast.sql
