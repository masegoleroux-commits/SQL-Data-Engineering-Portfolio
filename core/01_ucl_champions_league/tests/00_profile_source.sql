/* =============================================================================
   00_profile_source.sql
   Profiles the staging tables before anything is built on them.
   These are the queries that found the problems described in
   docs/data_quality.md. Run after transformations/01_load_staging.sql.
============================================================================= */

USE UCL;
GO

SET NOCOUNT ON;

-- 1. Volume and completeness per file
SELECT 'attacking' AS source_file, COUNT(*) AS row_count,
       SUM(CASE WHEN player_name IS NULL OR club IS NULL OR position IS NULL THEN 1 ELSE 0 END) AS missing_keys,
       COUNT(DISTINCT club) AS clubs
FROM dbo.stg_attacking
UNION ALL
SELECT 'defending', COUNT(*),
       SUM(CASE WHEN player_name IS NULL OR club IS NULL OR position IS NULL THEN 1 ELSE 0 END),
       COUNT(DISTINCT club)
FROM dbo.stg_defending
UNION ALL
SELECT 'distribution', COUNT(*),
       SUM(CASE WHEN player_name IS NULL OR club IS NULL OR position IS NULL THEN 1 ELSE 0 END),
       COUNT(DISTINCT club)
FROM dbo.stg_distribution
UNION ALL
SELECT 'disciplinary', COUNT(*),
       SUM(CASE WHEN player_name IS NULL OR club IS NULL OR position IS NULL THEN 1 ELSE 0 END),
       COUNT(DISTINCT club)
FROM dbo.stg_disciplinary;

-- 2. Card columns: red cards should be far rarer than yellows.
--    If "red" is the bigger number, the labels are swapped.
SELECT SUM(red)    AS total_in_red_column,
       SUM(yellow) AS total_in_yellow_column,
       MAX(red)    AS max_red_one_player,
       MAX(yellow) AS max_yellow_one_player,
       CASE WHEN SUM(red) > SUM(yellow) THEN 'Columns look swapped' ELSE 'Looks normal' END AS verdict
FROM dbo.stg_disciplinary;

-- 3. Does the source pass_accuracy agree with its own counts?
WITH gaps AS (
    SELECT player_name, club, pass_attempted, pass_completed, pass_accuracy,
           CAST(100.0 * pass_completed / pass_attempted AS DECIMAL(5, 1))                AS recalculated,
           ABS(pass_accuracy - 100.0 * pass_completed / pass_attempted)                  AS gap
    FROM dbo.stg_distribution
    WHERE pass_attempted > 0
)
SELECT CASE WHEN gap <= 1 THEN '0-1 pts'
            WHEN gap <= 5 THEN '1-5 pts'
            WHEN gap <= 10 THEN '5-10 pts'
            ELSE '10+ pts' END AS gap_band,
       COUNT(*)                AS players,
       CAST(MAX(gap) AS DECIMAL(5, 1)) AS worst_gap
FROM gaps
GROUP BY CASE WHEN gap <= 1 THEN '0-1 pts'
              WHEN gap <= 5 THEN '1-5 pts'
              WHEN gap <= 10 THEN '5-10 pts'
              ELSE '10+ pts' END
ORDER BY MIN(gap);

-- 4. Is serial a unique key? (It is not: it is a rank with ties.)
SELECT serial, COUNT(*) AS rows_sharing_serial
FROM dbo.stg_defending
GROUP BY serial
HAVING COUNT(*) > 1
ORDER BY serial;

-- 5. Stray whitespace in names. DATALENGTH is used because SQL Server ignores
--    trailing spaces when comparing strings ('Inter ' = 'Inter' is true).
SELECT 'player_name' AS column_name, COUNT(*) AS rows_with_whitespace
FROM (SELECT player_name FROM dbo.stg_attacking UNION ALL SELECT player_name FROM dbo.stg_defending
      UNION ALL SELECT player_name FROM dbo.stg_distribution UNION ALL SELECT player_name FROM dbo.stg_disciplinary) AS s
WHERE DATALENGTH(player_name) <> DATALENGTH(LTRIM(RTRIM(player_name)))
UNION ALL
SELECT 'club', COUNT(*)
FROM (SELECT club FROM dbo.stg_attacking UNION ALL SELECT club FROM dbo.stg_defending
      UNION ALL SELECT club FROM dbo.stg_distribution UNION ALL SELECT club FROM dbo.stg_disciplinary) AS s
WHERE DATALENGTH(club) <> DATALENGTH(LTRIM(RTRIM(club)));
GO
