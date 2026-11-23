/* =============================================================================
   02_business_parameters.sql
============================================================================= */

USE MarathonResults;
GO

DROP TABLE IF EXISTS ops.business_parameter;
CREATE TABLE ops.business_parameter (
    param_name    VARCHAR(50)     NOT NULL PRIMARY KEY,
    param_value   DECIMAL(10, 4)  NOT NULL,
    description   VARCHAR(200)    NOT NULL
);

INSERT INTO ops.business_parameter (param_name, param_value, description) VALUES
    ('fastest_plausible_km_seconds', 165,  'A 5K segment faster than this per km (2:45/km) is physically implausible for this field'),
    ('anomaly_z',                    4.0,  'A segment whose relative pace is this many standard deviations from the field is flagged'),
    ('wall_slowdown_pct',            20,   'Slowing by this much from the first 30K to the last 12K counts as hitting the wall'),
    ('min_country_runners',          50,   'Countries with fewer finishers are left out of the country report');

DROP TABLE IF EXISTS ops.age_group;
CREATE TABLE ops.age_group (
    age_group   VARCHAR(10)  NOT NULL PRIMARY KEY,
    min_age     INT          NOT NULL,
    max_age     INT          NOT NULL
);

-- the age bands the Boston Athletic Association uses for qualifying times
INSERT INTO ops.age_group VALUES
    ('18-34', 18, 34), ('35-39', 35, 39), ('40-44', 40, 44), ('45-49', 45, 49),
    ('50-54', 50, 54), ('55-59', 55, 59), ('60-64', 60, 64), ('65-69', 65, 69),
    ('70-74', 70, 74), ('75-79', 75, 79), ('80+',   80, 120);

DROP TABLE IF EXISTS ops.checkpoint;
CREATE TABLE ops.checkpoint (
    checkpoint_no  INT            NOT NULL PRIMARY KEY,
    checkpoint     VARCHAR(10)    NOT NULL UNIQUE,
    km             DECIMAL(7, 4)  NOT NULL
);

INSERT INTO ops.checkpoint VALUES
    (1, '5K', 5), (2, '10K', 10), (3, '15K', 15), (4, '20K', 20), (5, 'Half', 21.0975),
    (6, '25K', 25), (7, '30K', 30), (8, '35K', 35), (9, '40K', 40), (10, 'Finish', 42.195);
GO
