/* =============================================================================
   01_quality_checks.sql
============================================================================= */

USE NbaPlayerImpact;
GO

DROP TABLE IF EXISTS ops.test_result;
CREATE TABLE ops.test_result (
    test_name  VARCHAR(120)  NOT NULL,
    expected   BIGINT        NULL,
    actual     BIGINT        NULL
);

DECLARE @tol DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'sum_tolerance');

INSERT INTO ops.test_result
SELECT 'bronze -> silver: every row kept or quarantined',
       (SELECT COUNT(*) FROM bronze.raptor_player_seasons),
       (SELECT COUNT(*) FROM silver.player_season) + (SELECT COUNT(*) FROM ops.quarantine);

INSERT INTO ops.test_result
SELECT 'silver -> gold: every player season has a name key', (SELECT COUNT(*) FROM silver.player_season), (SELECT COUNT(*) FROM gold.fact_player_season);

INSERT INTO ops.test_result
SELECT 'long format: 8 metric rows per qualified player season',
       (SELECT 8 * COUNT(*) FROM silver.player_season WHERE is_small_sample = 0),
       (SELECT COUNT(*) FROM gold.fact_player_metric);

INSERT INTO ops.test_result
SELECT 'RAPTOR offense + defense = total', 0, COUNT(*)
FROM silver.player_season WHERE ABS(raptor_offense + raptor_defense - raptor_total) > @tol;

INSERT INTO ops.test_result
SELECT 'box offense + defense = box total', 0, COUNT(*)
FROM silver.player_season WHERE ABS(box_offense + box_defense - box_total) > @tol;

INSERT INTO ops.test_result
SELECT 'WAR regular season + playoffs = WAR total', 0, COUNT(*)
FROM silver.player_season WHERE ABS(war_reg_season + war_playoffs - war_total) > @tol;

INSERT INTO ops.test_result
SELECT 'dim_player: one current row per player',
       (SELECT COUNT(DISTINCT player_id) FROM silver.player_season),
       (SELECT COUNT(*) FROM gold.dim_player WHERE is_current = 1);

INSERT INTO ops.test_result
SELECT 'dim_player: no overlapping name spells', 0, COUNT(*)
FROM gold.dim_player AS a
INNER JOIN gold.dim_player AS b
        ON b.player_id = a.player_id AND b.player_name_key <> a.player_name_key
       AND a.valid_from <= b.valid_to AND b.valid_from <= a.valid_to;

INSERT INTO ops.test_result
SELECT 'z-scores average zero in every season and metric', 0, COUNT(*)
FROM (SELECT season, metric FROM gold.fact_player_metric
      GROUP BY season, metric HAVING ABS(AVG(z_score)) > 0.01) AS x;

SELECT test_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM ops.test_result;

IF EXISTS (SELECT 1 FROM ops.test_result WHERE actual IS NULL OR expected <> actual)
    THROW 50001, 'Quality checks failed. See the results grid.', 1;
GO
