/* =============================================================================
   run_all.sql
   Generates 2 million orders, measures seven slow queries, tunes them,
   measures again and tests the results. Takes a few minutes.

   1. Open in SSMS, switch on Query > SQLCMD Mode.
   2. Set RepoPath to this project's folder.
   3. Execute (F5).

   Command line:
     sqlcmd -S .\SQLEXPRESS -E -I -i run_all.sql -v RepoPath="C:\SQL_Boulevard\core\05_query_performance_tuning"

   Needs VIEW SERVER STATE to read plans from the plan cache. A local
   administrator / sysadmin login has it.
============================================================================= */

:setvar RepoPath C:\SQL_Boulevard\core\05_query_performance_tuning
:on error exit

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;      -- needed for the filtered index
GO

PRINT '--- 1. Generate data';
:r $(RepoPath)\setup\01_generate_large_dataset.sql
PRINT '--- 2. Benchmark harness and scenarios';
:r $(RepoPath)\benchmark\02_create_benchmark_harness.sql
:r $(RepoPath)\benchmark\03_register_scenarios.sql
PRINT '--- 3. Baseline (untuned)';
:r $(RepoPath)\benchmark\04_run_baseline.sql
PRINT '--- 4. Indexes';
:r $(RepoPath)\tuning\05_create_indexes.sql
PRINT '--- 5. Partitioning';
:r $(RepoPath)\tuning\06_partition_orders.sql
PRINT '--- 6. Tuned';
:r $(RepoPath)\benchmark\07_run_tuned.sql
PRINT '--- 7. Report and tests';
:r $(RepoPath)\reports\08_results_report.sql
:r $(RepoPath)\tests\09_test_tuning_results.sql
