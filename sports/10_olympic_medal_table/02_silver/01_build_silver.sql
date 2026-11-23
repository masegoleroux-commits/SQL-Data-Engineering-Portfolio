/* =============================================================================
   01_build_silver.sql
   silver.noc            GRAIN: one National Olympic Committee code
   silver.entry          GRAIN: one athlete in one event at one Games

   Cleaning steps, each counted in ops.cleaning_log:
     1. 'NA' text in age, height, weight and medal becomes NULL.
     2. Heights outside a human range are set to NULL.
     3. Team names with a boat or crew number ('United States-2') are
        reduced to the country; the NOC code is the reliable key anyway.
     4. NOC codes missing from the region file are added from an override
        table.
     5. Historic NOCs kept as they competed: EUN (the Unified Team of
        former Soviet states in 1992) is not merged into Russia.
============================================================================= */

USE OlympicMedals;
GO

DROP TABLE IF EXISTS silver.entry;
DROP TABLE IF EXISTS silver.noc;
GO

CREATE TABLE silver.noc (
    noc          CHAR(3)        NOT NULL PRIMARY KEY,
    region       NVARCHAR(60)   NOT NULL,
    notes        NVARCHAR(100)  NULL,
    from_override SMALLINT      NOT NULL
);

INSERT INTO silver.noc
SELECT noc, COALESCE(NULLIF(region, 'NA'), notes), NULLIF(notes, ''), 0
FROM bronze.noc_regions
UNION ALL
SELECT o.noc, o.region, o.reason, 1
FROM ops.noc_region_override AS o
WHERE o.noc NOT IN (SELECT noc FROM bronze.noc_regions);
GO

CREATE TABLE silver.entry (
    athlete_id   INT            NOT NULL,
    athlete_name NVARCHAR(150)  NOT NULL,
    sex          CHAR(1)        NOT NULL,
    age          SMALLINT       NULL,
    height_cm    SMALLINT       NULL,
    weight_kg    DECIMAL(5, 1)  NULL,
    team_name    NVARCHAR(60)   NOT NULL,
    noc          CHAR(3)        NOT NULL,
    games        VARCHAR(12)    NOT NULL,
    games_year   SMALLINT       NOT NULL,
    season       VARCHAR(6)     NOT NULL,
    host_city    NVARCHAR(30)   NOT NULL,
    sport        NVARCHAR(40)   NOT NULL,
    event        NVARCHAR(100)  NOT NULL,
    medal        VARCHAR(6)     NULL,
    PRIMARY KEY (athlete_id, games, event)
);

DECLARE @max_h DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'max_height_cm');
DECLARE @min_h DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'min_height_cm');

INSERT INTO silver.entry
SELECT CAST(id AS INT), name, sex,
       CASE WHEN age = 'NA' THEN NULL ELSE CAST(age AS SMALLINT) END,
       CASE WHEN height = 'NA' THEN NULL
            WHEN CAST(height AS SMALLINT) NOT BETWEEN @min_h AND @max_h THEN NULL
            ELSE CAST(height AS SMALLINT) END,
       CASE WHEN weight = 'NA' THEN NULL ELSE CAST(weight AS DECIMAL(5, 1)) END,
       -- 'United States-2' -> 'United States'
       CASE WHEN SUBSTRING(team, LEN(team) - 1, 1) = '-' AND RIGHT(team, 1) BETWEEN '0' AND '9'
            THEN LEFT(team, LEN(team) - 2) ELSE team END,
       noc, games, CAST(year AS SMALLINT), season, city, sport, event,
       NULLIF(medal, 'NA')
FROM bronze.athlete_events_1992_2016;
GO

DECLARE @max_h DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'max_height_cm');
DECLARE @min_h DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'min_height_cm');

INSERT INTO ops.cleaning_log (step_no, table_name, step_name, rows_affected)
SELECT 1, 'entry', '''NA'' medal set to NULL (no medal)', COUNT(*) FROM silver.entry WHERE medal IS NULL
UNION ALL
SELECT 1, 'entry', '''NA'' age set to NULL', COUNT(*) FROM bronze.athlete_events_1992_2016 WHERE age = 'NA'
UNION ALL
SELECT 1, 'entry', '''NA'' height set to NULL', COUNT(*) FROM bronze.athlete_events_1992_2016 WHERE height = 'NA'
UNION ALL
SELECT 2, 'entry', 'Heights outside the human range set to NULL',
       COUNT(*) FROM bronze.athlete_events_1992_2016 WHERE height <> 'NA' AND CAST(height AS INT) NOT BETWEEN @min_h AND @max_h
UNION ALL
SELECT 3, 'entry', 'Crew numbers removed from team names (''United States-2'')',
       COUNT(*) FROM bronze.athlete_events_1992_2016
       WHERE SUBSTRING(team, LEN(team) - 1, 1) = '-' AND RIGHT(team, 1) BETWEEN '0' AND '9'
UNION ALL
SELECT 4, 'noc', 'NOC codes added from the override table', SUM(from_override) FROM silver.noc;

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'silver', 'noc',   COUNT(*) FROM silver.noc UNION ALL
SELECT 'silver', 'entry', COUNT(*) FROM silver.entry;
GO
