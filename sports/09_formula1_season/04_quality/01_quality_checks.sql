/* =============================================================================
   01_quality_checks.sql
============================================================================= */

USE Formula1;
GO

DROP TABLE IF EXISTS ops.test_result;
CREATE TABLE ops.test_result (
    test_name  VARCHAR(120)  NOT NULL,
    expected   BIGINT        NULL,
    actual     BIGINT        NULL
);

INSERT INTO ops.test_result
SELECT 'every race and sprint row matched to a round and a team',
       (SELECT COUNT(*) FROM bronze.race_results) + (SELECT COUNT(*) FROM bronze.sprint_results),
       (SELECT COUNT(*) FROM silver.result);

INSERT INTO ops.test_result
SELECT 'every qualifying row matched', (SELECT COUNT(*) FROM bronze.qualifying_results), (SELECT COUNT(*) FROM silver.qualifying);

INSERT INTO ops.test_result
SELECT 'each results label matches exactly one round', 0, COUNT(*)
FROM (SELECT track_label FROM silver.race WHERE track_label IS NOT NULL GROUP BY track_label HAVING COUNT(*) > 1) AS x;

INSERT INTO ops.test_result
SELECT 'points engine reproduces the published points in every row', 0, COUNT(*)
FROM gold.fact_result WHERE engine_points <> published_points;

INSERT INTO ops.test_result
SELECT 'one winner per session', 0, COUNT(*)
FROM (SELECT session_type, round_no FROM gold.fact_result GROUP BY session_type, round_no
      HAVING SUM(CASE WHEN finish_position = 1 THEN 1 ELSE 0 END) <> 1) AS x;

INSERT INTO ops.test_result
SELECT 'no two drivers share a finishing position', 0, COUNT(*)
FROM (SELECT session_type, round_no, finish_position FROM gold.fact_result
      WHERE finish_position IS NOT NULL
      GROUP BY session_type, round_no, finish_position HAVING COUNT(*) > 1) AS x;

INSERT INTO ops.test_result
SELECT 'one fastest lap per Grand Prix', 0, COUNT(*)
FROM (SELECT round_no FROM gold.fact_result WHERE session_type = 'race'
      GROUP BY round_no HAVING SUM(fastest_lap) <> 1) AS x;

INSERT INTO ops.test_result
SELECT 'gaps grow with finishing position among drivers on the lead lap', 0, COUNT(*)
FROM (SELECT gap_seconds,
             LAG(gap_seconds) OVER (PARTITION BY session_type, round_no ORDER BY finish_position) AS prev_gap
      FROM gold.fact_result WHERE status = 'finished') AS x
WHERE x.gap_seconds < x.prev_gap;

INSERT INTO ops.test_result
SELECT 'a team never has more than two cars in one session', 0, COUNT(*)
FROM (SELECT session_type, round_no, team_key FROM gold.fact_result
      GROUP BY session_type, round_no, team_key HAVING COUNT(*) > 2) AS x;

SELECT test_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM ops.test_result;

IF EXISTS (SELECT 1 FROM ops.test_result WHERE actual IS NULL OR expected <> actual)
    THROW 50001, 'Quality checks failed. See the results grid.', 1;
GO
