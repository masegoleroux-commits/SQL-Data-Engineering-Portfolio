/* =============================================================================
   04_training_dataset_view.sql
   ml.v_training_dataset: one row per match, everything known before kick-off
   for both teams, plus the result as the label.

   This is the hand-over point to a data scientist. Export it to CSV (right
   click the results grid in SSMS > Save Results As) or read it from Python
   / Power BI / Azure ML, and train any model on the train split, check it on
   the test split. All the cleaning, joining and leakage-safe feature work is
   already done in SQL.
============================================================================= */

USE EuroLeagues;
GO

CREATE OR ALTER VIEW ml.v_training_dataset
AS
SELECT
    f.match_key,
    l.league_code,
    s.season_label,
    p.data_split,
    d.full_date                                   AS match_date,
    th.team_name                                  AS home_team,
    ta.team_name                                  AS away_team,
    -- strength
    CAST(e.home_elo_before AS DECIMAL(7, 1))      AS home_elo,
    CAST(e.away_elo_before AS DECIMAL(7, 1))      AS away_elo,
    CAST(e.home_elo_before - e.away_elo_before AS DECIMAL(7, 1)) AS elo_diff,
    -- recent form (previous matches only)
    fh.form_matches                               AS home_form_matches,
    fh.form_points_avg                            AS home_form_points,
    fh.form_goals_for_avg                         AS home_form_goals_for,
    fh.form_goals_against_avg                     AS home_form_goals_against,
    fh.form_sot_for_avg                           AS home_form_shots_on_target,
    fh.rest_days                                  AS home_rest_days,
    fa.form_matches                               AS away_form_matches,
    fa.form_points_avg                            AS away_form_points,
    fa.form_goals_for_avg                         AS away_form_goals_for,
    fa.form_goals_against_avg                     AS away_form_goals_against,
    fa.form_sot_for_avg                           AS away_form_shots_on_target,
    fa.rest_days                                  AS away_rest_days,
    -- model output and label
    CAST(p.p_home AS DECIMAL(4, 3))               AS model_p_home,
    CAST(p.p_draw AS DECIMAL(4, 3))               AS model_p_draw,
    CAST(p.p_away AS DECIMAL(4, 3))               AS model_p_away,
    f.ft_result                                   AS label_result
FROM dw.fact_match AS f
INNER JOIN dw.dim_league AS l  ON l.league_key = f.league_key
INNER JOIN dw.dim_season AS s  ON s.season_key = f.season_key
INNER JOIN dw.dim_date   AS d  ON d.date_key   = f.date_key
INNER JOIN dw.dim_team   AS th ON th.team_key  = f.home_team_key
INNER JOIN dw.dim_team   AS ta ON ta.team_key  = f.away_team_key
INNER JOIN ml.elo_history         AS e  ON e.match_key = f.match_key
INNER JOIN ml.match_prediction    AS p  ON p.match_key = f.match_key
INNER JOIN ml.team_match_features AS fh ON fh.match_key = f.match_key AND fh.team_key = f.home_team_key
INNER JOIN ml.team_match_features AS fa ON fa.match_key = f.match_key AND fa.team_key = f.away_team_key;
GO

SELECT TOP (10) *
FROM ml.v_training_dataset
WHERE data_split = 'test'
ORDER BY match_date, league_code;
GO
