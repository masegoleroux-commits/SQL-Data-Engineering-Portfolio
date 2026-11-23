/* =============================================================================
   01_match_outcome_model.sql
   A small, explainable model that predicts a match result (home win / draw /
   away win on the score) using only what was known BEFORE the tournament:

     strength = points per match in earlier World Cups of the same gender
                (new teams get new_team_ppm), plus host_advantage_ppm for the
                host nation
     diff     = home strength - away strength
     predict  H if diff >  band
              A if diff < -band
              D otherwise

   The one thing the model learns is the width of the draw band. Every
   candidate width from 0.00 to 1.50 is scored on the training tournaments
   (before test_from_year) and the most accurate one is kept. It is then
   applied, unchanged, to the held-back test tournaments.
============================================================================= */

USE WorldCup;
GO

DROP TABLE IF EXISTS ml.model_metric;
DROP TABLE IF EXISTS ml.prediction;
DROP TABLE IF EXISTS ml.band_search;
DROP TABLE IF EXISTS ml.match_feature;
DROP TABLE IF EXISTS ml.team_form;
GO

/* ---- 1. Pre-tournament form for every team at every tournament ----------- */
CREATE TABLE ml.team_form (
    tournament_key   INT            NOT NULL,
    team_key         INT            NOT NULL,
    prior_matches    INT            NOT NULL,
    prior_ppm        DECIMAL(6, 3)  NULL,      -- NULL = no history
    PRIMARY KEY (tournament_key, team_key)
);

DECLARE @points_win  DECIMAL(10, 2) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'points_win');
DECLARE @points_draw DECIMAL(10, 2) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'points_draw');

-- only matches from strictly earlier tournaments of the same gender count,
-- so nothing from the tournament being predicted leaks into its features
INSERT INTO ml.team_form
SELECT cur.tournament_key,
       cur.team_key,
       COUNT(hist.match_key),
       CAST(SUM(CASE hist.outcome WHEN 'W' THEN @points_win WHEN 'D' THEN @points_draw ELSE 0 END)
            / NULLIF(COUNT(hist.match_key), 0) AS DECIMAL(6, 3))
FROM (SELECT DISTINCT tournament_key, team_key FROM gold.fact_team_match) AS cur
INNER JOIN gold.dim_tournament AS tc ON tc.tournament_key = cur.tournament_key
LEFT JOIN (SELECT tm.match_key, tm.team_key, tm.outcome, t.tournament_year, t.gender
           FROM gold.fact_team_match AS tm
           INNER JOIN gold.dim_tournament AS t ON t.tournament_key = tm.tournament_key) AS hist
       ON hist.team_key = cur.team_key
      AND hist.gender   = tc.gender
      AND hist.tournament_year < tc.tournament_year
GROUP BY cur.tournament_key, cur.team_key;
GO

/* ---- 2. One feature row per match ---------------------------------------- */
CREATE TABLE ml.match_feature (
    match_key        INT            NOT NULL PRIMARY KEY,
    data_split       VARCHAR(5)     NOT NULL,   -- train / test
    home_strength    DECIMAL(6, 3)  NOT NULL,
    away_strength    DECIMAL(6, 3)  NOT NULL,
    strength_diff    DECIMAL(6, 3)  NOT NULL,
    actual_result    CHAR(1)        NOT NULL
);

DECLARE @new_team_ppm DECIMAL(10, 2) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'new_team_ppm');
DECLARE @host_bonus   DECIMAL(10, 2) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'host_advantage_ppm');
DECLARE @test_from    DECIMAL(10, 2) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'test_from_year');

INSERT INTO ml.match_feature
SELECT x.match_key, x.data_split, x.home_strength, x.away_strength,
       x.home_strength - x.away_strength, x.actual_result
FROM (
    SELECT f.match_key,
           CASE WHEN t.tournament_year >= @test_from THEN 'test' ELSE 'train' END AS data_split,
           COALESCE(fh.prior_ppm, @new_team_ppm)
             + CASE WHEN f.host_team_key = f.home_team_key THEN @host_bonus ELSE 0 END AS home_strength,
           COALESCE(fa.prior_ppm, @new_team_ppm)
             + CASE WHEN f.host_team_key = f.away_team_key THEN @host_bonus ELSE 0 END AS away_strength,
           f.regulation_result AS actual_result
    FROM gold.fact_match AS f
    INNER JOIN gold.dim_tournament AS t  ON t.tournament_key = f.tournament_key
    INNER JOIN ml.team_form        AS fh ON fh.tournament_key = f.tournament_key AND fh.team_key = f.home_team_key
    INNER JOIN ml.team_form        AS fa ON fa.tournament_key = f.tournament_key AND fa.team_key = f.away_team_key
) AS x;
GO

/* ---- 3. Train: search for the best draw band ----------------------------- */
CREATE TABLE ml.band_search (
    band          DECIMAL(4, 2)  NOT NULL PRIMARY KEY,
    train_rows    INT            NOT NULL,
    train_correct INT            NOT NULL,
    train_accuracy DECIMAL(5, 3) NOT NULL,
    is_chosen     SMALLINT       NOT NULL
);

WITH bands AS (
    SELECT CAST(n * 0.05 AS DECIMAL(4, 2)) AS band
    FROM (SELECT TOP (31) ROW_NUMBER() OVER (ORDER BY object_id) - 1 AS n
          FROM sys.all_objects) AS nums
),
scored AS (
    SELECT b.band,
           COUNT(*) AS train_rows,
           SUM(CASE WHEN mf.actual_result =
                         CASE WHEN mf.strength_diff >  b.band THEN 'H'
                              WHEN mf.strength_diff < -b.band THEN 'A'
                              ELSE 'D' END
                    THEN 1 ELSE 0 END) AS train_correct
    FROM bands AS b
    CROSS JOIN ml.match_feature AS mf
    WHERE mf.data_split = 'train'
    GROUP BY b.band
)
INSERT INTO ml.band_search
SELECT band, train_rows, train_correct,
       CAST(1.0 * train_correct / train_rows AS DECIMAL(5, 3)),
       -- ties go to the narrower band
       CASE WHEN ROW_NUMBER() OVER (ORDER BY train_correct DESC, band) = 1 THEN 1 ELSE 0 END
FROM scored;
GO

/* ---- 4. Test: apply the chosen band to the held-back tournaments --------- */
CREATE TABLE ml.prediction (
    match_key         INT       NOT NULL PRIMARY KEY,
    data_split        VARCHAR(5) NOT NULL,
    predicted_result  CHAR(1)   NOT NULL,
    actual_result     CHAR(1)   NOT NULL,
    is_correct        SMALLINT  NOT NULL
);

DECLARE @band DECIMAL(4, 2) = (SELECT band FROM ml.band_search WHERE is_chosen = 1);

INSERT INTO ml.prediction
SELECT p.match_key, p.data_split, p.predicted_result, p.actual_result,
       CASE WHEN p.predicted_result = p.actual_result THEN 1 ELSE 0 END
FROM (
    SELECT mf.match_key, mf.data_split, mf.actual_result,
           CASE WHEN mf.strength_diff >  @band THEN 'H'
                WHEN mf.strength_diff < -@band THEN 'A'
                ELSE 'D' END AS predicted_result
    FROM ml.match_feature AS mf
) AS p;
GO

/* ---- 5. Metrics, compared with a naive baseline -------------------------- */
-- baseline: always pick the listed home team, which is how most people guess
CREATE TABLE ml.model_metric (
    metric_name   VARCHAR(60)    NOT NULL PRIMARY KEY,
    metric_value  DECIMAL(8, 3)  NOT NULL
);

INSERT INTO ml.model_metric
SELECT 'chosen draw band', band FROM ml.band_search WHERE is_chosen = 1
UNION ALL
SELECT 'train accuracy', CAST(AVG(1.0 * is_correct) AS DECIMAL(8, 3)) FROM ml.prediction WHERE data_split = 'train'
UNION ALL
SELECT 'test accuracy',  CAST(AVG(1.0 * is_correct) AS DECIMAL(8, 3)) FROM ml.prediction WHERE data_split = 'test'
UNION ALL
SELECT 'test baseline accuracy (always home win)',
       CAST(AVG(CASE WHEN actual_result = 'H' THEN 1.0 ELSE 0 END) AS DECIMAL(8, 3))
FROM ml.prediction WHERE data_split = 'test'
UNION ALL
SELECT 'test matches', COUNT(*) FROM ml.prediction WHERE data_split = 'test';

SELECT metric_name, metric_value FROM ml.model_metric ORDER BY metric_name;

-- confusion matrix on the test set: rows = actual, columns = predicted
SELECT actual_result,
       SUM(CASE WHEN predicted_result = 'H' THEN 1 ELSE 0 END) AS predicted_home,
       SUM(CASE WHEN predicted_result = 'D' THEN 1 ELSE 0 END) AS predicted_draw,
       SUM(CASE WHEN predicted_result = 'A' THEN 1 ELSE 0 END) AS predicted_away
FROM ml.prediction
WHERE data_split = 'test'
GROUP BY actual_result
ORDER BY actual_result;
GO
