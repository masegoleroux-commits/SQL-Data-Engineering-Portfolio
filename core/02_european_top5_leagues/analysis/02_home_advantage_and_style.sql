/* =============================================================================
   02_home_advantage_and_style.sql
   Stage 6: how the five leagues differ.
============================================================================= */

USE EuroLeagues;
GO

-- 1. Home advantage by league and season
SELECT l.league_name,
       s.season_label,
       COUNT(*)                                                                       AS matches,
       CAST(100.0 * SUM(CASE WHEN f.ft_result = 'H' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(4, 1)) AS home_win_pct,
       CAST(100.0 * SUM(CASE WHEN f.ft_result = 'D' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(4, 1)) AS draw_pct,
       CAST(100.0 * SUM(CASE WHEN f.ft_result = 'A' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(4, 1)) AS away_win_pct,
       CAST(1.0 * SUM(f.ft_home_goals) / COUNT(*) AS DECIMAL(4, 2))                   AS home_goals_per_match,
       CAST(1.0 * SUM(f.ft_away_goals) / COUNT(*) AS DECIMAL(4, 2))                   AS away_goals_per_match
FROM dw.fact_match AS f
INNER JOIN dw.dim_league AS l ON l.league_key = f.league_key
INNER JOIN dw.dim_season AS s ON s.season_key = f.season_key
GROUP BY l.league_name, s.season_label
ORDER BY l.league_name, s.season_label;

-- 2. League style: goals, shots, accuracy and discipline per match.
--    Only matches with complete statistics are used for the stat columns.
SELECT l.league_name,
       CAST(1.0 * SUM(f.ft_home_goals + f.ft_away_goals) / COUNT(*) AS DECIMAL(4, 2)) AS goals_per_match,
       CAST(1.0 * SUM(CASE WHEN f.stats_complete = 1 THEN f.home_shots + f.away_shots END)
                / SUM(CASE WHEN f.stats_complete = 1 THEN 1 END) AS DECIMAL(5, 2))        AS shots_per_match,
       CAST(100.0 * SUM(CASE WHEN f.stats_complete = 1 THEN f.ft_home_goals + f.ft_away_goals END)
                  / SUM(CASE WHEN f.stats_complete = 1 THEN f.home_shots_on_target + f.away_shots_on_target END)
            AS DECIMAL(4, 1))                                                             AS goals_per_100_on_target,
       CAST(1.0 * SUM(CASE WHEN f.stats_complete = 1 THEN f.home_yellows + f.away_yellows END)
                / SUM(CASE WHEN f.stats_complete = 1 THEN 1 END) AS DECIMAL(4, 2))        AS yellows_per_match,
       CAST(100.0 * SUM(CASE WHEN f.ft_home_goals = 0 OR f.ft_away_goals = 0 THEN 1 ELSE 0 END) / COUNT(*)
            AS DECIMAL(4, 1))                                                             AS clean_sheet_match_pct
FROM dw.fact_match AS f
INNER JOIN dw.dim_league AS l ON l.league_key = f.league_key
GROUP BY l.league_name
ORDER BY goals_per_match DESC;

-- 3. Teams that are much stronger at home than away (2024/25)
WITH split AS (
    SELECT t.team_name, l.league_name,
           CAST(1.0 * SUM(CASE WHEN tm.is_home = 1 THEN tm.points END) / SUM(CASE WHEN tm.is_home = 1 THEN 1 END) AS DECIMAL(4, 2)) AS home_ppg,
           CAST(1.0 * SUM(CASE WHEN tm.is_home = 0 THEN tm.points END) / SUM(CASE WHEN tm.is_home = 0 THEN 1 END) AS DECIMAL(4, 2)) AS away_ppg
    FROM dw.fact_team_match AS tm
    INNER JOIN dw.dim_team   AS t ON t.team_key   = tm.team_key
    INNER JOIN dw.dim_league AS l ON l.league_key = tm.league_key
    WHERE tm.season_key = 2024
    GROUP BY t.team_name, l.league_name
)
SELECT TOP (10) team_name, league_name, home_ppg, away_ppg, home_ppg - away_ppg AS home_boost
FROM split
ORDER BY home_boost DESC;
GO
