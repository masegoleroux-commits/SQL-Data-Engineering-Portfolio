/* =============================================================================
   run_all.sql
   Builds the CustomerAnalytics database, runs every analysis, trains and
   tests the churn model, then runs the checks.

   1. Open in SSMS, switch on Query > SQLCMD Mode.
   2. Set RepoPath to this project's folder.
   3. Execute (F5).

   Command line:
     sqlcmd -S .\SQLEXPRESS -E -I -i run_all.sql -v RepoPath="C:\SQL_Boulevard\core\06_customer_analytics"
============================================================================= */

:setvar RepoPath C:\SQL_Boulevard\core\06_customer_analytics
:on error exit

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT '--- Data';
:r $(RepoPath)\data\01_create_shop_data.sql
PRINT '--- Analysis';
:r $(RepoPath)\analysis\02_rfm_segmentation.sql
:r $(RepoPath)\analysis\03_cohort_retention.sql
:r $(RepoPath)\analysis\04_purchase_behaviour.sql
:r $(RepoPath)\analysis\05_pareto_and_value.sql
:r $(RepoPath)\analysis\06_market_basket.sql
:r $(RepoPath)\analysis\07_executive_summary.sql
PRINT '--- Churn model';
:r $(RepoPath)\ml\08_churn_model.sql
PRINT '--- Tests';
:r $(RepoPath)\tests\09_test_analytics.sql
