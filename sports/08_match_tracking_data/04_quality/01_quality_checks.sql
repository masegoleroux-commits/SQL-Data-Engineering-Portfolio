/* =============================================================================
   01_quality_checks.sql
============================================================================= */

USE MatchTracking;
GO

DROP TABLE IF EXISTS ops.test_result;
CREATE TABLE ops.test_result (
    test_name  VARCHAR(120)  NOT NULL,
    expected   BIGINT        NULL,
    actual     BIGINT        NULL
);

INSERT INTO ops.test_result
SELECT 'home and away files cover the same samples',
       (SELECT COUNT(*) FROM bronze.tracking_home), (SELECT COUNT(*) FROM bronze.tracking_away);

INSERT INTO ops.test_result
SELECT 'home and away files agree on frame numbers', 0, COUNT(*)
FROM bronze.tracking_home AS h
WHERE NOT EXISTS (SELECT 1 FROM bronze.tracking_away AS a WHERE a.frame = h.frame);

-- the ball appears in both files and must be in the same place
INSERT INTO ops.test_result
SELECT 'home and away files agree on the ball position', 0, COUNT(*)
FROM bronze.tracking_home AS h
INNER JOIN bronze.tracking_away AS a ON a.frame = h.frame
WHERE h.ball_x <> a.ball_x OR h.ball_y <> a.ball_y;

INSERT INTO ops.test_result
SELECT '14 player slots read for each team', 28, COUNT(*) FROM silver.player_slot;

INSERT INTO ops.test_result
SELECT 'never more than 11 players of one team on the pitch', 0, COUNT(*)
FROM (SELECT ps.team, p.frame
      FROM silver.player_position AS p
      INNER JOIN silver.player_slot AS ps ON ps.player_code = p.player_code
      GROUP BY ps.team, p.frame
      HAVING COUNT(*) > 11) AS x;

INSERT INTO ops.test_result
SELECT 'every player named in an event is in the tracking data', 0, COUNT(*)
FROM silver.match_event AS e
WHERE (e.from_player IS NOT NULL AND e.from_player NOT IN (SELECT player_code FROM silver.player_slot))
   OR (e.to_player   IS NOT NULL AND e.to_player   NOT IN (SELECT player_code FROM silver.player_slot));

INSERT INTO ops.test_result
SELECT 'every event sample frame exists in the tracking data', 0, COUNT(*)
FROM silver.match_event AS e
WHERE NOT EXISTS (SELECT 1 FROM silver.ball_frame AS b WHERE b.frame = e.sample_frame);

INSERT INTO ops.test_result
SELECT 'sprints never overlap for one player', 0, COUNT(*)
FROM gold.fact_sprint AS a
INNER JOIN gold.fact_sprint AS b
        ON b.player_code = a.player_code AND b.start_frame > a.start_frame AND b.start_frame <= a.end_frame;

SELECT test_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM ops.test_result;

IF EXISTS (SELECT 1 FROM ops.test_result WHERE actual IS NULL OR expected <> actual)
    THROW 50001, 'Quality checks failed. See the results grid.', 1;
GO
