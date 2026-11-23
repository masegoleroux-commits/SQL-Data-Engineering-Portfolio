/* =============================================================================
   02_business_parameters.sql
   Numbers the analysis depends on, kept in one table so they can be changed
   without editing queries.
============================================================================= */

USE WorldCup;
GO

DROP TABLE IF EXISTS ops.business_parameter;
CREATE TABLE ops.business_parameter (
    param_name    VARCHAR(50)     NOT NULL PRIMARY KEY,
    param_value   DECIMAL(10, 2)  NOT NULL,
    description   VARCHAR(200)    NOT NULL
);

INSERT INTO ops.business_parameter (param_name, param_value, description) VALUES
    ('points_win',            3,    'Points for a win in all-time tables (applied to every era)'),
    ('points_draw',           1,    'Points for a draw'),
    ('min_matches_ranking',   10,   'Minimum World Cup matches before a team appears in rate rankings'),
    ('min_goals_scorer',      5,    'Minimum goals for the all-time scorer list'),
    ('late_goal_minute',      80,   'Goals from this minute of normal time count as late goals'),
    ('new_team_ppm',          1.00, 'Points per match assumed for a team with no earlier World Cup history'),
    ('host_advantage_ppm',    0.50, 'Points per match added to the host nation''s strength in the model'),
    ('test_from_year',        2010, 'Model: tournaments from this year onward are held back as the test set');
GO
