/* =============================================================================
   run_all.sql
   Builds the EuroLeagues database through all six stages and runs the tests.

   1. Open this file in SSMS and switch on Query > SQLCMD Mode.
   2. Set RepoPath to this project's folder and DataPath to its data\raw
      folder. Paths must not contain spaces and are written without quotes.
   3. Execute (F5). The run stops at the first error or failed test.

   Command line (SQL Server Express instance shown):
     sqlcmd -S .\SQLEXPRESS -E -i run_all.sql
============================================================================= */

:setvar RepoPath C:\SQL_Boulevard\core\02_european_top5_leagues
:setvar DataPath C:\SQL_Boulevard\core\02_european_top5_leagues\data\raw
:on error exit

PRINT '--- Setup: database, schemas, reference data, tables';
:r $(RepoPath)\ddl\01_create_database.sql
:r $(RepoPath)\ddl\02_reference_data.sql
:r $(RepoPath)\ddl\03_pipeline_tables.sql
:r $(RepoPath)\ddl\04_model_tables.sql

PRINT '--- Stage 1: raw';
:r $(RepoPath)\pipeline\01_load_raw.sql
PRINT '--- Stage 2: staging';
:r $(RepoPath)\pipeline\02_stage_typed.sql
PRINT '--- Stage 3: clean';
:r $(RepoPath)\pipeline\03_clean.sql
PRINT '--- Stage 4: model';
:r $(RepoPath)\pipeline\04_load_model.sql
:r $(RepoPath)\analysis\01_league_tables.sql

PRINT '--- Stage 5: machine learning';
:r $(RepoPath)\ml\01_team_form_features.sql
:r $(RepoPath)\ml\02_elo_ratings.sql
:r $(RepoPath)\ml\03_train_and_evaluate.sql
:r $(RepoPath)\ml\04_training_dataset_view.sql

PRINT '--- Tests';
:r $(RepoPath)\tests\01_pipeline_tests.sql
:r $(RepoPath)\tests\02_ml_tests.sql

PRINT '--- Done. Open the files in analysis\ to explore the results.';
