/* =============================================================================
   02_business_parameters.sql
============================================================================= */

USE MatchTracking;
GO

DROP TABLE IF EXISTS ops.business_parameter;
CREATE TABLE ops.business_parameter (
    param_name    VARCHAR(50)     NOT NULL PRIMARY KEY,
    param_value   DECIMAL(10, 4)  NOT NULL,
    description   VARCHAR(200)    NOT NULL
);

INSERT INTO ops.business_parameter (param_name, param_value, description) VALUES
    ('pitch_length_m',        105,  'Pitch length; tracking x runs 0 to 1 along it'),
    ('pitch_width_m',         68,   'Pitch width; tracking y runs 0 to 1 across it'),
    ('frame_step',            5,    'Frames between stored samples (25 fps source, every 5th frame kept)'),
    ('seconds_per_sample',    0.2,  'Time between stored samples'),
    ('max_human_speed',       10.5, 'Speeds above this (m/s, 37.8 km/h, faster than any recorded footballer) are tracking glitches'),
    ('high_speed_ms',         5.5,  'Running above this speed (m/s, about 20 km/h) counts as high-speed'),
    ('sprint_speed_ms',       7.0,  'Running above this speed (m/s, about 25 km/h) counts as sprinting'),
    ('min_sprint_samples',    5,    'A sprint must last at least this many samples (1 second)'),
    ('control_distance_m',    2.0,  'A player this close to the ball is treated as having it'),
    ('event_match_distance_m', 5.0, 'A passer this close to the ball at the pass frame agrees with the event');
GO
