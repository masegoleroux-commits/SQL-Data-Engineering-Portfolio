/* =============================================================================
   run_all.sql
   Builds the UCL warehouse end to end, builds the ML feature table and runs
   every test.

   1. Open this file in SSMS and switch on Query > SQLCMD Mode.
   2. Set RepoPath to this project's folder and DataPath to its data\raw
      folder. Paths must not contain spaces and are written without quotes.
   3. Execute (F5).

   From the command line (SQL Server Express instance shown):
     sqlcmd -S .\SQLEXPRESS -E -i run_all.sql
============================================================================= */

:setvar RepoPath C:\SQL_Boulevard\core\01_ucl_champions_league
:setvar DataPath C:\SQL_Boulevard\core\01_ucl_champions_league\data\raw
:on error exit

PRINT '--- Stage 1-2: database and staging tables';
:r $(RepoPath)\ddl\01_create_database.sql
:r $(RepoPath)\ddl\02_staging_tables.sql

PRINT '--- Stage 2: load raw CSV files into staging';
:r $(RepoPath)\transformations\01_load_staging.sql

PRINT '--- Stage 3: profile the source before building on it';
:r $(RepoPath)\tests\00_profile_source.sql

PRINT '--- Stage 4: dimensional model';
:r $(RepoPath)\ddl\03_dimensions.sql
:r $(RepoPath)\ddl\04_facts.sql
:r $(RepoPath)\ddl\05_indexes.sql
:r $(RepoPath)\ddl\06_views.sql
:r $(RepoPath)\ddl\07_business_parameters.sql
:r $(RepoPath)\transformations\02_load_dimensions.sql
:r $(RepoPath)\transformations\03_load_facts.sql

PRINT '--- Stage 5: ML feature table';
:r $(RepoPath)\ml\01_player_features.sql

PRINT '--- Tests';
:r $(RepoPath)\tests\01_grain_checks.sql
:r $(RepoPath)\tests\02_referential_integrity.sql
:r $(RepoPath)\tests\03_reconciliation.sql
:r $(RepoPath)\tests\04_ml_feature_checks.sql
