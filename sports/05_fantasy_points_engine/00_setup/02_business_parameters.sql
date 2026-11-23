/* =============================================================================
   02_business_parameters.sql
   The scoring rules live in a table, not in code. Each rule set is a full
   version of the game's rules, so a rule change is a new set of rows and
   the engine runs unchanged.

   ops.scoring_rule
     event          what the player did (goal, assist, saves ...)
     position       GK / DEF / MID / FWD, or ALL
     points         points per unit
     unit_size      how many of the event make one unit (3 saves = 1 point)
     min_minutes    the rule only applies if the player played this long
============================================================================= */

USE FantasyPoints;
GO

DROP TABLE IF EXISTS ops.business_parameter;
CREATE TABLE ops.business_parameter (
    param_name    VARCHAR(50)     NOT NULL PRIMARY KEY,
    param_value   DECIMAL(10, 4)  NOT NULL,
    description   VARCHAR(200)    NOT NULL
);

INSERT INTO ops.business_parameter (param_name, param_value, description) VALUES
    ('official_rule_set',  1,  'Rule set that should reproduce the published points exactly'),
    ('scenario_rule_set',  2,  'Rule set used for the what-if comparison'),
    ('form_window',        4,  'Number of previous matches averaged for the form forecast'),
    ('min_matches_value',  10, 'Matches a player needs before appearing in the value ranking');

DROP TABLE IF EXISTS ops.scoring_rule;
CREATE TABLE ops.scoring_rule (
    rule_set      INT           NOT NULL,
    rule_set_name VARCHAR(60)   NOT NULL,
    event         VARCHAR(30)   NOT NULL,
    position      VARCHAR(3)    NOT NULL,
    points        INT           NOT NULL,
    unit_size     INT           NOT NULL,
    min_minutes   INT           NOT NULL,
    PRIMARY KEY (rule_set, event, position)
);

INSERT INTO ops.scoring_rule VALUES
    -- rule set 1: the 2023-24 game
    (1, '2023-24 rules', 'appearance',        'ALL', 1,  1, 1),
    (1, '2023-24 rules', 'played_60',         'ALL', 1,  1, 60),
    (1, '2023-24 rules', 'goal',              'GK',  6,  1, 0),
    (1, '2023-24 rules', 'goal',              'DEF', 6,  1, 0),
    (1, '2023-24 rules', 'goal',              'MID', 5,  1, 0),
    (1, '2023-24 rules', 'goal',              'FWD', 4,  1, 0),
    (1, '2023-24 rules', 'assist',            'ALL', 3,  1, 0),
    (1, '2023-24 rules', 'clean_sheet',       'GK',  4,  1, 60),
    (1, '2023-24 rules', 'clean_sheet',       'DEF', 4,  1, 60),
    (1, '2023-24 rules', 'clean_sheet',       'MID', 1,  1, 60),
    (1, '2023-24 rules', 'saves',             'GK',  1,  3, 0),
    (1, '2023-24 rules', 'penalty_saved',     'ALL', 5,  1, 0),
    (1, '2023-24 rules', 'penalty_missed',    'ALL', -2, 1, 0),
    (1, '2023-24 rules', 'goals_conceded',    'GK',  -1, 2, 0),
    (1, '2023-24 rules', 'goals_conceded',    'DEF', -1, 2, 0),
    (1, '2023-24 rules', 'yellow_card',       'ALL', -1, 1, 0),
    (1, '2023-24 rules', 'red_card',          'ALL', -3, 1, 0),
    (1, '2023-24 rules', 'own_goal',          'ALL', -2, 1, 0),
    (1, '2023-24 rules', 'bonus',             'ALL', 1,  1, 0),
    -- rule set 2: what if goalkeeper goals were worth 10 and every 2 saves scored?
    (2, 'What-if: keeper-friendly', 'appearance',     'ALL', 1,  1, 1),
    (2, 'What-if: keeper-friendly', 'played_60',      'ALL', 1,  1, 60),
    (2, 'What-if: keeper-friendly', 'goal',           'GK',  10, 1, 0),
    (2, 'What-if: keeper-friendly', 'goal',           'DEF', 6,  1, 0),
    (2, 'What-if: keeper-friendly', 'goal',           'MID', 5,  1, 0),
    (2, 'What-if: keeper-friendly', 'goal',           'FWD', 4,  1, 0),
    (2, 'What-if: keeper-friendly', 'assist',         'ALL', 3,  1, 0),
    (2, 'What-if: keeper-friendly', 'clean_sheet',    'GK',  4,  1, 60),
    (2, 'What-if: keeper-friendly', 'clean_sheet',    'DEF', 4,  1, 60),
    (2, 'What-if: keeper-friendly', 'clean_sheet',    'MID', 1,  1, 60),
    (2, 'What-if: keeper-friendly', 'saves',          'GK',  1,  2, 0),
    (2, 'What-if: keeper-friendly', 'penalty_saved',  'ALL', 5,  1, 0),
    (2, 'What-if: keeper-friendly', 'penalty_missed', 'ALL', -2, 1, 0),
    (2, 'What-if: keeper-friendly', 'goals_conceded', 'GK',  -1, 2, 0),
    (2, 'What-if: keeper-friendly', 'goals_conceded', 'DEF', -1, 2, 0),
    (2, 'What-if: keeper-friendly', 'yellow_card',    'ALL', -1, 1, 0),
    (2, 'What-if: keeper-friendly', 'red_card',       'ALL', -3, 1, 0),
    (2, 'What-if: keeper-friendly', 'own_goal',       'ALL', -2, 1, 0),
    (2, 'What-if: keeper-friendly', 'bonus',          'ALL', 1,  1, 0);
GO
