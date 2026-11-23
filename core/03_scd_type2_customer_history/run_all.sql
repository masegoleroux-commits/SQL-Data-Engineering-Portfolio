/* =============================================================================
   run_all.sql
   Builds the CustomerHistory database, loads four monthly batches through
   the SCD Type 2 procedure and runs the tests.

   1. Open in SSMS, switch on Query > SQLCMD Mode.
   2. Set RepoPath to this project's folder.
   3. Execute (F5).

   Command line:
     sqlcmd -S .\SQLEXPRESS -E -I -i run_all.sql -v RepoPath="C:\SQL_Boulevard\core\03_scd_type2_customer_history"
============================================================================= */

:setvar RepoPath C:\SQL_Boulevard\core\03_scd_type2_customer_history
:on error exit

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;     -- required for the filtered index on dim_customer
GO

:r $(RepoPath)\ddl\01_create_tables.sql
:r $(RepoPath)\procedures\02_usp_load_dim_customer.sql
:r $(RepoPath)\data\03_generate_monthly_snapshots.sql

PRINT '--- Loading four monthly batches';
USE CustomerHistory;
EXEC dbo.usp_load_dim_customer @batch_date = '2024-01-01';
EXEC dbo.usp_load_dim_customer @batch_date = '2024-02-01';
EXEC dbo.usp_load_dim_customer @batch_date = '2024-03-01';
EXEC dbo.usp_load_dim_customer @batch_date = '2024-04-01';
EXEC dbo.usp_resolve_order_keys;
GO

:r $(RepoPath)\tests\04_scd_tests.sql
:r $(RepoPath)\analysis\05_point_in_time_queries.sql
