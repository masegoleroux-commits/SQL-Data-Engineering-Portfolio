/* =============================================================================
   03_reconciliation.sql
   Source-to-target reconciliation: row counts and control totals must match
   between each staging table and its fact table. A difference means the load
   dropped, duplicated or altered rows.

   Also runs the business-rule checks on the source and reports the known
   pass-accuracy issue as a WARN rather than a FAIL, since it is a property of
   the source data and is handled in the model (docs/data_quality.md).
============================================================================= */

USE UCL;
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS #recon_results;
CREATE TABLE #recon_results (test_name VARCHAR(100), source_value BIGINT, target_value BIGINT, is_warning BIT DEFAULT 0);

/* ---- Row counts ---------------------------------------------------------- */
INSERT INTO #recon_results (test_name, source_value, target_value)
SELECT 'attacking: row count',    (SELECT COUNT(*) FROM dbo.stg_attacking),    (SELECT COUNT(*) FROM dbo.fact_attacking)
UNION ALL
SELECT 'defending: row count',    (SELECT COUNT(*) FROM dbo.stg_defending),    (SELECT COUNT(*) FROM dbo.fact_defending)
UNION ALL
SELECT 'distribution: row count', (SELECT COUNT(*) FROM dbo.stg_distribution), (SELECT COUNT(*) FROM dbo.fact_distribution)
UNION ALL
SELECT 'discipline: row count',   (SELECT COUNT(*) FROM dbo.stg_disciplinary), (SELECT COUNT(*) FROM dbo.fact_discipline);

/* ---- Control totals ------------------------------------------------------ */
INSERT INTO #recon_results (test_name, source_value, target_value)
SELECT 'attacking: total assists',          (SELECT SUM(assists)             FROM dbo.stg_attacking),    (SELECT SUM(assists)              FROM dbo.fact_attacking)
UNION ALL
SELECT 'attacking: total dribbles',         (SELECT SUM(dribbles)            FROM dbo.stg_attacking),    (SELECT SUM(dribbles)             FROM dbo.fact_attacking)
UNION ALL
SELECT 'defending: total balls recovered',  (SELECT SUM(balls_recoverd)      FROM dbo.stg_defending),    (SELECT SUM(balls_recovered)      FROM dbo.fact_defending)
UNION ALL
SELECT 'defending: total tackles',          (SELECT SUM(tackles)             FROM dbo.stg_defending),    (SELECT SUM(tackles)              FROM dbo.fact_defending)
UNION ALL
SELECT 'distribution: total passes',        (SELECT SUM(pass_attempted)      FROM dbo.stg_distribution), (SELECT SUM(passes_attempted)     FROM dbo.fact_distribution)
UNION ALL
SELECT 'distribution: total crosses',       (SELECT SUM(cross_attempted)     FROM dbo.stg_distribution), (SELECT SUM(crosses_attempted)    FROM dbo.fact_distribution)
UNION ALL
SELECT 'discipline: total fouls committed', (SELECT SUM(fouls_committed)     FROM dbo.stg_disciplinary), (SELECT SUM(fouls_committed)      FROM dbo.fact_discipline)
UNION ALL
SELECT 'discipline: total minutes',         (SELECT SUM(minutes_played)      FROM dbo.stg_disciplinary), (SELECT SUM(minutes_played)       FROM dbo.fact_discipline)
UNION ALL
-- cards are swapped on load, so each target column reconciles to the opposite source column
SELECT 'discipline: yellow cards (src red)', (SELECT SUM(red)                FROM dbo.stg_disciplinary), (SELECT SUM(yellow_cards)         FROM dbo.fact_discipline)
UNION ALL
SELECT 'discipline: red cards (src yellow)', (SELECT SUM(yellow)             FROM dbo.stg_disciplinary), (SELECT SUM(red_cards)            FROM dbo.fact_discipline);

/* ---- Business rules on the source --------------------------------------- */
INSERT INTO #recon_results (test_name, source_value, target_value)
SELECT 'defending: tackles <> won + lost',
       (SELECT COUNT(*) FROM dbo.stg_defending WHERE tackles <> t_won + t_lost), 0
UNION ALL
SELECT 'distribution: completed > attempted',
       (SELECT COUNT(*) FROM dbo.stg_distribution WHERE pass_completed > pass_attempted OR cross_complted > cross_attempted), 0
UNION ALL
SELECT 'distribution: cross_accuracy off by > 1 pt',
       (SELECT COUNT(*) FROM dbo.stg_distribution
        WHERE cross_attempted > 0
          AND ABS(cross_accuracy - 100.0 * cross_complted / cross_attempted) > 1), 0;

/* Known source issue: reported, not failed */
INSERT INTO #recon_results (test_name, source_value, target_value, is_warning)
SELECT 'distribution: pass_accuracy off by > 5 pts',
       (SELECT COUNT(*) FROM dbo.stg_distribution
        WHERE pass_attempted > 0
          AND ABS(pass_accuracy - 100.0 * pass_completed / pass_attempted) > 5), 0, 1;

SELECT test_name,
       source_value,
       target_value,
       CASE WHEN source_value = target_value THEN 'PASS'
            WHEN is_warning = 1              THEN 'WARN'
            ELSE 'FAIL' END AS result
FROM #recon_results
ORDER BY result, test_name;
GO
