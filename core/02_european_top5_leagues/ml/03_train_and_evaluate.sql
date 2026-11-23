/* =============================================================================
   03_train_and_evaluate.sql
   Stage 5c: turn Elo expectations into home/draw/away probabilities, then
   test them on a season the model has never seen.

   Seasons (set in cfg.business_parameter)
     burn_in_season  2022/23  ratings warm up; not used for learning
     train_season    2023/24  learn how often H / D / A happens in each band
     test_season     2024/25  held back; used only to measure accuracy

   Training ("calibration")
     The Elo expected score is split into equal-width bands (10 by default).
     For each band, count how often the home team won, drew and lost in the
     training season. Those shares ARE the model's probabilities. Adding 1 to
     each count (Laplace smoothing) stops a band with no draws from
     predicting a 0% chance of a draw.

   Evaluation on the test season
     accuracy   share of matches where the most likely outcome happened
     Brier      mean squared error of the three probabilities (lower = better,
                0 = perfect, about 0.667 = always guessing one third each)
     log loss   penalises confident wrong answers heavily (lower = better)
   Compared with two simple baselines anyone could use without a model:
     always back the home team, and the training season's average H/D/A rates.
============================================================================= */

USE EuroLeagues;
GO

SET NOCOUNT ON;

DECLARE @bins        INT      = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'calibration_bins'),
        @train       SMALLINT = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'train_season'),
        @test        SMALLINT = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'test_season');

/* ---- 1. Calibration table (the trained model) --------------------------- */
DROP TABLE IF EXISTS ml.calibration;

WITH bins AS (
    SELECT TOP (@bins) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS bin_no
    FROM sys.all_objects
),
train AS (
    SELECT CASE WHEN FLOOR(e.expected_home * @bins) > @bins - 1 THEN @bins - 1
                ELSE CAST(FLOOR(e.expected_home * @bins) AS INT) END AS bin_no,
           f.ft_result
    FROM ml.elo_history AS e
    INNER JOIN dw.fact_match AS f ON f.match_key = e.match_key
    WHERE e.season_key = @train
)
SELECT
    b.bin_no,
    CAST(1.0 * b.bin_no / @bins       AS DECIMAL(4, 2)) AS expected_from,
    CAST(1.0 * (b.bin_no + 1) / @bins AS DECIMAL(4, 2)) AS expected_to,
    COUNT(t.ft_result)                                   AS train_matches,
    SUM(CASE WHEN t.ft_result = 'H' THEN 1 ELSE 0 END)   AS home_wins,
    SUM(CASE WHEN t.ft_result = 'D' THEN 1 ELSE 0 END)   AS draws,
    SUM(CASE WHEN t.ft_result = 'A' THEN 1 ELSE 0 END)   AS away_wins,
    (SUM(CASE WHEN t.ft_result = 'H' THEN 1 ELSE 0 END) + 1.0) / (COUNT(t.ft_result) + 3.0) AS p_home,
    (SUM(CASE WHEN t.ft_result = 'D' THEN 1 ELSE 0 END) + 1.0) / (COUNT(t.ft_result) + 3.0) AS p_draw,
    (SUM(CASE WHEN t.ft_result = 'A' THEN 1 ELSE 0 END) + 1.0) / (COUNT(t.ft_result) + 3.0) AS p_away
INTO ml.calibration
FROM bins AS b
LEFT JOIN train AS t ON t.bin_no = b.bin_no
GROUP BY b.bin_no;

/* ---- 2. Predictions for every match ------------------------------------- */
DROP TABLE IF EXISTS ml.match_prediction;

SELECT
    e.match_key,
    e.season_key,
    CASE WHEN e.season_key = @test  THEN 'test'
         WHEN e.season_key = @train THEN 'train'
         ELSE 'burn-in' END                      AS data_split,
    e.expected_home,
    c.bin_no,
    c.p_home,
    c.p_draw,
    c.p_away,
    -- most likely outcome (ties go to H, then D)
    CASE WHEN c.p_home >= c.p_draw AND c.p_home >= c.p_away THEN 'H'
         WHEN c.p_draw >= c.p_away THEN 'D'
         ELSE 'A' END                            AS predicted_result,
    f.ft_result                                  AS actual_result
INTO ml.match_prediction
FROM ml.elo_history AS e
INNER JOIN dw.fact_match AS f ON f.match_key = e.match_key
INNER JOIN ml.calibration AS c
    ON c.bin_no = CASE WHEN FLOOR(e.expected_home * @bins) > @bins - 1 THEN @bins - 1
                       ELSE CAST(FLOOR(e.expected_home * @bins) AS INT) END;

ALTER TABLE ml.match_prediction ADD CONSTRAINT pk_match_prediction PRIMARY KEY (match_key);

/* ---- 3. Evaluation on the test season ----------------------------------- */
DROP TABLE IF EXISTS ml.model_evaluation;

DECLARE @base_h FLOAT, @base_d FLOAT, @base_a FLOAT;
SELECT @base_h = AVG(CASE WHEN ft_result = 'H' THEN 1.0 ELSE 0 END),
       @base_d = AVG(CASE WHEN ft_result = 'D' THEN 1.0 ELSE 0 END),
       @base_a = AVG(CASE WHEN ft_result = 'A' THEN 1.0 ELSE 0 END)
FROM dw.fact_match
WHERE season_key = @train;

WITH scored AS (
    SELECT p.*,
           -- outcome indicators
           CASE WHEN actual_result = 'H' THEN 1.0 ELSE 0 END AS o_h,
           CASE WHEN actual_result = 'D' THEN 1.0 ELSE 0 END AS o_d,
           CASE WHEN actual_result = 'A' THEN 1.0 ELSE 0 END AS o_a
    FROM ml.match_prediction AS p
    WHERE p.data_split = 'test'
)
SELECT model, matches, accuracy_pct, brier_score, log_loss
INTO ml.model_evaluation
FROM (
    SELECT 'Elo + calibration' AS model,
           COUNT(*) AS matches,
           CAST(100.0 * AVG(CASE WHEN predicted_result = actual_result THEN 1.0 ELSE 0 END) AS DECIMAL(5, 2)) AS accuracy_pct,
           CAST(AVG(SQUARE(p_home - o_h) + SQUARE(p_draw - o_d) + SQUARE(p_away - o_a)) AS DECIMAL(6, 4)) AS brier_score,
           CAST(AVG(-LOG(CASE actual_result WHEN 'H' THEN p_home WHEN 'D' THEN p_draw ELSE p_away END)) AS DECIMAL(6, 4)) AS log_loss
    FROM scored
    UNION ALL
    SELECT 'Baseline: training-season average rates',
           COUNT(*),
           -- the highest average rate is home win, so this always predicts H
           CAST(100.0 * AVG(o_h) AS DECIMAL(5, 2)),
           CAST(AVG(SQUARE(@base_h - o_h) + SQUARE(@base_d - o_d) + SQUARE(@base_a - o_a)) AS DECIMAL(6, 4)),
           CAST(AVG(-LOG(CASE actual_result WHEN 'H' THEN @base_h WHEN 'D' THEN @base_d ELSE @base_a END)) AS DECIMAL(6, 4))
    FROM scored
) AS m;
GO

SELECT bin_no, expected_from, expected_to, train_matches, home_wins, draws, away_wins,
       CAST(p_home AS DECIMAL(4, 3)) AS p_home,
       CAST(p_draw AS DECIMAL(4, 3)) AS p_draw,
       CAST(p_away AS DECIMAL(4, 3)) AS p_away
FROM ml.calibration
ORDER BY bin_no;

SELECT model, matches, accuracy_pct, brier_score, log_loss
FROM ml.model_evaluation
ORDER BY brier_score;
GO
