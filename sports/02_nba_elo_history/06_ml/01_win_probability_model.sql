/* =============================================================================
   01_win_probability_model.sql
   Learns how much playing at home is worth, then checks whether the
   resulting win probabilities are honest.

     p(home win) = 1 / (1 + 10 ^ (-(home_elo - away_elo + hca) / elo_scale))

   hca (home-court advantage, in Elo points) is the one thing the model
   learns. Every value from 0 to hca_search_max is scored on the training
   seasons with the Brier score (mean squared error of the probability:
   0 is perfect, 0.25 is a coin flip) and the lowest is kept. The chosen
   value is then applied, unchanged, to the held-back test seasons and
   compared with:
     - FiveThirtyEight's own published forecast for the same games
     - a baseline that gives every home team the training home-win rate

   Forfeits are left out: the score of a forfeit says nothing about strength.
============================================================================= */

USE NbaElo;
GO

DROP TABLE IF EXISTS ml.calibration;
DROP TABLE IF EXISTS ml.model_metric;
DROP TABLE IF EXISTS ml.prediction;
DROP TABLE IF EXISTS ml.hca_search;
DROP TABLE IF EXISTS ml.game_feature;
GO

/* ---- 1. Features --------------------------------------------------------- */
CREATE TABLE ml.game_feature (
    game_key          INT            NOT NULL PRIMARY KEY,
    data_split        VARCHAR(5)     NOT NULL,
    elo_diff          DECIMAL(9, 4)  NOT NULL,   -- home minus away, before the game
    is_neutral        SMALLINT       NOT NULL,
    published_prob    DECIMAL(9, 8)  NOT NULL,   -- FiveThirtyEight's forecast
    home_win          SMALLINT       NOT NULL
);

DECLARE @test_from DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'test_from_season');

INSERT INTO ml.game_feature
SELECT game_key,
       CASE WHEN season >= @test_from THEN 'test' ELSE 'train' END,
       home_elo_before - away_elo_before,
       is_neutral, home_forecast, home_win
FROM gold.fact_game
WHERE is_forfeit = 0;
GO

/* ---- 2. Train: search for the home-court advantage ----------------------- */
CREATE TABLE ml.hca_search (
    hca          INT            NOT NULL PRIMARY KEY,
    train_games  INT            NOT NULL,
    brier        DECIMAL(8, 6)  NOT NULL,
    is_chosen    SMALLINT       NOT NULL
);

DECLARE @scale DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'elo_scale');
DECLARE @max   DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'hca_search_max');
DECLARE @step  DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'hca_search_step');

WITH candidates AS (
    SELECT CAST(n * @step AS INT) AS hca
    FROM (SELECT TOP (500) ROW_NUMBER() OVER (ORDER BY object_id) - 1 AS n FROM sys.all_objects) AS nums
    WHERE n * @step <= @max
),
scored AS (
    SELECT c.hca,
           COUNT(*) AS train_games,
           AVG(SQUARE(1.0 / (1.0 + POWER(10.0, -(gf.elo_diff + c.hca * (1 - gf.is_neutral)) / @scale))
                      - gf.home_win)) AS brier
    FROM candidates AS c
    CROSS JOIN ml.game_feature AS gf
    WHERE gf.data_split = 'train'
    GROUP BY c.hca
)
INSERT INTO ml.hca_search
SELECT hca, train_games, CAST(brier AS DECIMAL(8, 6)),
       CASE WHEN ROW_NUMBER() OVER (ORDER BY brier, hca) = 1 THEN 1 ELSE 0 END
FROM scored;
GO

/* ---- 3. Predict every game with the chosen value ------------------------- */
CREATE TABLE ml.prediction (
    game_key        INT            NOT NULL PRIMARY KEY,
    data_split      VARCHAR(5)     NOT NULL,
    model_prob      DECIMAL(9, 8)  NOT NULL,
    published_prob  DECIMAL(9, 8)  NOT NULL,
    baseline_prob   DECIMAL(9, 8)  NOT NULL,
    home_win        SMALLINT       NOT NULL
);

DECLARE @scale DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'elo_scale');
DECLARE @hca   DECIMAL(10, 4) = (SELECT hca FROM ml.hca_search WHERE is_chosen = 1);
DECLARE @base  DECIMAL(10, 8) = (SELECT AVG(1.0 * home_win) FROM ml.game_feature
                                 WHERE data_split = 'train' AND is_neutral = 0);

INSERT INTO ml.prediction
SELECT game_key, data_split,
       1.0 / (1.0 + POWER(10.0, -(elo_diff + @hca * (1 - is_neutral)) / @scale)),
       published_prob,
       CASE WHEN is_neutral = 1 THEN 0.5 ELSE @base END,
       home_win
FROM ml.game_feature;
GO

/* ---- 4. Metrics on the test seasons --------------------------------------- */
CREATE TABLE ml.model_metric (
    metric_name   VARCHAR(60)    NOT NULL PRIMARY KEY,
    metric_value  DECIMAL(10, 4) NOT NULL
);

INSERT INTO ml.model_metric
SELECT 'learned home-court advantage (Elo points)', hca FROM ml.hca_search WHERE is_chosen = 1
UNION ALL
SELECT 'test games', COUNT(*) FROM ml.prediction WHERE data_split = 'test'
UNION ALL
SELECT 'test Brier: this model',
       AVG(SQUARE(model_prob - home_win)) FROM ml.prediction WHERE data_split = 'test'
UNION ALL
SELECT 'test Brier: FiveThirtyEight forecast',
       AVG(SQUARE(published_prob - home_win)) FROM ml.prediction WHERE data_split = 'test'
UNION ALL
SELECT 'test Brier: home-rate baseline',
       AVG(SQUARE(baseline_prob - home_win)) FROM ml.prediction WHERE data_split = 'test'
UNION ALL
SELECT 'test accuracy: this model',
       AVG(CASE WHEN (model_prob >= 0.5 AND home_win = 1) OR (model_prob < 0.5 AND home_win = 0)
                THEN 1.0 ELSE 0 END)
FROM ml.prediction WHERE data_split = 'test';

SELECT metric_name, metric_value FROM ml.model_metric ORDER BY metric_name;
GO

/* ---- 5. Calibration: when the model says 70%, does it happen 70%? -------- */
CREATE TABLE ml.calibration (
    bucket          INT            NOT NULL PRIMARY KEY,
    games           INT            NOT NULL,
    avg_predicted   DECIMAL(6, 4)  NOT NULL,
    actual_rate     DECIMAL(6, 4)  NOT NULL
);

DECLARE @buckets DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'calibration_buckets');

INSERT INTO ml.calibration
SELECT b.bucket, COUNT(*), AVG(b.model_prob), AVG(1.0 * b.home_win)
FROM (
    SELECT model_prob, home_win,
           CASE WHEN FLOOR(model_prob * @buckets) >= @buckets THEN @buckets - 1
                ELSE FLOOR(model_prob * @buckets) END AS bucket
    FROM ml.prediction
    WHERE data_split = 'test'
) AS b
GROUP BY b.bucket;

SELECT bucket, games, avg_predicted, actual_rate,
       CAST(actual_rate - avg_predicted AS DECIMAL(6, 4)) AS gap
FROM ml.calibration
ORDER BY bucket;
GO
