/* =============================================================================
   01_analysis.sql
   Questions answered from the gold layer.
============================================================================= */

USE FootballLeagues;
GO

/* ---- 1. Champions and runners-up of every league and season -------------- */
SELECT l.league_name, s.season_label,
       MAX(CASE WHEN v.position = 1 THEN t.team_name END) AS champion,
       MAX(CASE WHEN v.position = 1 THEN v.points END)    AS champion_points,
       MAX(CASE WHEN v.position = 2 THEN t.team_name END) AS runner_up,
       MAX(CASE WHEN v.position = 1 THEN v.points END)
     - MAX(CASE WHEN v.position = 2 THEN v.points END)    AS title_margin,
       MAX(v.played)                                      AS most_games_played
FROM gold.v_league_table AS v
INNER JOIN gold.dim_league AS l ON l.league_key = v.league_key
INNER JOIN gold.dim_season AS s ON s.season_key = v.season_key
INNER JOIN gold.dim_team   AS t ON t.team_key   = v.team_key
GROUP BY l.league_name, s.season_label
ORDER BY l.league_name, s.season_label;
GO

/* ---- 2. Home advantage, and what happened without crowds ----------------- */
-- 2020-21 was played almost entirely behind closed doors
SELECT l.league_name,
       CAST(100.0 * SUM(CASE WHEN f.season_key <> 2020 AND f.result = 'H' THEN 1 ELSE 0 END)
            / SUM(CASE WHEN f.season_key <> 2020 THEN 1 ELSE 0 END) AS DECIMAL(5, 1)) AS home_win_pct_with_crowds,
       CAST(100.0 * SUM(CASE WHEN f.season_key = 2020 AND f.result = 'H' THEN 1 ELSE 0 END)
            / SUM(CASE WHEN f.season_key = 2020 THEN 1 ELSE 0 END) AS DECIMAL(5, 1))  AS home_win_pct_2020_21,
       CAST(100.0 * SUM(CASE WHEN f.season_key <> 2020 AND f.result = 'A' THEN 1 ELSE 0 END)
            / SUM(CASE WHEN f.season_key <> 2020 THEN 1 ELSE 0 END) AS DECIMAL(5, 1)) AS away_win_pct_with_crowds,
       CAST(100.0 * SUM(CASE WHEN f.season_key = 2020 AND f.result = 'A' THEN 1 ELSE 0 END)
            / SUM(CASE WHEN f.season_key = 2020 THEN 1 ELSE 0 END) AS DECIMAL(5, 1))  AS away_win_pct_2020_21
FROM gold.fact_match AS f
INNER JOIN gold.dim_league AS l ON l.league_key = f.league_key
WHERE f.counts_in_goals = 1
GROUP BY l.league_name
ORDER BY l.league_name;
GO

/* ---- 3. Goals per match by league and season ----------------------------- */
SELECT l.league_name, s.season_label,
       COUNT(*)                                                        AS matches,
       CAST(AVG(1.0 * (f.ft_home + f.ft_away)) AS DECIMAL(4, 2))        AS goals_per_match,
       CAST(100.0 * SUM(CASE WHEN f.ft_home + f.ft_away > 2 THEN 1 ELSE 0 END) / COUNT(*)
            AS DECIMAL(5, 1))                                          AS over_2_5_pct,
       CAST(100.0 * SUM(CASE WHEN f.ft_home > 0 AND f.ft_away > 0 THEN 1 ELSE 0 END) / COUNT(*)
            AS DECIMAL(5, 1))                                          AS both_teams_scored_pct
FROM gold.fact_match AS f
INNER JOIN gold.dim_league AS l ON l.league_key = f.league_key
INNER JOIN gold.dim_season AS s ON s.season_key = f.season_key
WHERE f.counts_in_goals = 1
GROUP BY l.league_name, s.season_label
ORDER BY l.league_name, s.season_label;
GO

/* ---- 4. Comebacks: behind at half-time, not beaten at full-time ---------- */
-- only matches with a half-time score can be used
SELECT t.team_name, l.league_name,
       COUNT(*)                                             AS times_behind_at_ht,
       SUM(CASE WHEN x.ft_for > x.ft_against THEN 1 ELSE 0 END)  AS turned_into_wins,
       SUM(CASE WHEN x.ft_for = x.ft_against THEN 1 ELSE 0 END)  AS turned_into_draws,
       CAST(100.0 * SUM(CASE WHEN x.ft_for >= x.ft_against THEN 1 ELSE 0 END) / COUNT(*)
            AS DECIMAL(5, 1))                               AS points_rescued_pct
FROM (
    SELECT home_team_key AS team_key, league_key, ht_home AS ht_for, ht_away AS ht_against,
           ft_home AS ft_for, ft_away AS ft_against
    FROM gold.fact_match WHERE counts_in_goals = 1 AND ht_home IS NOT NULL
    UNION ALL
    SELECT away_team_key, league_key, ht_away, ht_home, ft_away, ft_home
    FROM gold.fact_match WHERE counts_in_goals = 1 AND ht_home IS NOT NULL
) AS x
INNER JOIN gold.dim_team   AS t ON t.team_key   = x.team_key
INNER JOIN gold.dim_league AS l ON l.league_key = x.league_key
WHERE x.ht_for < x.ht_against
GROUP BY t.team_name, l.league_name
HAVING COUNT(*) >= 20
ORDER BY points_rescued_pct DESC;
GO

/* ---- 5. Heavy wins ------------------------------------------------------- */
DECLARE @margin DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'big_win_margin');

SELECT f.match_date, l.league_name, th.team_name AS home_team,
       CONCAT(f.ft_home, '-', f.ft_away) AS score, ta.team_name AS away_team
FROM gold.fact_match AS f
INNER JOIN gold.dim_league AS l  ON l.league_key = f.league_key
INNER JOIN gold.dim_team   AS th ON th.team_key  = f.home_team_key
INNER JOIN gold.dim_team   AS ta ON ta.team_key  = f.away_team_key
WHERE f.counts_in_goals = 1 AND ABS(f.ft_home - f.ft_away) >= @margin
ORDER BY ABS(f.ft_home - f.ft_away) DESC, f.match_date;
GO

/* ---- 6. Clubs present in all six seasons, points per game by season ------ */
SELECT t.team_name, l.league_name,
       CAST(AVG(CASE WHEN v.season_key = 2019 THEN 1.0 * v.points / v.played END) AS DECIMAL(4, 2)) AS ppg_2019_20,
       CAST(AVG(CASE WHEN v.season_key = 2020 THEN 1.0 * v.points / v.played END) AS DECIMAL(4, 2)) AS ppg_2020_21,
       CAST(AVG(CASE WHEN v.season_key = 2021 THEN 1.0 * v.points / v.played END) AS DECIMAL(4, 2)) AS ppg_2021_22,
       CAST(AVG(CASE WHEN v.season_key = 2022 THEN 1.0 * v.points / v.played END) AS DECIMAL(4, 2)) AS ppg_2022_23,
       CAST(AVG(CASE WHEN v.season_key = 2023 THEN 1.0 * v.points / v.played END) AS DECIMAL(4, 2)) AS ppg_2023_24,
       CAST(AVG(CASE WHEN v.season_key = 2024 THEN 1.0 * v.points / v.played END) AS DECIMAL(4, 2)) AS ppg_2024_25
FROM gold.v_league_table AS v
INNER JOIN gold.dim_team   AS t ON t.team_key   = v.team_key
INNER JOIN gold.dim_league AS l ON l.league_key = v.league_key
GROUP BY t.team_name, l.league_name
HAVING COUNT(*) = (SELECT COUNT(*) FROM gold.dim_season)
ORDER BY l.league_name, t.team_name;
GO
