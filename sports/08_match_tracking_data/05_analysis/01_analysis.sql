/* =============================================================================
   01_analysis.sql
============================================================================= */

USE MatchTracking;
GO

/* ---- 1. Physical output per player --------------------------------------- */
SELECT player_code, team, minutes_tracked, distance_km, high_speed_km, sprints, top_speed_kmh,
       CAST(1000 * distance_km / NULLIF(minutes_tracked, 0) AS DECIMAL(6, 1)) AS metres_per_minute
FROM gold.dim_player
ORDER BY team, distance_km DESC;
GO

/* ---- 2. First half vs second half ---------------------------------------- */
SELECT ps.team, s.period,
       CAST(SUM(CASE WHEN s.is_glitch = 0 THEN s.step_m END) / 1000 AS DECIMAL(6, 2)) AS team_distance_km,
       (SELECT COUNT(*) FROM gold.fact_sprint AS sp
        INNER JOIN silver.player_slot AS q ON q.player_code = sp.player_code
        WHERE q.team = ps.team AND sp.period = s.period) AS sprints
FROM gold.fact_player_sample AS s
INNER JOIN silver.player_slot AS ps ON ps.player_code = s.player_code
GROUP BY ps.team, s.period
ORDER BY ps.team, s.period;
GO

/* ---- 3. Team shape: average width and depth of the outfield players ------ */
-- the goalkeeper is the player with the smallest average distance to a goal line
WITH keeper AS (
    SELECT ps.team, p.player_code,
           ROW_NUMBER() OVER (PARTITION BY ps.team
                              ORDER BY AVG(CASE WHEN p.x_m < 52.5 THEN p.x_m ELSE 105 - p.x_m END)) AS rn
    FROM silver.player_position AS p
    INNER JOIN silver.player_slot AS ps ON ps.player_code = p.player_code
    GROUP BY ps.team, p.player_code
),
shape AS (
    SELECT ps.team, p.period, p.frame,
           MAX(p.y_m) - MIN(p.y_m) AS width_m,
           MAX(p.x_m) - MIN(p.x_m) AS depth_m
    FROM silver.player_position AS p
    INNER JOIN silver.player_slot AS ps ON ps.player_code = p.player_code
    WHERE p.player_code NOT IN (SELECT player_code FROM keeper WHERE rn = 1)
    GROUP BY ps.team, p.period, p.frame
)
SELECT team, period,
       CAST(AVG(width_m) AS DECIMAL(5, 1)) AS avg_width_m,
       CAST(AVG(depth_m) AS DECIMAL(5, 1)) AS avg_depth_m,
       CAST(AVG(width_m * depth_m) AS DECIMAL(7, 0)) AS avg_area_m2
FROM shape
GROUP BY team, period
ORDER BY team, period;
GO

/* ---- 4. Pass network: most frequent passing pairs ------------------------ */
SELECT TOP (15) team, from_player, to_player, COUNT(*) AS passes
FROM silver.match_event
WHERE event_type = 'PASS' AND to_player IS NOT NULL
GROUP BY team, from_player, to_player
ORDER BY passes DESC;
GO

/* ---- 5. Do the events agree with the tracking? --------------------------- */
-- at the moment a pass is logged, the passer should be next to the ball
DECLARE @agree DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'event_match_distance_m');

WITH pass_check AS (
    SELECT e.event_id, e.team,
           SQRT(SQUARE(p.x_m - b.ball_x_m) + SQUARE(p.y_m - b.ball_y_m)) AS passer_to_ball_m
    FROM silver.match_event AS e
    INNER JOIN silver.ball_frame      AS b ON b.frame = e.sample_frame
    INNER JOIN silver.player_position AS p ON p.player_code = e.from_player AND p.frame = e.sample_frame
    WHERE e.event_type = 'PASS' AND b.ball_x_m IS NOT NULL
)
SELECT team, COUNT(*) AS passes_checked,
       SUM(CASE WHEN passer_to_ball_m <= @agree THEN 1 ELSE 0 END) AS passer_near_ball,
       CAST(100.0 * SUM(CASE WHEN passer_to_ball_m <= @agree THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 1)) AS agreement_pct,
       CAST(AVG(passer_to_ball_m) AS DECIMAL(5, 2)) AS avg_distance_m
FROM pass_check
GROUP BY team;
GO
