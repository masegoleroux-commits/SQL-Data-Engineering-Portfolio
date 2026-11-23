/* =============================================================================
   02_business_parameters.sql
   Numbers the analysis and model depend on, kept in one table so they can be
   changed without editing queries.
============================================================================= */

USE NbaElo;
GO

DROP TABLE IF EXISTS ops.business_parameter;
CREATE TABLE ops.business_parameter (
    param_name    VARCHAR(50)     NOT NULL PRIMARY KEY,
    param_value   DECIMAL(10, 4)  NOT NULL,
    description   VARCHAR(200)    NOT NULL
);

INSERT INTO ops.business_parameter (param_name, param_value, description) VALUES
    ('elo_scale',            400,    'Elo points that make one team 10 times more likely to win'),
    ('upset_forecast_max',   0.20,   'A win counts as an upset when the winner''s forecast was at or below this'),
    ('min_win_streak',       15,     'Shortest winning run shown in the streak report'),
    ('elo_tolerance',        0.01,   'Allowed rounding difference when checking Elo arithmetic'),
    ('test_from_season',     2006,   'Model: seasons from this year onward are held back as the test set'),
    ('hca_search_max',       200,    'Model: largest home-court advantage (Elo points) tried in the search'),
    ('hca_search_step',      10,     'Model: step between home-court advantage values tried'),
    ('calibration_buckets',  10,     'Model: number of probability buckets in the calibration table');
GO
