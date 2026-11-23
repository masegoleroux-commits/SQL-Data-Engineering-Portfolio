/* =============================================================================
   01_quality_checks.sql
   Every check returns expected vs actual and PASS / FAIL. The last
   statement raises an error if anything failed, which stops run_all.sql.
============================================================================= */

USE NbaElo;
GO

DROP TABLE IF EXISTS ops.test_result;
CREATE TABLE ops.test_result (
    test_name  VARCHAR(120)  NOT NULL,
    expected   BIGINT        NULL,
    actual     BIGINT        NULL
);

DECLARE @tol DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'elo_tolerance');

/* ---- Reconciliation ---------------------------------------------------- */
INSERT INTO ops.test_result
SELECT 'bronze -> silver: every row kept or its game quarantined',
       (SELECT COUNT(*) FROM bronze.nba_elo_games),
       (SELECT COUNT(*) FROM silver.team_game)
     + (SELECT COUNT(*) FROM bronze.nba_elo_games WHERE game_id IN (SELECT record_key FROM ops.quarantine));

INSERT INTO ops.test_result
SELECT 'silver: two team rows for every game',
       (SELECT 2 * COUNT(*) FROM silver.game), (SELECT COUNT(*) FROM silver.team_game);

INSERT INTO ops.test_result
SELECT 'silver -> gold: every game in fact_game',
       (SELECT COUNT(*) FROM silver.game), (SELECT COUNT(*) FROM gold.fact_game);

INSERT INTO ops.test_result
SELECT 'silver -> gold: every team row in fact_team_game',
       (SELECT COUNT(*) FROM silver.team_game), (SELECT COUNT(*) FROM gold.fact_team_game);

/* ---- Business rules ---------------------------------------------------- */
INSERT INTO ops.test_result
SELECT 'exactly one winner per game', 0, COUNT(*)
FROM (SELECT game_key FROM gold.fact_team_game GROUP BY game_key HAVING SUM(is_win) <> 1) AS x;

INSERT INTO ops.test_result
SELECT 'winner scored more points', 0, COUNT(*)
FROM gold.fact_team_game
WHERE is_win = 1 AND pts <= opp_pts;

INSERT INTO ops.test_result
SELECT 'Elo is zero-sum: both sides of a game move by equal and opposite amounts', 0, COUNT(*)
FROM gold.fact_team_game AS a
INNER JOIN gold.fact_team_game AS b ON b.game_key = a.game_key AND b.team_key = a.opp_team_key
WHERE ABS((a.elo_after - a.elo_before) + (b.elo_after - b.elo_before)) > @tol;

INSERT INTO ops.test_result
SELECT 'the two forecasts for a game add up to 1', 0, COUNT(*)
FROM gold.fact_team_game AS a
INNER JOIN gold.fact_team_game AS b ON b.game_key = a.game_key AND b.team_key = a.opp_team_key
WHERE ABS(a.forecast + b.forecast - 1) > 0.0001;

-- within a season a team's rating carries straight from one game to the
-- next (between seasons it is pulled back toward the mean, so that is skipped)
INSERT INTO ops.test_result
SELECT 'Elo carries from game to game within a season', 0, COUNT(*)
FROM (
    SELECT season, elo_before,
           LAG(elo_after) OVER (PARTITION BY franchise_key ORDER BY team_game_no) AS prev_after,
           LAG(season)    OVER (PARTITION BY franchise_key ORDER BY team_game_no) AS prev_season
    FROM gold.fact_team_game
) AS x
WHERE x.prev_season = x.season AND ABS(x.elo_before - x.prev_after) > @tol;

/* ---- SCD Type 2 integrity ---------------------------------------------- */
INSERT INTO ops.test_result
SELECT 'dim_team: no overlapping spells within a franchise', 0, COUNT(*)
FROM gold.dim_team AS a
INNER JOIN gold.dim_team AS b
        ON b.franchise_key = a.franchise_key AND b.team_key <> a.team_key
       AND a.valid_from <= b.valid_to AND b.valid_from <= a.valid_to;

INSERT INTO ops.test_result
SELECT 'dim_team: exactly one current row per franchise',
       (SELECT COUNT(*) FROM gold.dim_franchise),
       (SELECT COUNT(*) FROM gold.dim_team WHERE is_current = 1);

INSERT INTO ops.test_result
SELECT 'dim_team: no season gap inside a franchise''s history', 0, COUNT(*)
FROM (
    SELECT valid_from,
           LAG(valid_to) OVER (PARTITION BY franchise_key ORDER BY valid_from) AS prev_to
    FROM gold.dim_team
) AS x
WHERE x.prev_to IS NOT NULL AND x.valid_from <> x.prev_to + 1;

/* ---- Results ----------------------------------------------------------- */
SELECT test_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM ops.test_result;

IF EXISTS (SELECT 1 FROM ops.test_result WHERE actual IS NULL OR expected <> actual)
    THROW 50001, 'Quality checks failed. See the results grid.', 1;
GO
