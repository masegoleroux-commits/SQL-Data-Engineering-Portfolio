/* =============================================================================
   04_ml_feature_checks.sql
   Checks on ml.player_features before anyone trusts the similarity search.
   0 failed rows means PASS.
============================================================================= */

USE UCL;
GO

SET NOCOUNT ON;

DECLARE @min_minutes INT = (SELECT param_value FROM dbo.business_parameter WHERE param_name = 'min_minutes');

DROP TABLE IF EXISTS #ml_feature_results;
CREATE TABLE #ml_feature_results (test_name VARCHAR(100), failed_rows INT);

/* Row count: every eligible outfield player, nobody else */
INSERT INTO #ml_feature_results
SELECT 'features: row count <> eligible players',
       ABS((SELECT COUNT(*) FROM ml.player_features)
         - (SELECT COUNT(*)
            FROM dbo.dim_player AS p
            INNER JOIN dbo.fact_discipline   AS dc ON dc.player_key = p.player_key
            INNER JOIN dbo.fact_distribution AS ds ON ds.player_key = p.player_key
            INNER JOIN dbo.fact_defending    AS dd ON dd.player_key = p.player_key
            WHERE p.position <> N'Goalkeeper'
              AND dc.minutes_played >= @min_minutes));

/* One row per player */
INSERT INTO #ml_feature_results
SELECT 'features: duplicate player_key', COUNT(*)
FROM (SELECT player_key FROM ml.player_features GROUP BY player_key HAVING COUNT(*) > 1) AS d;

/* No goalkeepers and nobody under the minutes threshold */
INSERT INTO #ml_feature_results
SELECT 'features: goalkeeper or under min_minutes', COUNT(*)
FROM ml.player_features
WHERE position = N'Goalkeeper' OR minutes_played < @min_minutes;

/* A model input must not contain NULLs */
INSERT INTO #ml_feature_results
SELECT 'features: NULL in a z-score column', COUNT(*)
FROM ml.player_features
WHERE z_passes IS NULL OR z_pass_completion IS NULL OR z_crosses IS NULL
   OR z_recoveries IS NULL OR z_tackles IS NULL OR z_tackle_success IS NULL
   OR z_clearances IS NULL OR z_fouls IS NULL OR z_fouled IS NULL OR z_assists IS NULL;

/* Standardisation worked: mean ~0 and standard deviation ~1 within each position */
INSERT INTO #ml_feature_results
SELECT 'features: z_passes mean not 0 or stdev not 1 by position', COUNT(*)
FROM (
    SELECT position, AVG(1.0 * z_passes) AS mean_z, STDEV(z_passes) AS sd_z
    FROM ml.player_features
    GROUP BY position
) AS s
WHERE ABS(mean_z) > 0.01 OR ABS(sd_z - 1) > 0.01;

INSERT INTO #ml_feature_results
SELECT 'features: z_tackles mean not 0 or stdev not 1 by position', COUNT(*)
FROM (
    SELECT position, AVG(1.0 * z_tackles) AS mean_z, STDEV(z_tackles) AS sd_z
    FROM ml.player_features
    GROUP BY position
) AS s
WHERE ABS(mean_z) > 0.01 OR ABS(sd_z - 1) > 0.01;

/* Rates are physically possible */
INSERT INTO #ml_feature_results
SELECT 'features: completion % outside 0-100', COUNT(*)
FROM ml.player_features
WHERE pass_completion_pct NOT BETWEEN 0 AND 100
   OR tackle_success_pct  NOT BETWEEN 0 AND 100;

SELECT test_name,
       failed_rows,
       CASE WHEN failed_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM #ml_feature_results
ORDER BY result, test_name;
GO
