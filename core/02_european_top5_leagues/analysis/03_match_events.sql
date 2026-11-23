/* =============================================================================
   03_match_events.sql
   Stage 6: comebacks, finishing and referees.
============================================================================= */

USE EuroLeagues;
GO

DECLARE @min_referee_matches INT = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'min_referee_matches');

-- 1. Comeback kings: points won from losing positions at half-time
SELECT TOP (15)
    t.team_name,
    l.league_name,
    SUM(CASE WHEN tm.ht_goals_for < tm.ht_goals_against THEN 1 ELSE 0 END)                    AS behind_at_half_time,
    SUM(CASE WHEN tm.ht_goals_for < tm.ht_goals_against AND tm.result = 'W' THEN 1 ELSE 0 END) AS turned_into_wins,
    SUM(CASE WHEN tm.ht_goals_for < tm.ht_goals_against THEN tm.points ELSE 0 END)            AS points_from_losing_positions
FROM dw.fact_team_match AS tm
INNER JOIN dw.dim_team   AS t ON t.team_key   = tm.team_key
INNER JOIN dw.dim_league AS l ON l.league_key = tm.league_key
WHERE tm.ht_goals_for IS NOT NULL
GROUP BY t.team_name, l.league_name
ORDER BY points_from_losing_positions DESC, turned_into_wins DESC;

-- 2. Clinical finishing: goals per shot on target (min 150 shots on target, complete stats only)
SELECT TOP (15)
    t.team_name,
    l.league_name,
    SUM(tm.shots_on_target_for)                                                  AS shots_on_target,
    SUM(tm.goals_for)                                                            AS goals,
    CAST(100.0 * SUM(tm.goals_for) / SUM(tm.shots_on_target_for) AS DECIMAL(4, 1)) AS goals_per_100_on_target
FROM dw.fact_team_match AS tm
INNER JOIN dw.dim_team   AS t ON t.team_key   = tm.team_key
INNER JOIN dw.dim_league AS l ON l.league_key = tm.league_key
WHERE tm.stats_complete = 1
GROUP BY t.team_name, l.league_name
HAVING SUM(tm.shots_on_target_for) >= 150
ORDER BY goals_per_100_on_target DESC;

-- 3. Premier League referees: cards per match (only league with referee data)
SELECT
    r.referee_name,
    COUNT(*)                                                                             AS matches,
    CAST(1.0 * SUM(f.home_yellows + f.away_yellows) / COUNT(*) AS DECIMAL(4, 2))         AS yellows_per_match,
    SUM(f.home_reds + f.away_reds)                                                       AS red_cards,
    CAST(1.0 * SUM(f.home_fouls + f.away_fouls) / COUNT(*) AS DECIMAL(4, 1))             AS fouls_per_match,
    CAST(100.0 * SUM(CASE WHEN f.ft_result = 'H' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(4, 1)) AS home_win_pct
FROM dw.fact_match AS f
INNER JOIN dw.dim_referee AS r ON r.referee_key = f.referee_key
WHERE f.referee_key <> -1
  AND f.stats_complete = 1
GROUP BY r.referee_name
HAVING COUNT(*) >= @min_referee_matches
ORDER BY yellows_per_match DESC;

-- 4. Matches with the most goals
SELECT TOP (10)
    d.full_date, l.league_name, th.team_name AS home_team, f.ft_home_goals, f.ft_away_goals, ta.team_name AS away_team
FROM dw.fact_match AS f
INNER JOIN dw.dim_date   AS d  ON d.date_key   = f.date_key
INNER JOIN dw.dim_league AS l  ON l.league_key = f.league_key
INNER JOIN dw.dim_team   AS th ON th.team_key  = f.home_team_key
INNER JOIN dw.dim_team   AS ta ON ta.team_key  = f.away_team_key
ORDER BY f.ft_home_goals + f.ft_away_goals DESC, d.full_date;
GO
