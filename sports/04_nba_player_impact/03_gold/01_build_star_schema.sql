/* =============================================================================
   01_build_star_schema.sql
   dim_player           SCD TYPE 2 on the player's name: one row per name a
                        player was listed under, with the seasons it covers
   fact_player_season   GRAIN: one player in one season
   fact_player_metric   GRAIN: one player, one season, one metric (long
                        format), with z-score and percentile within the
                        season, for qualified players only
============================================================================= */

USE NbaPlayerImpact;
GO

DROP TABLE IF EXISTS gold.fact_player_metric;
DROP TABLE IF EXISTS gold.fact_player_season;
DROP TABLE IF EXISTS gold.dim_player;
GO

CREATE TABLE gold.dim_player (
    player_name_key  INT            NOT NULL PRIMARY KEY,
    player_id        VARCHAR(10)    NOT NULL,
    player_name      NVARCHAR(60)   NOT NULL,
    valid_from       SMALLINT       NOT NULL,
    valid_to         SMALLINT       NOT NULL,
    is_current       SMALLINT       NOT NULL,
    UNIQUE (player_id, valid_from)
);

-- gaps and islands on the name: a new row whenever the name differs from
-- the player's previous season
WITH marked AS (
    SELECT player_id, season, player_name,
           CASE WHEN LAG(player_name) OVER (PARTITION BY player_id ORDER BY season) = player_name
                THEN 0 ELSE 1 END AS is_new
    FROM silver.player_season
),
islands AS (
    SELECT m.*, SUM(is_new) OVER (PARTITION BY player_id ORDER BY season ROWS UNBOUNDED PRECEDING) AS island
    FROM marked AS m
),
spells AS (
    SELECT player_id, island, MIN(player_name) AS player_name, MIN(season) AS valid_from, MAX(season) AS valid_to
    FROM islands
    GROUP BY player_id, island
)
INSERT INTO gold.dim_player
SELECT ROW_NUMBER() OVER (ORDER BY player_id, valid_from),
       player_id, player_name, valid_from, valid_to,
       CASE WHEN valid_to = MAX(valid_to) OVER (PARTITION BY player_id) THEN 1 ELSE 0 END
FROM spells;

CREATE TABLE gold.fact_player_season (
    player_name_key  INT            NOT NULL REFERENCES gold.dim_player (player_name_key),
    player_id        VARCHAR(10)    NOT NULL,
    season           SMALLINT       NOT NULL,
    minutes          INT            NOT NULL,
    possessions      INT            NOT NULL,
    raptor_offense   DECIMAL(10, 4) NOT NULL,
    raptor_defense   DECIMAL(10, 4) NOT NULL,
    raptor_total     DECIMAL(10, 4) NOT NULL,
    war_total        DECIMAL(10, 4) NOT NULL,
    is_qualified     SMALLINT       NOT NULL,
    PRIMARY KEY (player_id, season)
);

INSERT INTO gold.fact_player_season
SELECT d.player_name_key, s.player_id, s.season, s.minutes, s.possessions,
       s.raptor_offense, s.raptor_defense, s.raptor_total, s.war_total,
       1 - s.is_small_sample
FROM silver.player_season AS s
INNER JOIN gold.dim_player AS d
        ON d.player_id = s.player_id AND s.season BETWEEN d.valid_from AND d.valid_to;
GO

/* ---- Long format: one row per metric, standardised within each season ---- */
CREATE TABLE gold.fact_player_metric (
    player_id     VARCHAR(10)    NOT NULL,
    season        SMALLINT       NOT NULL,
    metric        VARCHAR(20)    NOT NULL,
    metric_value  DECIMAL(10, 4) NOT NULL,
    z_score       DECIMAL(8, 3)  NOT NULL,   -- standard deviations from the season average
    percentile    DECIMAL(5, 1)  NOT NULL,   -- 0 = lowest in the season, 100 = highest
    PRIMARY KEY (player_id, season, metric)
);

-- CROSS APPLY (VALUES ...) unpivots eight columns into eight rows
WITH long_form AS (
    SELECT s.player_id, s.season, v.metric, v.metric_value
    FROM silver.player_season AS s
    CROSS APPLY (VALUES ('box_offense',   s.box_offense),
                        ('box_defense',   s.box_defense),
                        ('onoff_offense', s.onoff_offense),
                        ('onoff_defense', s.onoff_defense),
                        ('raptor_total',  s.raptor_total),
                        ('war_total',     s.war_total),
                        ('predator_total', s.predator_total),
                        ('pace_impact',   s.pace_impact)) AS v (metric, metric_value)
    WHERE s.is_small_sample = 0
)
INSERT INTO gold.fact_player_metric
SELECT player_id, season, metric, metric_value,
       (metric_value - AVG(metric_value) OVER (PARTITION BY season, metric))
         / NULLIF(STDEV(metric_value) OVER (PARTITION BY season, metric), 0),
       100 * PERCENT_RANK() OVER (PARTITION BY season, metric ORDER BY metric_value)
FROM long_form;
GO

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'gold', 'dim_player',         COUNT(*) FROM gold.dim_player UNION ALL
SELECT 'gold', 'fact_player_season', COUNT(*) FROM gold.fact_player_season UNION ALL
SELECT 'gold', 'fact_player_metric', COUNT(*) FROM gold.fact_player_metric;
GO
