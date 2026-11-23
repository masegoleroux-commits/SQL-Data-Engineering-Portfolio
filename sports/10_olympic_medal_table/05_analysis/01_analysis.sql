/* =============================================================================
   01_analysis.sql
============================================================================= */

USE OlympicMedals;
GO

/* ---- 1. The grain mistake, measured --------------------------------------- */
-- what a naive SUM of medal rows would claim, against the real count
SELECT TOP (15) e.noc,
       COUNT(*) AS medal_rows_naive,
       (SELECT COUNT(*) FROM gold.fact_medal AS m WHERE m.noc = e.noc) AS medals_actual,
       COUNT(*) - (SELECT COUNT(*) FROM gold.fact_medal AS m WHERE m.noc = e.noc) AS overcount
FROM gold.fact_entry AS e
WHERE e.medal IS NOT NULL
GROUP BY e.noc
ORDER BY overcount DESC;
GO

/* ---- 2. Medal table for each Games (top 10) ------------------------------- */
SELECT games, position, noc, gold, silver, bronze, total
FROM (SELECT v.*, RANK() OVER (PARTITION BY v.games ORDER BY v.gold DESC, v.silver DESC, v.bronze DESC) AS position
      FROM gold.v_medal_table AS v) AS x
WHERE position <= 10
ORDER BY games, position;
GO

/* ---- 3. Host effect: medals at home vs the average elsewhere -------------- */
SELECT g.games, g.host_noc,
       COALESCE(home.total, 0) AS medals_at_home,
       CAST(AVG(1.0 * other.total) AS DECIMAL(6, 1)) AS avg_medals_same_season_elsewhere
FROM gold.dim_games AS g
LEFT JOIN gold.v_medal_table AS home ON home.games = g.games AND home.noc = g.host_noc
INNER JOIN gold.dim_games AS og ON og.season = g.season AND og.games <> g.games
LEFT JOIN gold.v_medal_table AS other ON other.games = og.games AND other.noc = g.host_noc
GROUP BY g.games, g.host_noc, home.total
ORDER BY g.games;
GO

/* ---- 4. Medals per athlete sent ------------------------------------------- */
DECLARE @min_medals DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'min_medals_ranking');

SELECT TOP (20) c.region, e.noc,
       COUNT(DISTINCT CONCAT(e.athlete_id, '|', d.games)) AS athlete_games,
       (SELECT COUNT(*) FROM gold.fact_medal AS m WHERE m.noc = e.noc) AS medals,
       CAST(100.0 * (SELECT COUNT(*) FROM gold.fact_medal AS m WHERE m.noc = e.noc)
            / COUNT(DISTINCT CONCAT(e.athlete_id, '|', d.games)) AS DECIMAL(5, 1)) AS medals_per_100_athletes
FROM gold.fact_entry AS e
INNER JOIN gold.dim_event   AS d ON d.event_key = e.event_key
INNER JOIN gold.dim_country AS c ON c.noc = e.noc
GROUP BY c.region, e.noc
HAVING (SELECT COUNT(*) FROM gold.fact_medal AS m WHERE m.noc = e.noc) >= @min_medals
ORDER BY medals_per_100_athletes DESC;
GO
