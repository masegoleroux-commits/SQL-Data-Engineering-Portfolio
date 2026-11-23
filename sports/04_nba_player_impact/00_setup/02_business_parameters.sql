/* =============================================================================
   02_business_parameters.sql
============================================================================= */

USE NbaPlayerImpact;
GO

DROP TABLE IF EXISTS ops.business_parameter;
CREATE TABLE ops.business_parameter (
    param_name    VARCHAR(50)     NOT NULL PRIMARY KEY,
    param_value   DECIMAL(10, 4)  NOT NULL,
    description   VARCHAR(200)    NOT NULL
);

INSERT INTO ops.business_parameter (param_name, param_value, description) VALUES
    ('min_minutes',        1000, 'Minutes a player needs in a season before his ratings are trusted'),
    ('sum_tolerance',      0.01, 'Allowed rounding gap when parts of a rating should add up to the total'),
    ('comparison_season',  2022, 'Season whose players get a list of similar players'),
    ('similar_players',    5,    'How many similar players to list for each player');
GO
