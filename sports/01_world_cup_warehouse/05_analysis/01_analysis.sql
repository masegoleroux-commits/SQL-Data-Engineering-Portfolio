/* =============================================================================
   01_analysis.sql
   Questions answered from the gold layer. Thresholds come from
   ops.business_parameter, so changing a parameter changes the answer without
   touching the queries.
============================================================================= */

USE WorldCup;
GO

/* ---- 1. All-time table (men's), points under today's 3-1-0 system -------- */
DECLARE @points_win  DECIMAL(10, 2) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'points_win');
DECLARE @points_draw DECIMAL(10, 2) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'points_draw');
DECLARE @min_matches DECIMAL(10, 2) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'min_matches_ranking');

SELECT tt.team_name,
       COUNT(DISTINCT tm.tournament_key)                               AS tournaments,
       COUNT(*)                                                        AS matches,
       SUM(CASE WHEN tm.outcome = 'W' THEN 1 ELSE 0 END)               AS wins,
       SUM(CASE WHEN tm.outcome = 'D' THEN 1 ELSE 0 END)               AS draws,
       SUM(CASE WHEN tm.outcome = 'L' THEN 1 ELSE 0 END)               AS losses,
       SUM(tm.goals_for) - SUM(tm.goals_against)                       AS goal_difference,
       SUM(CASE tm.outcome WHEN 'W' THEN @points_win WHEN 'D' THEN @points_draw ELSE 0 END) AS points,
       CAST(SUM(CASE tm.outcome WHEN 'W' THEN @points_win WHEN 'D' THEN @points_draw ELSE 0 END)
            / COUNT(*) AS DECIMAL(5, 2))                               AS points_per_match
FROM gold.fact_team_match AS tm
INNER JOIN gold.dim_team       AS tt ON tt.team_key       = tm.team_key
INNER JOIN gold.dim_tournament AS t  ON t.tournament_key  = tm.tournament_key
WHERE t.gender = 'Men'
GROUP BY tt.team_name
HAVING COUNT(*) >= @min_matches
ORDER BY points DESC, goal_difference DESC;
GO

/* ---- 2. All-time scorers (own goals excluded) ---------------------------- */
DECLARE @min_goals DECIMAL(10, 2) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'min_goals_scorer');

SELECT p.player_name,
       p.gender,
       COUNT(*)                                            AS goals,
       SUM(g.is_penalty)                                   AS penalties,
       COUNT(DISTINCT f.tournament_key)                    AS tournaments_scored_in,
       RANK() OVER (PARTITION BY p.gender ORDER BY COUNT(*) DESC) AS rank_in_gender
FROM gold.fact_goal AS g
INNER JOIN gold.dim_player AS p ON p.player_key = g.player_key
INNER JOIN gold.fact_match AS f ON f.match_key  = g.match_key
WHERE g.is_own_goal = 0
GROUP BY p.player_name, p.gender
HAVING COUNT(*) >= @min_goals
ORDER BY p.gender, goals DESC;
GO

/* ---- 3. Late goals by decade --------------------------------------------- */
DECLARE @late_minute DECIMAL(10, 2) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'late_goal_minute');

SELECT (t.tournament_year / 10) * 10                                AS decade,
       COUNT(*)                                                     AS goals,
       SUM(CASE WHEN g.minute_regulation >= @late_minute
                 AND g.is_extra_time = 0 THEN 1 ELSE 0 END)         AS late_goals,
       CAST(100.0 * SUM(CASE WHEN g.minute_regulation >= @late_minute
                              AND g.is_extra_time = 0 THEN 1 ELSE 0 END)
            / COUNT(*) AS DECIMAL(5, 1))                            AS late_goal_pct,
       CAST(1.0 * COUNT(*) / COUNT(DISTINCT g.match_key) AS DECIMAL(4, 2)) AS goals_per_match
FROM gold.fact_goal AS g
INNER JOIN gold.fact_match     AS f ON f.match_key      = g.match_key
INNER JOIN gold.dim_tournament AS t ON t.tournament_key = f.tournament_key
WHERE t.gender = 'Men'
GROUP BY (t.tournament_year / 10) * 10
ORDER BY decade;
GO

/* ---- 4. Does hosting help? Host nation vs its own record elsewhere -------- */
WITH host_teams AS (
    SELECT DISTINCT tm.team_key
    FROM gold.fact_team_match AS tm
    WHERE tm.is_host = 1
)
SELECT tt.team_name,
       SUM(CASE WHEN tm.is_host = 1 THEN 1 ELSE 0 END)                         AS matches_as_host,
       CAST(100.0 * SUM(CASE WHEN tm.is_host = 1 AND tm.outcome = 'W' THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN tm.is_host = 1 THEN 1 ELSE 0 END), 0) AS DECIMAL(5, 1)) AS win_pct_as_host,
       SUM(CASE WHEN tm.is_host = 0 THEN 1 ELSE 0 END)                         AS matches_elsewhere,
       CAST(100.0 * SUM(CASE WHEN tm.is_host = 0 AND tm.outcome = 'W' THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN tm.is_host = 0 THEN 1 ELSE 0 END), 0) AS DECIMAL(5, 1)) AS win_pct_elsewhere
FROM gold.fact_team_match AS tm
INNER JOIN host_teams    AS h  ON h.team_key  = tm.team_key
INNER JOIN gold.dim_team AS tt ON tt.team_key = tm.team_key
GROUP BY tt.team_name
ORDER BY matches_as_host DESC;
GO

/* ---- 5. Penalty shootout records ----------------------------------------- */
SELECT tt.team_name,
       COUNT(*)                                            AS shootouts,
       SUM(tm.went_through)                                AS won,
       COUNT(*) - SUM(tm.went_through)                     AS lost
FROM gold.fact_team_match AS tm
INNER JOIN gold.fact_match AS f  ON f.match_key  = tm.match_key
INNER JOIN gold.dim_team   AS tt ON tt.team_key  = tm.team_key
WHERE f.penalty_shootout = 1
GROUP BY tt.team_name
ORDER BY shootouts DESC, won DESC;
GO

/* ---- 6. How far each team went, tournament by tournament ----------------- */
SELECT t.tournament_name,
       tt.team_name,
       v.matches, v.wins, v.draws, v.losses, v.goals_for, v.goals_against,
       s.stage_name AS furthest_stage,
       CASE WHEN tt.team_name = t.winner THEN 1 ELSE 0 END AS is_winner
FROM gold.v_team_tournament AS v
INNER JOIN gold.dim_tournament AS t  ON t.tournament_key = v.tournament_key
INNER JOIN gold.dim_team       AS tt ON tt.team_key      = v.team_key
INNER JOIN (SELECT stage_order, MIN(stage_name) AS stage_name
            FROM gold.dim_stage GROUP BY stage_order) AS s
        ON s.stage_order = v.furthest_stage_order
ORDER BY t.tournament_year, t.gender, v.furthest_stage_order DESC, v.wins DESC;
GO
