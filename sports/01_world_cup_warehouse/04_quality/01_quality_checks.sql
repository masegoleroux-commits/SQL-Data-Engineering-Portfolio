/* =============================================================================
   01_quality_checks.sql
   Every check returns expected vs actual and PASS / FAIL. The last
   statement raises an error if anything failed, which stops run_all.sql.
============================================================================= */

USE WorldCup;
GO

DROP TABLE IF EXISTS ops.test_result;
CREATE TABLE ops.test_result (
    test_name  VARCHAR(120)  NOT NULL,
    expected   BIGINT        NULL,
    actual     BIGINT        NULL
);

/* ---- Reconciliation across layers -------------------------------------- */
INSERT INTO ops.test_result
SELECT 'bronze -> silver: every match kept or quarantined',
       (SELECT COUNT(*) FROM bronze.matches),
       (SELECT COUNT(*) FROM silver.match) + (SELECT COUNT(*) FROM ops.quarantine WHERE source_table = 'matches');

INSERT INTO ops.test_result
SELECT 'silver -> gold: every match in fact_match',
       (SELECT COUNT(*) FROM silver.match), (SELECT COUNT(*) FROM gold.fact_match);

INSERT INTO ops.test_result
SELECT 'bronze -> silver: every goal kept or quarantined',
       (SELECT COUNT(*) FROM bronze.goals),
       (SELECT COUNT(*) FROM silver.goal) + (SELECT COUNT(*) FROM ops.quarantine WHERE source_table = 'goals');

INSERT INTO ops.test_result
SELECT 'silver -> gold: every goal in fact_goal',
       (SELECT COUNT(*) FROM silver.goal), (SELECT COUNT(*) FROM gold.fact_goal);

INSERT INTO ops.test_result
SELECT 'silver -> gold: every card in fact_booking',
       (SELECT COUNT(*) FROM silver.booking), (SELECT COUNT(*) FROM gold.fact_booking);

INSERT INTO ops.test_result
SELECT 'fact_team_match has exactly two rows per match',
       (SELECT 2 * COUNT(*) FROM gold.fact_match), (SELECT COUNT(*) FROM gold.fact_team_match);

/* ---- Business rules ---------------------------------------------------- */
-- goals scored in fact_goal must add up to the final score of every match
INSERT INTO ops.test_result
SELECT 'goal records add up to every match score', 0, COUNT(*)
FROM gold.fact_match AS f
LEFT JOIN (SELECT match_key, COUNT(*) AS goals FROM gold.fact_goal GROUP BY match_key) AS g
    ON g.match_key = f.match_key
WHERE COALESCE(g.goals, 0) <> f.home_score + f.away_score;

INSERT INTO ops.test_result
SELECT 'goals credited to a team match that team''s goals_for', 0, COUNT(*)
FROM gold.fact_team_match AS tm
LEFT JOIN (SELECT match_key, team_key, COUNT(*) AS goals FROM gold.fact_goal GROUP BY match_key, team_key) AS g
    ON g.match_key = tm.match_key AND g.team_key = tm.team_key
WHERE COALESCE(g.goals, 0) <> tm.goals_for;

INSERT INTO ops.test_result
SELECT 'every shootout match was level on the score', 0, COUNT(*)
FROM gold.fact_match
WHERE penalty_shootout = 1 AND home_score <> away_score;

-- In 1934 and 1938 a drawn knockout match was replayed instead of going to
-- penalties, so those draws are allowed when the match is flagged as replayed.
INSERT INTO ops.test_result
SELECT 'every knockout match (not replayed) has someone going through', 0, COUNT(*)
FROM gold.fact_match AS f
INNER JOIN gold.dim_stage AS s ON s.stage_key = f.stage_key
INNER JOIN silver.match AS m ON m.match_id = f.match_id
WHERE s.is_knockout = 1 AND f.final_result = 'D' AND m.is_replayed = 0;

INSERT INTO ops.test_result
SELECT 'each tournament winner won its last match', 0, COUNT(*)
FROM gold.dim_tournament AS t
WHERE NOT EXISTS (
    SELECT 1
    FROM gold.fact_team_match AS tm
    INNER JOIN gold.dim_team AS tt ON tt.team_key = tm.team_key
    INNER JOIN gold.fact_match AS f ON f.match_key = tm.match_key
    WHERE tm.tournament_key = t.tournament_key
      AND tt.team_name = t.winner
      AND f.match_date = (SELECT MAX(f2.match_date) FROM gold.fact_match AS f2 WHERE f2.tournament_key = t.tournament_key)
);

INSERT INTO ops.test_result
SELECT 'no stage names left outside dim_stage', 0, COUNT(*)
FROM silver.match AS m
WHERE NOT EXISTS (SELECT 1 FROM gold.dim_stage AS s WHERE s.stage_name = m.stage_name);

INSERT INTO ops.test_result
SELECT 'no birth dates in the future or before 1880', 0, COUNT(*)
FROM gold.dim_player
WHERE birth_date > CAST(SYSDATETIME() AS DATE) OR birth_date < '1880-01-01';

/* ---- Results ----------------------------------------------------------- */
SELECT test_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM ops.test_result;

IF EXISTS (SELECT 1 FROM ops.test_result WHERE actual IS NULL OR expected <> actual)
    THROW 50001, 'Quality checks failed. See the results grid.', 1;
GO
