/* =============================================================================
   01_build_star_schema.sql
   THE GRAIN PROBLEM: the source has one row per athlete per event. When a
   relay team of four wins, there are four gold rows. Summing medal rows
   would give that country four golds for one race. A medal table needs
   one row per medal.

   dim_games      one Games
   dim_country    one NOC with its region
   dim_event      one event at one Games, with is_team_event
   fact_entry     GRAIN: one athlete in one event at one Games
   fact_medal     GRAIN: one medal awarded (Games + event + NOC + medal)
   v_medal_table  GRAIN: one NOC at one Games
============================================================================= */

USE OlympicMedals;
GO

DROP VIEW IF EXISTS gold.v_medal_table;
DROP TABLE IF EXISTS gold.fact_medal;
DROP TABLE IF EXISTS gold.fact_entry;
DROP TABLE IF EXISTS gold.dim_event;
DROP TABLE IF EXISTS gold.dim_country;
DROP TABLE IF EXISTS gold.dim_games;
GO

CREATE TABLE gold.dim_games (
    games        VARCHAR(12)   NOT NULL PRIMARY KEY,
    games_year   SMALLINT      NOT NULL,
    season       VARCHAR(6)    NOT NULL,
    host_city    NVARCHAR(30)  NOT NULL,
    host_noc     CHAR(3)       NOT NULL,
    nations      INT           NOT NULL,
    athletes     INT           NOT NULL,
    events       INT           NOT NULL
);

INSERT INTO gold.dim_games
SELECT e.games, MIN(e.games_year), MIN(e.season), MIN(e.host_city), MIN(h.host_noc),
       COUNT(DISTINCT e.noc), COUNT(DISTINCT e.athlete_id), COUNT(DISTINCT e.event)
FROM silver.entry AS e
INNER JOIN ops.host_city AS h ON h.games = e.games
GROUP BY e.games;

CREATE TABLE gold.dim_country (
    noc      CHAR(3)       NOT NULL PRIMARY KEY,
    region   NVARCHAR(60)  NOT NULL
);

INSERT INTO gold.dim_country SELECT noc, region FROM silver.noc;

CREATE TABLE gold.dim_event (
    event_key      INT            NOT NULL PRIMARY KEY,
    games          VARCHAR(12)    NOT NULL REFERENCES gold.dim_games (games),
    sport          NVARCHAR(40)   NOT NULL,
    event          NVARCHAR(100)  NOT NULL,
    is_team_event  SMALLINT       NOT NULL,   -- some country won one medal with several athletes
    UNIQUE (games, event)
);

INSERT INTO gold.dim_event
SELECT ROW_NUMBER() OVER (ORDER BY e.games, e.event), e.games, MIN(e.sport), e.event,
       CASE WHEN EXISTS (SELECT 1 FROM silver.entry AS x
                         WHERE x.games = e.games AND x.event = e.event AND x.medal IS NOT NULL
                         GROUP BY x.noc, x.medal HAVING COUNT(*) > 1) THEN 1 ELSE 0 END
FROM silver.entry AS e
GROUP BY e.games, e.event;
GO

CREATE TABLE gold.fact_entry (
    athlete_id   INT          NOT NULL,
    event_key    INT          NOT NULL REFERENCES gold.dim_event (event_key),
    noc          CHAR(3)      NOT NULL REFERENCES gold.dim_country (noc),
    sex          CHAR(1)      NOT NULL,
    age          SMALLINT     NULL,
    height_cm    SMALLINT     NULL,
    medal        VARCHAR(6)   NULL,
    PRIMARY KEY (athlete_id, event_key)
);

INSERT INTO gold.fact_entry
SELECT e.athlete_id, d.event_key, e.noc, e.sex, e.age, e.height_cm, e.medal
FROM silver.entry AS e
INNER JOIN gold.dim_event AS d ON d.games = e.games AND d.event = e.event;

CREATE TABLE gold.fact_medal (
    event_key    INT          NOT NULL REFERENCES gold.dim_event (event_key),
    noc          CHAR(3)      NOT NULL REFERENCES gold.dim_country (noc),
    medal        VARCHAR(6)   NOT NULL,
    athletes     INT          NOT NULL,    -- team size behind this one medal
    PRIMARY KEY (event_key, noc, medal)
);

INSERT INTO gold.fact_medal
SELECT event_key, noc, medal, COUNT(*)
FROM gold.fact_entry
WHERE medal IS NOT NULL
GROUP BY event_key, noc, medal;
GO

CREATE VIEW gold.v_medal_table
AS
SELECT d.games, m.noc,
       SUM(CASE WHEN m.medal = 'Gold'   THEN 1 ELSE 0 END) AS gold,
       SUM(CASE WHEN m.medal = 'Silver' THEN 1 ELSE 0 END) AS silver,
       SUM(CASE WHEN m.medal = 'Bronze' THEN 1 ELSE 0 END) AS bronze,
       COUNT(*) AS total
FROM gold.fact_medal AS m
INNER JOIN gold.dim_event AS d ON d.event_key = m.event_key
GROUP BY d.games, m.noc;
GO

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'gold', 'dim_event',  COUNT(*) FROM gold.dim_event UNION ALL
SELECT 'gold', 'fact_entry', COUNT(*) FROM gold.fact_entry UNION ALL
SELECT 'gold', 'fact_medal', COUNT(*) FROM gold.fact_medal;
GO
