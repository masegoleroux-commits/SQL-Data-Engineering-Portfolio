/* =============================================================================
   01_build_silver.sql
   silver.player_season   GRAIN: one player in one season (regular season and
                          playoffs combined, as published)

   Cleaning steps, each counted in ops.cleaning_log:
     1. Types applied; ratings kept at full precision.
     2. Seasons under min_minutes are flagged as small samples. A player who
        plays 20 minutes can post a rating of +70; that is noise, not talent.
     3. Rows with blank component ratings are quarantined (one player who
        played 4 minutes in 2020 has no box or on/off figures).
     4. Players whose name changes between seasons are found (Enes Kanter
        became Enes Freedom in 2021; P.J. Tucker is also written PJ Tucker).
        The ID is the key; the name history goes to an SCD Type 2 dimension.
============================================================================= */

USE NbaPlayerImpact;
GO

DROP TABLE IF EXISTS silver.player_season;
CREATE TABLE silver.player_season (
    player_id            VARCHAR(10)     NOT NULL,
    season               SMALLINT        NOT NULL,
    player_name          NVARCHAR(60)    NOT NULL,
    possessions          INT             NOT NULL,
    minutes              INT             NOT NULL,
    box_offense          DECIMAL(10, 4)  NOT NULL,
    box_defense          DECIMAL(10, 4)  NOT NULL,
    box_total            DECIMAL(10, 4)  NOT NULL,
    onoff_offense        DECIMAL(10, 4)  NOT NULL,
    onoff_defense        DECIMAL(10, 4)  NOT NULL,
    onoff_total          DECIMAL(10, 4)  NOT NULL,
    raptor_offense       DECIMAL(10, 4)  NOT NULL,
    raptor_defense       DECIMAL(10, 4)  NOT NULL,
    raptor_total         DECIMAL(10, 4)  NOT NULL,
    war_total            DECIMAL(10, 4)  NOT NULL,
    war_reg_season       DECIMAL(10, 4)  NOT NULL,
    war_playoffs         DECIMAL(10, 4)  NOT NULL,
    predator_total       DECIMAL(10, 4)  NOT NULL,
    pace_impact          DECIMAL(10, 4)  NOT NULL,
    is_small_sample      SMALLINT        NOT NULL,
    PRIMARY KEY (player_id, season)
);

DECLARE @min_minutes DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'min_minutes');

INSERT INTO silver.player_season
SELECT player_id, CAST(season AS SMALLINT), player_name,
       CAST(poss AS INT), CAST(mp AS INT),
       CAST(raptor_box_offense AS DECIMAL(10, 4)),
       CAST(raptor_box_defense AS DECIMAL(10, 4)),
       CAST(raptor_box_total AS DECIMAL(10, 4)),
       CAST(raptor_onoff_offense AS DECIMAL(10, 4)),
       CAST(raptor_onoff_defense AS DECIMAL(10, 4)),
       CAST(raptor_onoff_total AS DECIMAL(10, 4)),
       CAST(raptor_offense AS DECIMAL(10, 4)),
       CAST(raptor_defense AS DECIMAL(10, 4)),
       CAST(raptor_total AS DECIMAL(10, 4)),
       CAST(war_total AS DECIMAL(10, 4)),
       CAST(war_reg_season AS DECIMAL(10, 4)),
       CAST(war_playoffs AS DECIMAL(10, 4)),
       CAST(predator_total AS DECIMAL(10, 4)),
       CAST(pace_impact AS DECIMAL(10, 4)),
       CASE WHEN CAST(mp AS INT) < @min_minutes THEN 1 ELSE 0 END
FROM bronze.raptor_player_seasons
WHERE raptor_box_offense IS NOT NULL AND raptor_onoff_offense IS NOT NULL AND pace_impact IS NOT NULL;

INSERT INTO ops.quarantine (source_table, record_key, rule_code, detail)
SELECT 'raptor_player_seasons', CONCAT(player_id, '|', season), 'MISSING_COMPONENTS',
       CONCAT(player_name, ', ', mp, ' minutes')
FROM bronze.raptor_player_seasons
WHERE raptor_box_offense IS NULL OR raptor_onoff_offense IS NULL OR pace_impact IS NULL;
GO

INSERT INTO ops.cleaning_log (step_no, table_name, step_name, rows_affected)
SELECT 1, 'player_season', 'Rows typed, ratings rounded to 4 decimal places', COUNT(*) FROM silver.player_season
UNION ALL
SELECT 2, 'player_season', 'Seasons under the minutes threshold flagged as small samples', SUM(is_small_sample) FROM silver.player_season
UNION ALL
SELECT 3, 'player_season', 'Rows with blank component ratings (quarantined)',
       COUNT(*) FROM ops.quarantine WHERE rule_code = 'MISSING_COMPONENTS'
UNION ALL
SELECT 4, 'player_season', 'Players whose name changes between seasons',
       COUNT(*) FROM (SELECT player_id FROM silver.player_season
                      GROUP BY player_id HAVING COUNT(DISTINCT player_name) > 1) AS x;

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'silver', 'player_season', COUNT(*) FROM silver.player_season;
GO
