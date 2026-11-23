/* =============================================================================
   02_ml_tests.sql
   Checks on the features and the model.

   The leakage tests matter most: if a feature could see the result of the
   match it describes, every accuracy number in this project would be fake.
============================================================================= */

USE EuroLeagues;
GO

SET NOCOUNT ON;

DECLARE @form_window INT      = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'form_window'),
        @test        SMALLINT = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'test_season');

DROP TABLE IF EXISTS #ml_results;
CREATE TABLE #ml_results (
    test_id     INT IDENTITY(1, 1),
    area        VARCHAR(20),
    test_name   VARCHAR(120),
    failed_rows BIGINT
);

/* ---- Features ----------------------------------------------------------- */
INSERT INTO #ml_results (area, test_name, failed_rows)
SELECT 'features', 'one feature row per team per match',
       ABS((SELECT COUNT(*) FROM ml.team_match_features) - (SELECT COUNT(*) FROM dw.fact_team_match));

-- Leakage 1: a team's first match in the data must have no history at all
INSERT INTO #ml_results (area, test_name, failed_rows)
SELECT 'leakage', 'first match of each team has no form history', COUNT(*)
FROM ml.team_match_features
WHERE match_seq = 1 AND form_matches <> 0;

-- Leakage 2: recompute the form average for every row from matches strictly
-- before it and compare. Any difference means the current match leaked in.
INSERT INTO #ml_results (area, test_name, failed_rows)
SELECT 'leakage', 'form points use only earlier matches', COUNT(*)
FROM ml.team_match_features AS f
INNER JOIN dw.fact_team_match AS cur
    ON cur.match_key = f.match_key AND cur.team_key = f.team_key
OUTER APPLY (
    SELECT AVG(1.0 * p.points) AS check_avg
    FROM (SELECT TOP (@form_window) tm.points
          FROM dw.fact_team_match AS tm
          WHERE tm.team_key = f.team_key
            AND (tm.date_key < cur.date_key OR (tm.date_key = cur.date_key AND tm.match_key < cur.match_key))
          ORDER BY tm.date_key DESC, tm.match_key DESC) AS p
) AS c
WHERE ABS(COALESCE(f.form_points_avg, -1) - COALESCE(CAST(c.check_avg AS DECIMAL(5, 3)), -1)) > 0.001;

INSERT INTO #ml_results (area, test_name, failed_rows)
SELECT 'features', 'form window never exceeds the business parameter', COUNT(*)
FROM ml.team_match_features
WHERE form_matches > @form_window;

/* ---- Elo ---------------------------------------------------------------- */
INSERT INTO #ml_results (area, test_name, failed_rows)
SELECT 'elo', 'one rating row per match',
       ABS((SELECT COUNT(*) FROM ml.elo_history) - (SELECT COUNT(*) FROM dw.fact_match));

INSERT INTO #ml_results (area, test_name, failed_rows)
SELECT 'elo', 'expected score between 0 and 1', COUNT(*)
FROM ml.elo_history
WHERE expected_home <= 0 OR expected_home >= 1;

-- A team's rating before a match must equal its rating before its previous
-- match plus the change from that match (unless a new season started).
INSERT INTO #ml_results (area, test_name, failed_rows)
SELECT 'elo', 'ratings chain correctly from match to match within a season', COUNT(*)
FROM (
    SELECT tm.team_key, e.season_key,
           CASE WHEN tm.is_home = 1 THEN e.home_elo_before ELSE e.away_elo_before END AS before_rating,
           CASE WHEN tm.is_home = 1 THEN e.home_elo_before + e.rating_change
                ELSE e.away_elo_before - e.rating_change END                              AS after_rating,
           LEAD(CASE WHEN tm.is_home = 1 THEN e.home_elo_before ELSE e.away_elo_before END)
               OVER (PARTITION BY tm.team_key ORDER BY tm.date_key, tm.match_key)          AS next_before,
           LEAD(e.season_key)
               OVER (PARTITION BY tm.team_key ORDER BY tm.date_key, tm.match_key)          AS next_season
    FROM dw.fact_team_match AS tm
    INNER JOIN ml.elo_history AS e ON e.match_key = tm.match_key
) AS x
WHERE x.next_season = x.season_key
  AND ABS(x.next_before - x.after_rating) > 0.0001;

/* ---- Model -------------------------------------------------------------- */
INSERT INTO #ml_results (area, test_name, failed_rows)
SELECT 'model', 'probabilities add up to 1', COUNT(*)
FROM ml.match_prediction
WHERE ABS(p_home + p_draw + p_away - 1) > 0.0001;

INSERT INTO #ml_results (area, test_name, failed_rows)
SELECT 'model', 'calibration learned only from the training season', COUNT(*)
FROM ml.calibration
WHERE train_matches > (SELECT COUNT(*) FROM ml.match_prediction WHERE data_split = 'train');

INSERT INTO #ml_results (area, test_name, failed_rows)
SELECT 'model', 'test season is fully predicted',
       ABS((SELECT COUNT(*) FROM dw.fact_match WHERE season_key = @test)
         - (SELECT COUNT(*) FROM ml.match_prediction WHERE data_split = 'test'));

-- The model has to beat the simple baseline on unseen data, or it is not
-- worth having.
INSERT INTO #ml_results (area, test_name, failed_rows)
SELECT 'model', 'model Brier score beats the baseline on the test season',
       CASE WHEN (SELECT brier_score FROM ml.model_evaluation WHERE model = 'Elo + calibration')
               < (SELECT brier_score FROM ml.model_evaluation WHERE model LIKE 'Baseline%')
            THEN 0 ELSE 1 END;

/* ---- Results ------------------------------------------------------------ */
SELECT test_id, area, test_name, failed_rows,
       CASE WHEN failed_rows = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM #ml_results
ORDER BY test_id;

IF EXISTS (SELECT 1 FROM #ml_results WHERE failed_rows <> 0 OR failed_rows IS NULL)
    THROW 50002, 'ML tests failed. See the results grid.', 1;
GO
