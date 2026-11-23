/* =============================================================================
   04_model_insights.sql
   Stage 6: what the prediction model says, and where it was wrong.
============================================================================= */

USE EuroLeagues;
GO

-- 1. Model versus baseline on the unseen 2024/25 season
SELECT model, matches, accuracy_pct, brier_score, log_loss
FROM ml.model_evaluation
ORDER BY brier_score;

-- 2. Accuracy by league on the test season
SELECT l.league_name,
       COUNT(*)                                                                                  AS matches,
       CAST(100.0 * AVG(CASE WHEN p.predicted_result = p.actual_result THEN 1.0 ELSE 0 END) AS DECIMAL(4, 1)) AS accuracy_pct,
       CAST(100.0 * AVG(CASE WHEN p.actual_result = 'H' THEN 1.0 ELSE 0 END) AS DECIMAL(4, 1))   AS home_win_pct
FROM ml.match_prediction AS p
INNER JOIN dw.fact_match AS f ON f.match_key  = p.match_key
INNER JOIN dw.dim_league AS l ON l.league_key = f.league_key
WHERE p.data_split = 'test'
GROUP BY l.league_name
ORDER BY accuracy_pct DESC;

-- 3. Is the model honest? When it says 60%, does it happen about 60% of the time?
SELECT CAST(FLOOR(p.p_home * 10) / 10.0 AS DECIMAL(3, 1))                           AS predicted_home_win_band,
       COUNT(*)                                                                    AS matches,
       CAST(100.0 * AVG(p.p_home) AS DECIMAL(4, 1))                                AS avg_predicted_pct,
       CAST(100.0 * AVG(CASE WHEN p.actual_result = 'H' THEN 1.0 ELSE 0 END) AS DECIMAL(4, 1)) AS actual_home_win_pct
FROM ml.match_prediction AS p
WHERE p.data_split = 'test'
GROUP BY FLOOR(p.p_home * 10)
ORDER BY predicted_home_win_band;

-- 4. Biggest upsets of 2024/25: the result the model rated least likely
SELECT TOP (10)
    d.full_date, l.league_name,
    th.team_name AS home_team, f.ft_home_goals, f.ft_away_goals, ta.team_name AS away_team,
    CAST(100 * CASE p.actual_result WHEN 'H' THEN p.p_home WHEN 'D' THEN p.p_draw ELSE p.p_away END AS DECIMAL(4, 1))
        AS model_chance_of_this_result_pct
FROM ml.match_prediction AS p
INNER JOIN dw.fact_match AS f  ON f.match_key  = p.match_key
INNER JOIN dw.dim_date   AS d  ON d.date_key   = f.date_key
INNER JOIN dw.dim_league AS l  ON l.league_key = f.league_key
INNER JOIN dw.dim_team   AS th ON th.team_key  = f.home_team_key
INNER JOIN dw.dim_team   AS ta ON ta.team_key  = f.away_team_key
WHERE p.data_split = 'test'
ORDER BY model_chance_of_this_result_pct, d.full_date;

-- 5. Top three teams in each league at the end of 2024/25 by Elo rating.
--    Ratings are only comparable inside a league: the five leagues never
--    play each other in this data, so 1700 in Spain and 1700 in Italy do
--    not mean the same thing.
WITH ranked AS (
    SELECT team_name, league_name, elo_rating,
           ROW_NUMBER() OVER (PARTITION BY league_name ORDER BY elo_rating DESC) AS league_rank
    FROM ml.team_rating_current
)
SELECT league_name, league_rank, team_name, elo_rating
FROM ranked
WHERE league_rank <= 3
ORDER BY league_name, league_rank;
GO
