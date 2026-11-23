/* =============================================================================
   run_all.sql
   Builds the DataQuality database, checks the raw data, fixes and
   quarantines, checks again, then tests the framework itself.

   1. Open in SSMS, switch on Query > SQLCMD Mode.
   2. Set RepoPath to this project's folder.
   3. Execute (F5).

   Command line:
     sqlcmd -S .\SQLEXPRESS -E -I -i run_all.sql -v RepoPath="C:\SQL_Boulevard\core\04_data_quality_framework"
============================================================================= */

:setvar RepoPath C:\SQL_Boulevard\core\04_data_quality_framework
:on error exit

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT '--- 1. Raw data';
:r $(RepoPath)\raw_data\01_create_raw_sales.sql
PRINT '--- 2. Framework and rules';
:r $(RepoPath)\framework\02_create_dq_framework.sql
:r $(RepoPath)\framework\03_create_rule_templates.sql
:r $(RepoPath)\rules\04_register_rules.sql

PRINT '--- 3. Run 1: check the raw data';
USE DataQuality;
EXEC dq.usp_run_checks @run_label = N'Initial load';
SELECT ru.rule_code, r.status, r.failed_rows, r.failed_pct
FROM dq.result AS r
INNER JOIN dq.rule AS ru ON ru.rule_id = r.rule_id
WHERE r.run_id = (SELECT MAX(run_id) FROM dq.run) AND r.status <> 'PASS'
ORDER BY r.status, ru.rule_code;
GO

PRINT '--- 4. Fix, null out, quarantine';
:r $(RepoPath)\remediation\05_quarantine_and_fix.sql

PRINT '--- 5. Run 2: check again';
USE DataQuality;
EXEC dq.usp_run_checks @run_label = N'After remediation';
GO

PRINT '--- 6. Test the framework';
:r $(RepoPath)\tests\06_test_framework.sql
:r $(RepoPath)\reports\07_dq_scorecard.sql
