/* =============================================================================
   01_finish_from_grid.sql
   How much does the starting grid decide the result? A least-squares line,
   fitted in SQL with no libraries:

       slope     = covariance(grid, finish) / variance(grid)
       intercept = mean(finish) - slope x mean(grid)
       predicted finish = intercept + slope x grid

   Trained on the first model_train_last_round rounds, tested on the rest,
   and compared with the obvious baseline "you finish where you start".
   Only Grand Prix finishers with a grid position are used.

   R squared on the test rounds says how much of the finishing order the
   grid explains.
============================================================================= */

USE Formula1;
GO

DROP TABLE IF EXISTS ml.model_metric;
DROP TABLE IF EXISTS ml.prediction;
DROP TABLE IF EXISTS ml.line_fit;
GO

CREATE TABLE ml.line_fit (
    slope      DECIMAL(9, 5)  NOT NULL,
    intercept  DECIMAL(9, 5)  NOT NULL,
    train_rows INT            NOT NULL
);

DECLARE @last_train DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'model_train_last_round');

WITH train AS (
    SELECT 1.0 * grid_position AS x, 1.0 * finish_position AS y
    FROM gold.fact_result
    WHERE session_type = 'race' AND finish_position IS NOT NULL AND grid_position IS NOT NULL
      AND round_no <= @last_train
),
moments AS (
    SELECT AVG(x) AS mx, AVG(y) AS my, AVG(x * y) AS mxy, AVG(x * x) AS mxx, COUNT(*) AS n FROM train
)
INSERT INTO ml.line_fit
SELECT (mxy - mx * my) / (mxx - mx * mx),
       my - (mxy - mx * my) / (mxx - mx * mx) * mx,
       n
FROM moments;
GO

CREATE TABLE ml.prediction (
    round_no         INT            NOT NULL,
    driver_key       INT            NOT NULL,
    grid_position    INT            NOT NULL,
    finish_position  INT            NOT NULL,
    predicted        DECIMAL(6, 2)  NOT NULL,
    PRIMARY KEY (round_no, driver_key)
);

DECLARE @last_train DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'model_train_last_round');

INSERT INTO ml.prediction
SELECT f.round_no, f.driver_key, f.grid_position, f.finish_position,
       l.intercept + l.slope * f.grid_position
FROM gold.fact_result AS f
CROSS JOIN ml.line_fit AS l
WHERE f.session_type = 'race' AND f.finish_position IS NOT NULL AND f.grid_position IS NOT NULL
  AND f.round_no > @last_train;
GO

CREATE TABLE ml.model_metric (
    metric_name   VARCHAR(60)    NOT NULL PRIMARY KEY,
    metric_value  DECIMAL(10, 4) NOT NULL
);

INSERT INTO ml.model_metric
SELECT 'slope (places finished per grid place)', slope FROM ml.line_fit
UNION ALL
SELECT 'intercept', intercept FROM ml.line_fit
UNION ALL
SELECT 'train rows', train_rows FROM ml.line_fit
UNION ALL
SELECT 'test rows', COUNT(*) FROM ml.prediction
UNION ALL
SELECT 'test MAE: fitted line', AVG(ABS(finish_position - predicted)) FROM ml.prediction
UNION ALL
SELECT 'test MAE: finish = grid', AVG(ABS(1.0 * finish_position - grid_position)) FROM ml.prediction
UNION ALL
SELECT 'test R squared: fitted line',
       1 - SUM(SQUARE(finish_position - predicted))
         / SUM(SQUARE(finish_position - (SELECT AVG(1.0 * finish_position) FROM ml.prediction)))
FROM ml.prediction;

SELECT metric_name, metric_value FROM ml.model_metric ORDER BY metric_name;
GO
