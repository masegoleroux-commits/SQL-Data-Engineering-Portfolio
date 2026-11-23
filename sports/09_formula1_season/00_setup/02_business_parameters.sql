/* =============================================================================
   02_business_parameters.sql
   Points systems as data: a change of rules is a change of rows.
============================================================================= */

USE Formula1;
GO

DROP TABLE IF EXISTS ops.business_parameter;
CREATE TABLE ops.business_parameter (
    param_name    VARCHAR(50)     NOT NULL PRIMARY KEY,
    param_value   DECIMAL(10, 4)  NOT NULL,
    description   VARCHAR(200)    NOT NULL
);

INSERT INTO ops.business_parameter (param_name, param_value, description) VALUES
    ('fastest_lap_bonus',      1,  'Extra point for the fastest lap in a Grand Prix'),
    ('fastest_lap_max_pos',    10, 'The fastest-lap point only counts if the driver finishes in this position or better'),
    ('model_train_last_round', 15, 'Model: rounds up to this one train the model; later rounds test it');

DROP TABLE IF EXISTS ops.points_rule;
CREATE TABLE ops.points_rule (
    session_type   VARCHAR(10)  NOT NULL,     -- race / sprint
    position       INT          NOT NULL,
    points         INT          NOT NULL,
    PRIMARY KEY (session_type, position)
);

INSERT INTO ops.points_rule VALUES
    ('race', 1, 25), ('race', 2, 18), ('race', 3, 15), ('race', 4, 12), ('race', 5, 10),
    ('race', 6, 8),  ('race', 7, 6),  ('race', 8, 4),  ('race', 9, 2),  ('race', 10, 1),
    ('sprint', 1, 8), ('sprint', 2, 7), ('sprint', 3, 6), ('sprint', 4, 5),
    ('sprint', 5, 4), ('sprint', 6, 3), ('sprint', 7, 2), ('sprint', 8, 1);

-- Results name a race by a short label; the calendar uses country and city.
-- Most labels match the country or the city. These do not, because the
-- country hosted more than one race.
DROP TABLE IF EXISTS ops.track_label_override;
CREATE TABLE ops.track_label_override (
    track_label   VARCHAR(30)  NOT NULL PRIMARY KEY,
    city          VARCHAR(30)  NOT NULL,
    reason        VARCHAR(120) NOT NULL
);

INSERT INTO ops.track_label_override VALUES
    ('Italy',         'Monza',  'Italy had two dates; Imola was cancelled, so results for Italy are Monza'),
    ('United States', 'Austin', 'Three US races; Miami and Las Vegas have their own labels');
GO
