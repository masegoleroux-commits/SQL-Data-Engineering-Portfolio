/* =============================================================================
   01_league_tables.sql
   Stage 6: league tables rebuilt from match results.

   Ranking uses points, then goal difference, then goals scored. That is the
   Premier League rule; La Liga and Serie A use head-to-head results first,
   so a few tied positions there can differ from the official table.
============================================================================= */

USE EuroLeagues;
GO

CREATE OR ALTER VIEW rpt.v_league_table
AS
WITH totals AS (
    SELECT tm.league_key, tm.season_key, tm.team_key,
           COUNT(*)                                        AS played,
           SUM(CASE WHEN tm.result = 'W' THEN 1 ELSE 0 END) AS won,
           SUM(CASE WHEN tm.result = 'D' THEN 1 ELSE 0 END) AS drawn,
           SUM(CASE WHEN tm.result = 'L' THEN 1 ELSE 0 END) AS lost,
           SUM(tm.goals_for)                               AS goals_for,
           SUM(tm.goals_against)                           AS goals_against,
           SUM(tm.goals_for) - SUM(tm.goals_against)       AS goal_difference,
           SUM(tm.points)                                  AS points
    FROM dw.fact_team_match AS tm
    GROUP BY tm.league_key, tm.season_key, tm.team_key
),
ranked AS (
    SELECT t.*,
           RANK() OVER (PARTITION BY t.league_key, t.season_key
                        ORDER BY t.points DESC, t.goal_difference DESC, t.goals_for DESC) AS position,
           COUNT(*) OVER (PARTITION BY t.league_key, t.season_key)                         AS teams_in_league
    FROM totals AS t
)
SELECT
    l.league_name,
    s.season_label,
    r.position,
    tm.team_name,
    r.played, r.won, r.drawn, r.lost,
    r.goals_for, r.goals_against, r.goal_difference, r.points,
    CAST(1.0 * r.points / r.played AS DECIMAL(4, 2)) AS points_per_game,
    CASE WHEN r.position = 1 THEN 'Champions'
         WHEN r.position > r.teams_in_league - ls.relegation_places THEN 'Relegated'
         ELSE '' END                               AS zone,
    r.league_key, r.season_key, r.team_key
FROM ranked AS r
INNER JOIN dw.dim_league   AS l  ON l.league_key  = r.league_key
INNER JOIN dw.dim_season   AS s  ON s.season_key  = r.season_key
INNER JOIN dw.dim_team     AS tm ON tm.team_key   = r.team_key
INNER JOIN cfg.league_season AS ls
    ON  ls.league_code       = l.league_code
    AND ls.season_start_year = r.season_key;
GO

-- 1. Champions of every league and season
SELECT league_name, season_label, team_name, points, won, drawn, lost, goal_difference
FROM rpt.v_league_table
WHERE position = 1
ORDER BY league_name, season_label;

-- 2. Full Premier League table, 2024/25
SELECT position, team_name, played, won, drawn, lost, goals_for, goals_against,
       goal_difference, points, zone
FROM rpt.v_league_table
WHERE league_name = N'Premier League' AND season_label = '2024/25'
ORDER BY position;

-- 3. How dominant were the champions? Gap to second place
WITH top2 AS (
    SELECT league_name, season_label, team_name, points, position,
           LEAD(points) OVER (PARTITION BY league_name, season_label ORDER BY position, team_name) AS next_points
    FROM rpt.v_league_table
    WHERE position <= 2
)
SELECT league_name, season_label, team_name AS champion, points, points - next_points AS gap_to_second
FROM top2
WHERE position = 1
ORDER BY gap_to_second DESC;

-- 4. Points needed to stay up: points of the best relegated team
SELECT league_name, season_label, MAX(points) AS best_relegated_team_points
FROM rpt.v_league_table
WHERE zone = 'Relegated'
GROUP BY league_name, season_label
ORDER BY league_name, season_label;
GO
