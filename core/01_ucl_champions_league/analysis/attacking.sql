/* =============================================================================
   attacking.sql
   Attacking output, UCL 2021/22. Source table: fact_attacking.
   Note: the source file only lists players with at least one assist.
============================================================================= */

USE UCL;
GO

-- Thresholds come from dbo.business_parameter (ddl/07_business_parameters.sql).
DECLARE @min_matches INT = (SELECT param_value FROM dbo.business_parameter WHERE param_name = 'min_matches');

-- 1. Top 10 assist providers
SELECT TOP (10)
    p.player_name, p.club_name, f.assists, f.matches_played
FROM dbo.fact_attacking AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
ORDER BY f.assists DESC, f.matches_played ASC;


-- 2. Assists per match (minimum @min_matches so one-game cameos do not top the list)
SELECT TOP (10)
    p.player_name, p.club_name, f.assists, f.matches_played,
    CAST(1.0 * f.assists / f.matches_played AS DECIMAL(4, 2)) AS assists_per_match
FROM dbo.fact_attacking AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE f.matches_played >= @min_matches
ORDER BY assists_per_match DESC;


-- 3. Leading dribbler at each club
WITH ranked AS (
    SELECT p.club_name, p.player_name, f.dribbles,
           ROW_NUMBER() OVER (PARTITION BY f.club_key ORDER BY f.dribbles DESC, p.player_name) AS rn
    FROM dbo.fact_attacking AS f
    INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
)
SELECT club_name, player_name, dribbles
FROM ranked
WHERE rn = 1
ORDER BY dribbles DESC;


-- 4. Most caught offside
SELECT TOP (10)
    p.player_name, p.club_name, p.position, f.offsides
FROM dbo.fact_attacking AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
ORDER BY f.offsides DESC;


-- 5. Average assists and dribbles by position
SELECT
    p.position,
    COUNT(*)                                       AS players,
    CAST(AVG(1.0 * f.assists)  AS DECIMAL(4, 2))   AS avg_assists,
    CAST(AVG(1.0 * f.dribbles) AS DECIMAL(5, 2))   AS avg_dribbles
FROM dbo.fact_attacking AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
GROUP BY p.position
ORDER BY avg_assists DESC;


-- 6. Clubs by total assists
SELECT c.club_name, SUM(f.assists) AS total_assists, COUNT(*) AS players_with_assists
FROM dbo.fact_attacking AS f
INNER JOIN dbo.dim_club AS c ON c.club_key = f.club_key
GROUP BY c.club_name
ORDER BY total_assists DESC;


-- 7. Each player's share of all assists in the competition
SELECT TOP (15)
    p.player_name, p.club_name, f.assists,
    CAST(100.0 * f.assists / SUM(f.assists) OVER () AS DECIMAL(5, 2)) AS pct_of_all_assists
FROM dbo.fact_attacking AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
ORDER BY pct_of_all_assists DESC;


-- 8. Each player's share of their own club's assists
SELECT
    p.club_name, p.player_name, f.assists,
    CAST(100.0 * f.assists / SUM(f.assists) OVER (PARTITION BY f.club_key) AS DECIMAL(5, 1)) AS pct_of_club_assists
FROM dbo.fact_attacking AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
ORDER BY p.club_name, pct_of_club_assists DESC;


-- 9. Top 3 creators per club by assists per match
WITH per_match AS (
    SELECT p.club_name, p.player_name, f.assists, f.matches_played,
           CAST(1.0 * f.assists / f.matches_played AS DECIMAL(4, 2)) AS assists_per_match
    FROM dbo.fact_attacking AS f
    INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
),
ranked AS (
    SELECT *, DENSE_RANK() OVER (PARTITION BY club_name ORDER BY assists_per_match DESC) AS club_rank
    FROM per_match
)
SELECT club_name, club_rank, player_name, assists, matches_played, assists_per_match
FROM ranked
WHERE club_rank <= 3
ORDER BY club_name, club_rank;


-- 10. How assists are distributed across players
SELECT
    CASE WHEN f.assists = 1 THEN '1'
         WHEN f.assists = 2 THEN '2'
         WHEN f.assists = 3 THEN '3'
         ELSE '4+' END                AS assists_band,
    COUNT(*)                          AS players
FROM dbo.fact_attacking AS f
GROUP BY CASE WHEN f.assists = 1 THEN '1'
              WHEN f.assists = 2 THEN '2'
              WHEN f.assists = 3 THEN '3'
              ELSE '4+' END
ORDER BY assists_band;


-- 11. Set-piece takers: corners taken by position
SELECT p.position,
       SUM(f.corners_taken)                             AS total_corners,
       CAST(AVG(1.0 * f.corners_taken) AS DECIMAL(5, 2)) AS avg_corners_per_player
FROM dbo.fact_attacking AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
GROUP BY p.position
ORDER BY total_corners DESC;
GO
