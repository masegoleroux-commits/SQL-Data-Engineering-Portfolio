/* =============================================================================
   01_form_forecast.sql
   Can a simple form average beat the game's own forecast?

   The source includes xP, the game's expected points for each player in
   each fixture, published before kick-off. This script builds a rival
   forecast from nothing but the player's own last form_window matches
   (a rolling average, using window frames) and scores both forecasts
   against what actually happened with mean absolute error (MAE): the
   average number of points each forecast was out by.

   Only fixtures where the player already had form_window previous
   matches are scored, so both forecasts are judged on the same rows.
   Players who did not play in a fixture are left out: neither forecast
   is meant to predict team selection.
============================================================================= */

USE FantasyPoints;
GO

DROP TABLE IF EXISTS ml.forecast_metric;
DROP TABLE IF EXISTS ml.form_forecast;
GO

CREATE TABLE ml.form_forecast (
    player_id        INT            NOT NULL,
    fixture_id       INT            NOT NULL,
    actual_points    SMALLINT       NOT NULL,
    form_forecast    DECIMAL(6, 2)  NOT NULL,
    game_forecast    DECIMAL(6, 2)  NOT NULL,
    PRIMARY KEY (player_id, fixture_id)
);

DECLARE @window DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'form_window');

WITH played AS (
    SELECT player_id, fixture_id, kickoff_utc, official_points, expected_points,
           ROW_NUMBER() OVER (PARTITION BY player_id ORDER BY kickoff_utc) AS match_no
    FROM gold.fact_player_fixture
    WHERE minutes > 0
),
with_form AS (
    SELECT p.*,
           (SELECT AVG(1.0 * q.official_points) FROM played AS q
            WHERE q.player_id = p.player_id
              AND q.match_no BETWEEN p.match_no - @window AND p.match_no - 1) AS form_avg
    FROM played AS p
)
INSERT INTO ml.form_forecast
SELECT player_id, fixture_id, official_points, form_avg, expected_points
FROM with_form
WHERE match_no > @window;
GO

CREATE TABLE ml.forecast_metric (
    metric_name   VARCHAR(60)    NOT NULL PRIMARY KEY,
    metric_value  DECIMAL(10, 4) NOT NULL
);

INSERT INTO ml.forecast_metric
SELECT 'fixtures scored', COUNT(*) FROM ml.form_forecast
UNION ALL
SELECT 'MAE: rolling form average', AVG(ABS(actual_points - form_forecast)) FROM ml.form_forecast
UNION ALL
SELECT 'MAE: game forecast (xP)',   AVG(ABS(actual_points - game_forecast)) FROM ml.form_forecast
UNION ALL
SELECT 'MAE: blend of the two',     AVG(ABS(actual_points - (form_forecast + game_forecast) / 2)) FROM ml.form_forecast
UNION ALL
SELECT 'MAE: always forecast the overall average',
       AVG(ABS(actual_points - (SELECT AVG(1.0 * actual_points) FROM ml.form_forecast))) FROM ml.form_forecast;

SELECT metric_name, metric_value FROM ml.forecast_metric ORDER BY metric_value DESC;
GO
