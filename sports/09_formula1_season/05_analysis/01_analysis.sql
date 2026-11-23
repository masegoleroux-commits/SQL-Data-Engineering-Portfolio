/* =============================================================================
   01_analysis.sql
============================================================================= */

USE Formula1;
GO

/* ---- 1. Final championship tables ----------------------------------------- */
SELECT RANK() OVER (ORDER BY s.total_points DESC) AS position, d.driver_name, s.total_points
FROM gold.v_standing AS s
INNER JOIN gold.dim_driver AS d ON d.driver_key = s.driver_key
WHERE s.round_no = (SELECT MAX(round_no) FROM gold.v_standing AS x WHERE x.driver_key = s.driver_key)
ORDER BY s.total_points DESC;

SELECT RANK() OVER (ORDER BY s.total_points DESC) AS position, t.team_name, s.total_points
FROM gold.v_team_standing AS s
INNER JOIN gold.dim_team AS t ON t.team_key = s.team_key
WHERE s.round_no = (SELECT MAX(round_no) FROM gold.v_team_standing)
ORDER BY s.total_points DESC;
GO

/* ---- 2. When was the title decided? -------------------------------------- */
-- after each round: the leader's margin vs the most points still available
-- (25 + fastest lap per remaining race, 8 per remaining sprint)
DECLARE @fl DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'fastest_lap_bonus');

WITH ranked AS (
    SELECT round_no, driver_key, total_points,
           ROW_NUMBER() OVER (PARTITION BY round_no ORDER BY total_points DESC) AS rk
    FROM gold.v_standing
),
leader AS (
    SELECT a.round_no, a.driver_key, a.total_points - b.total_points AS margin
    FROM ranked AS a INNER JOIN ranked AS b ON b.round_no = a.round_no AND b.rk = 2
    WHERE a.rk = 1
),
remaining AS (
    SELECT r.round_no,
           (SELECT COUNT(*) FROM gold.dim_race AS x WHERE x.round_no > r.round_no AND x.is_cancelled = 0) * ((SELECT MAX(points) FROM ops.points_rule WHERE session_type = 'race') + @fl)
         + (SELECT COUNT(*) FROM gold.dim_race AS x WHERE x.round_no > r.round_no AND x.has_sprint = 1) * (SELECT MAX(points) FROM ops.points_rule WHERE session_type = 'sprint')
           AS max_points_left
    FROM gold.dim_race AS r
    WHERE r.is_cancelled = 0
)
SELECT l.round_no, r.gp_name, d.driver_name AS leader, l.margin, m.max_points_left,
       CASE WHEN l.margin > m.max_points_left THEN 'decided' ELSE 'open' END AS title
FROM leader AS l
INNER JOIN remaining       AS m ON m.round_no = l.round_no
INNER JOIN gold.dim_race   AS r ON r.round_no = l.round_no
INNER JOIN gold.dim_driver AS d ON d.driver_key = l.driver_key
ORDER BY l.round_no;
GO

/* ---- 3. Teammate qualifying head-to-head --------------------------------- */
-- compare the last session both drivers reached: Q3 if both, else Q2, else Q1
WITH pairs AS (
    SELECT a.round_no, a.team_name, a.driver_name AS driver_a, b.driver_name AS driver_b,
           CASE WHEN a.q3_seconds IS NOT NULL AND b.q3_seconds IS NOT NULL THEN a.q3_seconds - b.q3_seconds
                WHEN a.q2_seconds IS NOT NULL AND b.q2_seconds IS NOT NULL THEN a.q2_seconds - b.q2_seconds
                ELSE a.q1_seconds - b.q1_seconds END AS gap_s
    FROM silver.qualifying AS a
    INNER JOIN silver.qualifying AS b
            ON b.round_no = a.round_no AND b.team_name = a.team_name AND b.driver_name > a.driver_name
)
SELECT team_name, driver_a, driver_b,
       SUM(CASE WHEN gap_s < 0 THEN 1 ELSE 0 END) AS a_ahead,
       SUM(CASE WHEN gap_s > 0 THEN 1 ELSE 0 END) AS b_ahead,
       CAST(AVG(gap_s) AS DECIMAL(6, 3))          AS avg_gap_s
FROM pairs
WHERE gap_s IS NOT NULL
GROUP BY team_name, driver_a, driver_b
HAVING COUNT(*) >= 5
ORDER BY team_name;
GO

/* ---- 4. Reliability and racecraft by team -------------------------------- */
SELECT t.team_name,
       COUNT(*)                                                      AS starts,
       SUM(CASE WHEN f.status IN ('DNF', 'DNS') THEN 1 ELSE 0 END)   AS did_not_finish,
       CAST(AVG(1.0 * f.positions_gained) AS DECIMAL(4, 1))          AS avg_places_gained
FROM gold.fact_result AS f
INNER JOIN gold.dim_team AS t ON t.team_key = f.team_key
WHERE f.session_type = 'race'
GROUP BY t.team_name
ORDER BY did_not_finish DESC;
GO
