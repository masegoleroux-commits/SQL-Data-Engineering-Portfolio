/* =============================================================================
   01_quality_checks.sql
   Every check returns expected vs actual and PASS / FAIL. The last
   statement raises an error if anything failed, which stops run_all.sql.
============================================================================= */

USE FootballLeagues;
GO

DROP TABLE IF EXISTS ops.test_result;
CREATE TABLE ops.test_result (
    test_name  VARCHAR(120)  NOT NULL,
    expected   BIGINT        NULL,
    actual     BIGINT        NULL
);

/* ---- Reconciliation ---------------------------------------------------- */
INSERT INTO ops.test_result
SELECT 'bronze -> silver: one source_file row per landed document',
       (SELECT COUNT(*) FROM bronze.api_landing), (SELECT COUNT(*) FROM silver.source_file);

INSERT INTO ops.test_result
SELECT 'JSON: matches shredded = matches counted inside each document',
       (SELECT SUM(matches_in_file) FROM silver.source_file), (SELECT COUNT(*) FROM silver.match_raw);

INSERT INTO ops.test_result
SELECT 'silver: no match lost while resolving team names',
       (SELECT COUNT(*) FROM silver.match_raw), (SELECT COUNT(*) FROM silver.match);

INSERT INTO ops.test_result
SELECT 'silver -> gold: every match in fact_match',
       (SELECT COUNT(*) FROM silver.match), (SELECT COUNT(*) FROM gold.fact_match);

INSERT INTO ops.test_result
SELECT 'gold: two team rows for every match that counts',
       (SELECT 2 * COUNT(*) FROM gold.fact_match WHERE counts_in_table = 1),
       (SELECT COUNT(*) FROM gold.fact_team_match);

/* ---- Entity resolution -------------------------------------------------- */
-- A double round robin means every ordered pair (home, away) meets exactly
-- once per season. If a club were still split across two names, its pairs
-- would show up as missing or doubled.
INSERT INTO ops.test_result
SELECT 'every home/away pairing happens exactly once per season', 0, COUNT(*)
FROM (SELECT league_key, season_key, home_team_key, away_team_key
      FROM gold.fact_match
      GROUP BY league_key, season_key, home_team_key, away_team_key
      HAVING COUNT(*) <> 1) AS x;

INSERT INTO ops.test_result
SELECT 'matches per season = teams x (teams - 1)', 0, COUNT(*)
FROM (SELECT league_key, season_key,
             COUNT(*) AS matches,
             COUNT(DISTINCT home_team_key) AS teams
      FROM gold.fact_match
      GROUP BY league_key, season_key) AS x
WHERE x.matches <> x.teams * (x.teams - 1);

INSERT INTO ops.test_result
SELECT 'alias table: every canonical name maps to itself', 0, COUNT(*)
FROM silver.team_alias AS a
WHERE NOT EXISTS (SELECT 1 FROM silver.team_alias AS c
                  WHERE c.league_code = a.league_code
                    AND c.source_name = a.canonical_name
                    AND c.canonical_name = a.canonical_name);

INSERT INTO ops.test_result
SELECT 'no accepted name pair shares a season', 0, COUNT(*)
FROM silver.team_name_candidate
WHERE decision = 'accepted' AND share_a_season = 1;

/* ---- Business rules ----------------------------------------------------- */
INSERT INTO ops.test_result
SELECT 'played matches have a full-time score', 0, COUNT(*)
FROM gold.fact_match
WHERE counts_in_table = 1 AND (ft_home IS NULL OR ft_away IS NULL);

INSERT INTO ops.test_result
SELECT 'half-time goals never exceed full-time goals', 0, COUNT(*)
FROM gold.fact_match
WHERE ht_home > ft_home OR ht_away > ft_away;

DECLARE @win  DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'points_win');
DECLARE @draw DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'points_draw');

INSERT INTO ops.test_result
SELECT 'points in each table = win points per decisive match + 2 x draw points per draw', 0, COUNT(*)
FROM (SELECT f.league_key, f.season_key,
             SUM(CASE WHEN f.result = 'D' THEN 2 * @draw ELSE @win END) AS expected_points,
             (SELECT SUM(points) FROM gold.v_league_table AS v
              WHERE v.league_key = f.league_key AND v.season_key = f.season_key) AS table_points
      FROM gold.fact_match AS f
      WHERE f.counts_in_table = 1
      GROUP BY f.league_key, f.season_key) AS x
WHERE x.expected_points <> x.table_points;

/* ---- Results ----------------------------------------------------------- */
SELECT test_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM ops.test_result;

IF EXISTS (SELECT 1 FROM ops.test_result WHERE actual IS NULL OR expected <> actual)
    THROW 50001, 'Quality checks failed. See the results grid.', 1;
GO
