/* =============================================================================
   discipline.sql
   Fouls and cards, UCL 2021/22. Source table: fact_discipline.
   Cards have already been corrected for the swapped source columns.
============================================================================= */

USE UCL;
GO

-- Thresholds come from dbo.business_parameter (ddl/07_business_parameters.sql).
DECLARE @min_minutes INT = (SELECT param_value FROM dbo.business_parameter WHERE param_name = 'min_minutes');

-- 1. Most fouls committed
SELECT TOP (10)
    p.player_name, p.club_name, p.position, f.fouls_committed, f.matches_played
FROM dbo.fact_discipline AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
ORDER BY f.fouls_committed DESC;


-- 2. Fouls per 90 minutes (minimum @min_minutes, 270 by default = three full games)
SELECT TOP (10)
    p.player_name, p.club_name, f.fouls_committed, f.minutes_played,
    CAST(90.0 * f.fouls_committed / f.minutes_played AS DECIMAL(4, 2)) AS fouls_per_90
FROM dbo.fact_discipline AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE f.minutes_played >= @min_minutes
ORDER BY fouls_per_90 DESC;


-- 3. Most fouled players
SELECT TOP (10)
    p.player_name, p.club_name, p.position, f.fouls_suffered,
    CAST(90.0 * f.fouls_suffered / f.minutes_played AS DECIMAL(4, 2)) AS fouled_per_90
FROM dbo.fact_discipline AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
ORDER BY f.fouls_suffered DESC;


-- 4. Most cautioned players
SELECT TOP (10)
    p.player_name, p.club_name, f.yellow_cards, f.red_cards, f.matches_played
FROM dbo.fact_discipline AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
ORDER BY f.yellow_cards DESC, f.red_cards DESC;


-- 5. Players sent off
SELECT p.player_name, p.club_name, p.position, f.red_cards, f.yellow_cards
FROM dbo.fact_discipline AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE f.red_cards > 0
ORDER BY f.red_cards DESC, p.player_name;


-- 6. Discipline by position, normalised per 90 minutes
SELECT p.position,
       COUNT(*)                                                                    AS players,
       CAST(90.0 * SUM(f.fouls_committed) / SUM(f.minutes_played) AS DECIMAL(4, 2)) AS fouls_per_90,
       CAST(90.0 * SUM(f.yellow_cards)    / SUM(f.minutes_played) AS DECIMAL(4, 3)) AS yellows_per_90,
       SUM(f.red_cards)                                                            AS red_cards
FROM dbo.fact_discipline AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
GROUP BY p.position
ORDER BY fouls_per_90 DESC;


-- 7. Club card totals
SELECT c.club_name,
       SUM(f.yellow_cards)    AS yellow_cards,
       SUM(f.red_cards)       AS red_cards,
       SUM(f.fouls_committed) AS fouls_committed
FROM dbo.fact_discipline AS f
INNER JOIN dbo.dim_club AS c ON c.club_key = f.club_key
GROUP BY c.club_name
ORDER BY yellow_cards DESC, red_cards DESC;


-- 8. Club discipline rate: fouls and yellows per 90 player-minutes
SELECT c.club_name,
       CAST(90.0 * SUM(f.fouls_committed) / SUM(f.minutes_played) AS DECIMAL(4, 2)) AS fouls_per_90,
       CAST(90.0 * SUM(f.yellow_cards)    / SUM(f.minutes_played) AS DECIMAL(4, 3)) AS yellows_per_90
FROM dbo.fact_discipline AS f
INNER JOIN dbo.dim_club AS c ON c.club_key = f.club_key
GROUP BY c.club_name
ORDER BY fouls_per_90 DESC;


-- 9. Clean records: most minutes played without a single card
SELECT TOP (15)
    p.player_name, p.club_name, p.position, f.minutes_played, f.fouls_committed
FROM dbo.fact_discipline AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE f.yellow_cards = 0
  AND f.red_cards = 0
ORDER BY f.minutes_played DESC;


-- 10. Single-player lookup
DECLARE @player NVARCHAR(100) = N'Casemiro';

SELECT p.player_name, p.club_name, f.matches_played, f.minutes_played,
       f.fouls_committed, f.fouls_suffered, f.yellow_cards, f.red_cards
FROM dbo.fact_discipline AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE p.player_name = @player;
GO
