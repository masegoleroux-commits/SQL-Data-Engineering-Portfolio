/* =============================================================================
   01_analysis.sql
============================================================================= */

USE FantasyPoints;
GO

/* ---- 1. Season leaders, with where the points came from ------------------ */
DECLARE @official DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'official_rule_set');

SELECT TOP (15) d.player_name, d.position, d.current_team,
       SUM(b.points) AS total_points,
       SUM(CASE WHEN b.event = 'goal'        THEN b.points ELSE 0 END) AS from_goals,
       SUM(CASE WHEN b.event = 'assist'      THEN b.points ELSE 0 END) AS from_assists,
       SUM(CASE WHEN b.event = 'clean_sheet' THEN b.points ELSE 0 END) AS from_clean_sheets,
       SUM(CASE WHEN b.event = 'bonus'       THEN b.points ELSE 0 END) AS from_bonus,
       SUM(CASE WHEN b.points < 0            THEN b.points ELSE 0 END) AS deductions
FROM gold.fact_points_breakdown AS b
INNER JOIN gold.dim_player AS d ON d.player_id = b.player_id
WHERE b.rule_set = @official
GROUP BY d.player_name, d.position, d.current_team
ORDER BY total_points DESC;
GO

/* ---- 2. Value: points per million ---------------------------------------- */
DECLARE @min_matches DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'min_matches_value');

SELECT TOP (20) d.player_name, d.position,
       SUM(f.official_points)                                   AS points,
       CAST(AVG(f.price_millions) AS DECIMAL(4, 1))             AS avg_price,
       CAST(SUM(f.official_points) / AVG(f.price_millions) AS DECIMAL(6, 1)) AS points_per_million
FROM gold.fact_player_fixture AS f
INNER JOIN gold.dim_player AS d ON d.player_id = f.player_id
WHERE f.minutes > 0
GROUP BY d.player_name, d.position
HAVING COUNT(*) >= @min_matches
ORDER BY points_per_million DESC;
GO

/* ---- 3. What-if: who gains most from the scenario rule set? --------------- */
SELECT TOP (15) d.player_name, d.position,
       SUM(f.official_points)                           AS official_points,
       SUM(f.scenario_points)                           AS scenario_points,
       SUM(f.scenario_points) - SUM(f.official_points)  AS change,
       RANK() OVER (ORDER BY SUM(f.official_points) DESC) AS official_rank,
       RANK() OVER (ORDER BY SUM(f.scenario_points) DESC) AS scenario_rank
FROM gold.fact_player_fixture AS f
INNER JOIN gold.dim_player AS d ON d.player_id = f.player_id
GROUP BY d.player_name, d.position
ORDER BY change DESC;
GO

/* ---- 4. Points by position, per 90 minutes ------------------------------- */
SELECT d.position,
       COUNT(DISTINCT d.player_id)                                   AS players,
       SUM(f.official_points)                                        AS points,
       CAST(90.0 * SUM(f.official_points) / NULLIF(SUM(f.minutes), 0) AS DECIMAL(4, 2)) AS points_per_90
FROM gold.fact_player_fixture AS f
INNER JOIN gold.dim_player AS d ON d.player_id = f.player_id
GROUP BY d.position
ORDER BY points_per_90 DESC;
GO
