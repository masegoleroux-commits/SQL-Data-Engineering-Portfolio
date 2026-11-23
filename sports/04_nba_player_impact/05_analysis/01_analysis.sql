/* =============================================================================
   01_analysis.sql
============================================================================= */

USE NbaPlayerImpact;
GO

/* ---- 1. Most valuable players of each season (wins above replacement) --- */
SELECT season, player_name, minutes, war, raptor_total, rk
FROM (
    SELECT f.season, d.player_name, f.minutes,
           CAST(f.war_total AS DECIMAL(5, 1))    AS war,
           CAST(f.raptor_total AS DECIMAL(5, 1)) AS raptor_total,
           RANK() OVER (PARTITION BY f.season ORDER BY f.war_total DESC) AS rk
    FROM gold.fact_player_season AS f
    INNER JOIN gold.dim_player AS d ON d.player_name_key = f.player_name_key
    WHERE f.is_qualified = 1
) AS x
WHERE rk <= 5
ORDER BY season, rk;
GO

/* ---- 2. Biggest improvers year on year ----------------------------------- */
WITH yoy AS (
    SELECT f.player_id, f.season, f.raptor_total, f.is_qualified,
           LAG(f.raptor_total) OVER (PARTITION BY f.player_id ORDER BY f.season) AS prev_raptor,
           LAG(f.season)       OVER (PARTITION BY f.player_id ORDER BY f.season) AS prev_season,
           LAG(f.is_qualified) OVER (PARTITION BY f.player_id ORDER BY f.season) AS prev_qualified
    FROM gold.fact_player_season AS f
)
SELECT TOP (20) d.player_name, y.season,
       CAST(y.prev_raptor AS DECIMAL(5, 1))                 AS raptor_before,
       CAST(y.raptor_total AS DECIMAL(5, 1))                AS raptor_after,
       CAST(y.raptor_total - y.prev_raptor AS DECIMAL(5, 1)) AS improvement
FROM yoy AS y
INNER JOIN gold.dim_player AS d ON d.player_id = y.player_id AND d.is_current = 1
WHERE y.is_qualified = 1 AND y.prev_qualified = 1 AND y.prev_season = y.season - 1
ORDER BY improvement DESC;
GO

/* ---- 3. Player types: offence-first, defence-first, two-way -------------- */
SELECT f.season,
       SUM(CASE WHEN f.raptor_offense > 0 AND f.raptor_defense > 0 THEN 1 ELSE 0 END)  AS two_way,
       SUM(CASE WHEN f.raptor_offense > 0 AND f.raptor_defense <= 0 THEN 1 ELSE 0 END) AS offence_first,
       SUM(CASE WHEN f.raptor_offense <= 0 AND f.raptor_defense > 0 THEN 1 ELSE 0 END) AS defence_first,
       SUM(CASE WHEN f.raptor_offense <= 0 AND f.raptor_defense <= 0 THEN 1 ELSE 0 END) AS below_average
FROM gold.fact_player_season AS f
WHERE f.is_qualified = 1
GROUP BY f.season
ORDER BY f.season;
GO

/* ---- 4. Name history from the Type 2 dimension --------------------------- */
SELECT player_id, player_name, valid_from, valid_to, is_current
FROM gold.dim_player
WHERE player_id IN (SELECT player_id FROM gold.dim_player GROUP BY player_id HAVING COUNT(*) > 1)
ORDER BY player_id, valid_from;
GO
