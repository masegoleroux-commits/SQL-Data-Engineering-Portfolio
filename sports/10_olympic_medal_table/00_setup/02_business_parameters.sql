/* =============================================================================
   02_business_parameters.sql
============================================================================= */

USE OlympicMedals;
GO

DROP TABLE IF EXISTS ops.business_parameter;
CREATE TABLE ops.business_parameter (
    param_name    VARCHAR(50)     NOT NULL PRIMARY KEY,
    param_value   DECIMAL(10, 4)  NOT NULL,
    description   VARCHAR(200)    NOT NULL
);

INSERT INTO ops.business_parameter (param_name, param_value, description) VALUES
    ('min_medals_ranking',  10,   'Medals a country needs over the period to appear in efficiency rankings'),
    ('test_from_year',      2012, 'Model: Games from this year onward are the test set'),
    ('max_height_cm',       230,  'Heights above this are treated as errors'),
    ('min_height_cm',       120,  'Heights below this are treated as errors');

-- NOCs the region file does not list, found when loading
DROP TABLE IF EXISTS ops.noc_region_override;
CREATE TABLE ops.noc_region_override (
    noc       CHAR(3)       NOT NULL PRIMARY KEY,
    region    NVARCHAR(60)  NOT NULL,
    reason    VARCHAR(200)  NOT NULL
);

INSERT INTO ops.noc_region_override VALUES
    ('SGP', N'Singapore', 'Athlete file uses SGP; the region file only has the older code SIN');

-- host city -> host NOC, for the host effect
DROP TABLE IF EXISTS ops.host_city;
CREATE TABLE ops.host_city (
    games      VARCHAR(12)   NOT NULL PRIMARY KEY,
    host_noc   CHAR(3)       NOT NULL
);

INSERT INTO ops.host_city VALUES
    ('1992 Summer', 'ESP'), ('1992 Winter', 'FRA'), ('1994 Winter', 'NOR'), ('1996 Summer', 'USA'),
    ('1998 Winter', 'JPN'), ('2000 Summer', 'AUS'), ('2002 Winter', 'USA'), ('2004 Summer', 'GRE'),
    ('2006 Winter', 'ITA'), ('2008 Summer', 'CHN'), ('2010 Winter', 'CAN'), ('2012 Summer', 'GBR'),
    ('2014 Winter', 'RUS'), ('2016 Summer', 'BRA');
GO

-- medal counts as published at the time of each Games, used to check that
-- the medal table is counted at the right grain
USE OlympicMedals;
GO

DROP TABLE IF EXISTS ops.reference_medal_count;
CREATE TABLE ops.reference_medal_count (
    games   VARCHAR(12)  NOT NULL,
    noc     CHAR(3)      NOT NULL,
    gold    INT          NOT NULL,
    silver  INT          NOT NULL,
    bronze  INT          NOT NULL,
    PRIMARY KEY (games, noc)
);

INSERT INTO ops.reference_medal_count VALUES
    ('2016 Summer', 'USA', 46, 37, 38),
    ('2016 Summer', 'GBR', 27, 23, 17),
    ('2012 Summer', 'GBR', 29, 17, 19),
    ('2008 Summer', 'CHN', 51, 21, 28),
    ('2014 Winter', 'NOR', 11, 5, 10);
GO
