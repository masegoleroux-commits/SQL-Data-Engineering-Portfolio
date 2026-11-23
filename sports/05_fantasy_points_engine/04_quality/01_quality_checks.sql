/* =============================================================================
   01_quality_checks.sql
   The key check: the engine, driven only by the rules table, must
   reproduce the published points for every player in every fixture.
============================================================================= */

USE FantasyPoints;
GO

DROP TABLE IF EXISTS ops.test_result;
CREATE TABLE ops.test_result (
    test_name  VARCHAR(120)  NOT NULL,
    expected   BIGINT        NULL,
    actual     BIGINT        NULL
);

INSERT INTO ops.test_result
SELECT 'bronze -> silver: every row kept',
       (SELECT COUNT(*) FROM bronze.fpl_player_gameweeks), (SELECT COUNT(*) FROM silver.player_fixture);

INSERT INTO ops.test_result
SELECT 'silver -> gold: every player fixture', (SELECT COUNT(*) FROM silver.player_fixture), (SELECT COUNT(*) FROM gold.fact_player_fixture);

INSERT INTO ops.test_result
SELECT 'engine reproduces published points in every row', 0, COUNT(*)
FROM gold.fact_player_fixture WHERE engine_points <> official_points;

INSERT INTO ops.test_result
SELECT 'engine season total = published season total',
       (SELECT SUM(official_points) FROM gold.fact_player_fixture),
       (SELECT SUM(engine_points)   FROM gold.fact_player_fixture);

INSERT INTO ops.test_result
SELECT 'every event in the data has a rule in each rule set', 0, COUNT(*)
FROM (SELECT DISTINCT e.event, r.rule_set
      FROM silver.player_fixture_event AS e
      CROSS JOIN (SELECT DISTINCT rule_set FROM ops.scoring_rule) AS r
      WHERE NOT EXISTS (SELECT 1 FROM ops.scoring_rule AS s
                        WHERE s.rule_set = r.rule_set AND s.event = e.event)) AS x;

INSERT INTO ops.test_result
SELECT 'clean sheets only for players with 60+ minutes in a fixture with no goals conceded', 0, COUNT(*)
FROM silver.player_fixture
WHERE clean_sheets = 1 AND (minutes < 60 OR goals_conceded > 0);

INSERT INTO ops.test_result
SELECT 'no player in two fixtures at the same kick-off time', 0, COUNT(*)
FROM (SELECT player_id, kickoff_utc FROM silver.player_fixture
      GROUP BY player_id, kickoff_utc HAVING COUNT(*) > 1) AS x;

SELECT test_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM ops.test_result;

IF EXISTS (SELECT 1 FROM ops.test_result WHERE actual IS NULL OR expected <> actual)
    THROW 50001, 'Quality checks failed. See the results grid.', 1;
GO
