/* =============================================================================
   01_grain_checks.sql
   Every table has a declared grain (docs/grain.md). These checks prove it.
   Each check counts violating rows; 0 means PASS.
============================================================================= */

USE UCL;
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS #grain_results;
CREATE TABLE #grain_results (test_name VARCHAR(100), failed_rows INT);

/* Staging: one row per player + club in each source file */
INSERT INTO #grain_results
SELECT 'stg_attacking: duplicate player+club', COUNT(*)
FROM (SELECT player_name, club FROM dbo.stg_attacking GROUP BY player_name, club HAVING COUNT(*) > 1) AS d;

INSERT INTO #grain_results
SELECT 'stg_defending: duplicate player+club', COUNT(*)
FROM (SELECT player_name, club FROM dbo.stg_defending GROUP BY player_name, club HAVING COUNT(*) > 1) AS d;

INSERT INTO #grain_results
SELECT 'stg_distribution: duplicate player+club', COUNT(*)
FROM (SELECT player_name, club FROM dbo.stg_distribution GROUP BY player_name, club HAVING COUNT(*) > 1) AS d;

INSERT INTO #grain_results
SELECT 'stg_disciplinary: duplicate player+club', COUNT(*)
FROM (SELECT player_name, club FROM dbo.stg_disciplinary GROUP BY player_name, club HAVING COUNT(*) > 1) AS d;

/* Staging: required columns populated */
INSERT INTO #grain_results
SELECT 'staging: missing player, club or position', COUNT(*)
FROM (
    SELECT player_name, club, position FROM dbo.stg_attacking
    UNION ALL SELECT player_name, club, position FROM dbo.stg_defending
    UNION ALL SELECT player_name, club, position FROM dbo.stg_distribution
    UNION ALL SELECT player_name, club, position FROM dbo.stg_disciplinary
) AS s
WHERE s.player_name IS NULL OR s.club IS NULL OR s.position IS NULL;

/* Conformance: the same player+club must carry the same position and
   matches played in every file, otherwise the dimension is ambiguous */
INSERT INTO #grain_results
SELECT 'staging: position differs across files', COUNT(*)
FROM (
    SELECT player_name, club
    FROM (
        SELECT player_name, club, position FROM dbo.stg_attacking
        UNION SELECT player_name, club, position FROM dbo.stg_defending
        UNION SELECT player_name, club, position FROM dbo.stg_distribution
        UNION SELECT player_name, club, position FROM dbo.stg_disciplinary
    ) AS u
    GROUP BY player_name, club
    HAVING COUNT(DISTINCT position) > 1
) AS d;

INSERT INTO #grain_results
SELECT 'staging: matches played differs across files', COUNT(*)
FROM (
    SELECT player_name, club
    FROM (
        SELECT player_name, club, match_played FROM dbo.stg_attacking
        UNION SELECT player_name, club, match_played FROM dbo.stg_defending
        UNION SELECT player_name, club, match_played FROM dbo.stg_distribution
        UNION SELECT player_name, club, match_played FROM dbo.stg_disciplinary
    ) AS u
    GROUP BY player_name, club
    HAVING COUNT(DISTINCT match_played) > 1
) AS d;

/* Dimensions */
INSERT INTO #grain_results
SELECT 'dim_club: duplicate club_name', COUNT(*)
FROM (SELECT club_name FROM dbo.dim_club GROUP BY club_name HAVING COUNT(*) > 1) AS d;

INSERT INTO #grain_results
SELECT 'dim_player: duplicate player+club', COUNT(*)
FROM (SELECT player_name, club_name FROM dbo.dim_player GROUP BY player_name, club_name HAVING COUNT(*) > 1) AS d;

/* Facts: one row per player_key */
INSERT INTO #grain_results
SELECT 'fact_attacking: duplicate player_key', COUNT(*)
FROM (SELECT player_key FROM dbo.fact_attacking GROUP BY player_key HAVING COUNT(*) > 1) AS d;

INSERT INTO #grain_results
SELECT 'fact_defending: duplicate player_key', COUNT(*)
FROM (SELECT player_key FROM dbo.fact_defending GROUP BY player_key HAVING COUNT(*) > 1) AS d;

INSERT INTO #grain_results
SELECT 'fact_distribution: duplicate player_key', COUNT(*)
FROM (SELECT player_key FROM dbo.fact_distribution GROUP BY player_key HAVING COUNT(*) > 1) AS d;

INSERT INTO #grain_results
SELECT 'fact_discipline: duplicate player_key', COUNT(*)
FROM (SELECT player_key FROM dbo.fact_discipline GROUP BY player_key HAVING COUNT(*) > 1) AS d;

/* Views must not multiply rows */
INSERT INTO #grain_results
SELECT 'vw_player_season: row count <> dim_player', ABS((SELECT COUNT(*) FROM dbo.vw_player_season) - (SELECT COUNT(*) FROM dbo.dim_player));

INSERT INTO #grain_results
SELECT 'vw_club_season: row count <> dim_club', ABS((SELECT COUNT(*) FROM dbo.vw_club_season) - (SELECT COUNT(*) FROM dbo.dim_club));

SELECT test_name,
       failed_rows,
       CASE WHEN failed_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM #grain_results
ORDER BY result, test_name;
GO
