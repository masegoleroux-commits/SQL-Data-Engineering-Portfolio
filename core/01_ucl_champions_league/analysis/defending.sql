/* =============================================================================
   defending.sql
   Defensive output, UCL 2021/22. Source table: fact_defending.
============================================================================= */

USE UCL;
GO

-- Thresholds come from dbo.business_parameter (ddl/07_business_parameters.sql).
DECLARE @min_tackles INT = (SELECT param_value FROM dbo.business_parameter WHERE param_name = 'min_tackles'),
        @min_matches INT = (SELECT param_value FROM dbo.business_parameter WHERE param_name = 'min_matches'),
        @ever_present_share DECIMAL(4, 2) = (SELECT param_value FROM dbo.business_parameter WHERE param_name = 'ever_present_share');

-- 1. Best tackle success rate (minimum @min_tackles tackles)
SELECT TOP (20)
    p.player_name, p.club_name, p.position, f.tackles, f.tackles_won,
    CAST(100.0 * f.tackles_won / f.tackles AS DECIMAL(5, 1)) AS tackle_success_pct
FROM dbo.fact_defending AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE f.tackles >= @min_tackles
ORDER BY tackle_success_pct DESC, f.tackles DESC;


-- 2. Clubs by balls recovered per match
-- Uses total recoveries / total player-matches rather than an average of
-- per-player ratios, which would over-weight players with one appearance.
SELECT TOP (10)
    c.club_name,
    SUM(f.balls_recovered)                                                       AS balls_recovered,
    CAST(1.0 * SUM(f.balls_recovered) / SUM(f.matches_played) AS DECIMAL(5, 2))  AS recoveries_per_player_match
FROM dbo.fact_defending AS f
INNER JOIN dbo.dim_club AS c ON c.club_key = f.club_key
GROUP BY c.club_name
ORDER BY recoveries_per_player_match DESC;


-- 3. Clearances by club
SELECT c.club_name, SUM(f.clearances_attempted) AS total_clearances
FROM dbo.fact_defending AS f
INNER JOIN dbo.dim_club AS c ON c.club_key = f.club_key
GROUP BY c.club_name
ORDER BY total_clearances DESC;


-- 4. Tackles won by club, with team success rate
SELECT TOP (10)
    c.club_name,
    SUM(f.tackles_won)                                                     AS tackles_won,
    SUM(f.tackles)                                                         AS tackles,
    CAST(100.0 * SUM(f.tackles_won) / NULLIF(SUM(f.tackles), 0) AS DECIMAL(5, 1)) AS tackle_success_pct
FROM dbo.fact_defending AS f
INNER JOIN dbo.dim_club AS c ON c.club_key = f.club_key
GROUP BY c.club_name
ORDER BY tackles_won DESC;


-- 5. Most tackles per match (minimum @min_matches matches)
SELECT TOP (20)
    p.player_name, p.club_name, f.tackles, f.matches_played,
    CAST(1.0 * f.tackles / f.matches_played AS DECIMAL(4, 2)) AS tackles_per_match
FROM dbo.fact_defending AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE f.matches_played >= @min_matches
ORDER BY tackles_per_match DESC;


-- 6. All-round defenders: top quartile for BOTH recoveries and clearances
WITH quartiles AS (
    SELECT f.player_key, f.balls_recovered, f.clearances_attempted,
           NTILE(4) OVER (ORDER BY f.balls_recovered DESC)      AS recovery_quartile,
           NTILE(4) OVER (ORDER BY f.clearances_attempted DESC) AS clearance_quartile
    FROM dbo.fact_defending AS f
)
SELECT p.player_name, p.club_name, p.position, q.balls_recovered, q.clearances_attempted
FROM quartiles AS q
INNER JOIN dbo.dim_player AS p ON p.player_key = q.player_key
WHERE q.recovery_quartile = 1
  AND q.clearance_quartile = 1
ORDER BY q.balls_recovered + q.clearances_attempted DESC;


-- 7. Head-to-head: compare any two players
DECLARE @player_a NVARCHAR(100) = N'Koke',
        @player_b NVARCHAR(100) = N'Rodri';

SELECT p.player_name, p.club_name, f.matches_played, f.balls_recovered,
       f.tackles, f.tackles_won, f.clearances_attempted
FROM dbo.fact_defending AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE p.player_name IN (@player_a, @player_b);


-- 8. Ever-presents: played at least @ever_present_share of the most matches any player played
SELECT p.player_name, p.club_name, f.matches_played
FROM dbo.fact_defending AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE f.matches_played >= @ever_present_share * (SELECT MAX(matches_played) FROM dbo.fact_defending)
ORDER BY f.matches_played DESC, p.player_name;


-- 9. Defensive profile by position
SELECT p.position,
       COUNT(*)                                                                      AS players,
       CAST(1.0 * SUM(f.balls_recovered)      / SUM(f.matches_played) AS DECIMAL(4, 2)) AS recoveries_per_match,
       CAST(1.0 * SUM(f.tackles)              / SUM(f.matches_played) AS DECIMAL(4, 2)) AS tackles_per_match,
       CAST(1.0 * SUM(f.clearances_attempted) / SUM(f.matches_played) AS DECIMAL(4, 2)) AS clearances_per_match
FROM dbo.fact_defending AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
GROUP BY p.position
ORDER BY recoveries_per_match DESC;
GO
