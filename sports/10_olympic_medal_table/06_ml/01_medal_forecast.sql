/* =============================================================================
   01_medal_forecast.sql
   Forecast a country's medals at the next Games of the same season from
   its medals at the previous one, plus a host bonus:

       medals = a + b x previous_medals + c x is_host

   Two inputs, so the least-squares fit needs a small system of equations.
   It is solved here by first removing the host effect (the average extra
   medals a host won over its previous Games in the training data), then
   fitting a and b on the rest with the one-variable formulas.

   Trained on Games before test_from_year, tested on later Games.
   Baseline: "same as last time".
============================================================================= */

USE OlympicMedals;
GO

DROP TABLE IF EXISTS ml.model_metric;
DROP TABLE IF EXISTS ml.prediction;
DROP TABLE IF EXISTS ml.medal_pair;
GO

/* ---- Each country's medals at consecutive Games of the same season ------- */
CREATE TABLE ml.medal_pair (
    games           VARCHAR(12)  NOT NULL,
    noc             CHAR(3)      NOT NULL,
    games_year      SMALLINT     NOT NULL,
    previous_medals INT          NOT NULL,
    medals          INT          NOT NULL,
    is_host         SMALLINT     NOT NULL,
    PRIMARY KEY (games, noc)
);

-- countries with no medals still count (zero), as long as they competed
WITH participation AS (
    SELECT DISTINCT d.games, e.noc FROM gold.fact_entry AS e INNER JOIN gold.dim_event AS d ON d.event_key = e.event_key
),
counts AS (
    SELECT p.games, p.noc, g.games_year, g.season, COALESCE(v.total, 0) AS medals,
           CASE WHEN g.host_noc = p.noc THEN 1 ELSE 0 END AS is_host,
           LAG(COALESCE(v.total, 0)) OVER (PARTITION BY p.noc, g.season ORDER BY g.games_year) AS previous_medals,
           LAG(g.games_year)         OVER (PARTITION BY p.noc, g.season ORDER BY g.games_year) AS previous_year
    FROM participation AS p
    INNER JOIN gold.dim_games AS g ON g.games = p.games
    LEFT JOIN gold.v_medal_table AS v ON v.games = p.games AND v.noc = p.noc
)
INSERT INTO ml.medal_pair
SELECT games, noc, games_year, previous_medals, medals, is_host
FROM counts
WHERE previous_medals IS NOT NULL AND games_year - previous_year = 4;
GO

/* ---- Fit on the training Games ------------------------------------------ */
CREATE TABLE ml.model_metric (
    metric_name   VARCHAR(60)    NOT NULL PRIMARY KEY,
    metric_value  DECIMAL(10, 4) NOT NULL
);

DECLARE @test_from DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'test_from_year');
DECLARE @host_bonus DECIMAL(10, 4) = (SELECT AVG(1.0 * (medals - previous_medals)) FROM ml.medal_pair
                                     WHERE is_host = 1 AND games_year < @test_from);

WITH train AS (
    SELECT 1.0 * previous_medals AS x, 1.0 * medals - is_host * @host_bonus AS y
    FROM ml.medal_pair WHERE games_year < @test_from
),
m AS (SELECT AVG(x) AS mx, AVG(y) AS my, AVG(x * y) AS mxy, AVG(x * x) AS mxx FROM train)
INSERT INTO ml.model_metric
SELECT 'slope b', (mxy - mx * my) / (mxx - mx * mx) FROM m
UNION ALL
SELECT 'intercept a', my - (mxy - mx * my) / (mxx - mx * mx) * mx FROM m
UNION ALL
SELECT 'host bonus c (medals)', @host_bonus;
GO

CREATE TABLE ml.prediction (
    games       VARCHAR(12)    NOT NULL,
    noc         CHAR(3)        NOT NULL,
    medals      INT            NOT NULL,
    previous    INT            NOT NULL,
    predicted   DECIMAL(7, 2)  NOT NULL,
    PRIMARY KEY (games, noc)
);

DECLARE @test_from DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'test_from_year');
DECLARE @a DECIMAL(10, 4) = (SELECT metric_value FROM ml.model_metric WHERE metric_name = 'intercept a');
DECLARE @b DECIMAL(10, 4) = (SELECT metric_value FROM ml.model_metric WHERE metric_name = 'slope b');
DECLARE @c DECIMAL(10, 4) = (SELECT metric_value FROM ml.model_metric WHERE metric_name = 'host bonus c (medals)');

INSERT INTO ml.prediction
SELECT games, noc, medals, previous_medals, @a + @b * previous_medals + @c * is_host
FROM ml.medal_pair
WHERE games_year >= @test_from;

INSERT INTO ml.model_metric
SELECT 'test rows (country-Games)', COUNT(*) FROM ml.prediction
UNION ALL
SELECT 'test MAE: model', AVG(ABS(medals - predicted)) FROM ml.prediction
UNION ALL
SELECT 'test MAE: same as last time', AVG(ABS(1.0 * medals - previous)) FROM ml.prediction
UNION ALL
SELECT 'test MAE: model, countries with 10+ medals', AVG(ABS(medals - predicted)) FROM ml.prediction WHERE previous >= 10
UNION ALL
SELECT 'test MAE: same as last time, countries with 10+ medals', AVG(ABS(1.0 * medals - previous)) FROM ml.prediction WHERE previous >= 10;

SELECT metric_name, metric_value FROM ml.model_metric ORDER BY metric_name;

-- the host nations in the test period, predicted against actual
SELECT p.games, p.noc, p.previous, p.predicted, p.medals
FROM ml.prediction AS p
INNER JOIN gold.dim_games AS g ON g.games = p.games AND g.host_noc = p.noc;
GO
