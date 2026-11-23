/* =============================================================================
   02_referential_integrity.sql
   Orphan checks. The foreign keys already block orphans on insert; these
   queries confirm it after every load and also catch the case the FKs cannot:
   staging rows that never made it into the model.
   0 failed rows means PASS.
============================================================================= */

USE UCL;
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS #ri_results;
CREATE TABLE #ri_results (test_name VARCHAR(100), failed_rows INT);

/* Facts -> dim_player */
INSERT INTO #ri_results
SELECT 'fact_attacking: orphan player_key', COUNT(*)
FROM dbo.fact_attacking AS f
LEFT JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE p.player_key IS NULL;

INSERT INTO #ri_results
SELECT 'fact_defending: orphan player_key', COUNT(*)
FROM dbo.fact_defending AS f
LEFT JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE p.player_key IS NULL;

INSERT INTO #ri_results
SELECT 'fact_distribution: orphan player_key', COUNT(*)
FROM dbo.fact_distribution AS f
LEFT JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE p.player_key IS NULL;

INSERT INTO #ri_results
SELECT 'fact_discipline: orphan player_key', COUNT(*)
FROM dbo.fact_discipline AS f
LEFT JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE p.player_key IS NULL;

/* Fact club_key must agree with the player's club in dim_player */
INSERT INTO #ri_results
SELECT 'facts: club_key disagrees with dim_player.club_name', COUNT(*)
FROM (
    SELECT player_key, club_key FROM dbo.fact_attacking
    UNION ALL SELECT player_key, club_key FROM dbo.fact_defending
    UNION ALL SELECT player_key, club_key FROM dbo.fact_distribution
    UNION ALL SELECT player_key, club_key FROM dbo.fact_discipline
) AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
INNER JOIN dbo.dim_club   AS c ON c.club_key   = f.club_key
WHERE p.club_name <> c.club_name;

/* Every club named in dim_player exists in dim_club */
INSERT INTO #ri_results
SELECT 'dim_player: club missing from dim_club', COUNT(*)
FROM dbo.dim_player AS p
LEFT JOIN dbo.dim_club AS c ON c.club_name = p.club_name
WHERE c.club_key IS NULL;

/* Every dim_player row is used by at least one fact */
INSERT INTO #ri_results
SELECT 'dim_player: row not referenced by any fact', COUNT(*)
FROM dbo.dim_player AS p
WHERE NOT EXISTS (SELECT 1 FROM dbo.fact_attacking    AS f WHERE f.player_key = p.player_key)
  AND NOT EXISTS (SELECT 1 FROM dbo.fact_defending    AS f WHERE f.player_key = p.player_key)
  AND NOT EXISTS (SELECT 1 FROM dbo.fact_distribution AS f WHERE f.player_key = p.player_key)
  AND NOT EXISTS (SELECT 1 FROM dbo.fact_discipline   AS f WHERE f.player_key = p.player_key);

/* Staging rows with no matching dimension member (would be silently
   dropped by the INNER JOINs in 03_load_facts.sql) */
INSERT INTO #ri_results
SELECT 'staging: rows with no dim_player match', COUNT(*)
FROM (
    SELECT player_name, club FROM dbo.stg_attacking
    UNION ALL SELECT player_name, club FROM dbo.stg_defending
    UNION ALL SELECT player_name, club FROM dbo.stg_distribution
    UNION ALL SELECT player_name, club FROM dbo.stg_disciplinary
) AS s
LEFT JOIN dbo.dim_player AS p
    ON  p.player_name = LTRIM(RTRIM(s.player_name))
    AND p.club_name   = LTRIM(RTRIM(s.club))
WHERE p.player_key IS NULL;

SELECT test_name,
       failed_rows,
       CASE WHEN failed_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM #ri_results
ORDER BY result, test_name;
GO
