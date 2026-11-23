/* =============================================================================
   01_load_bronze.sql
   Bronze layer: each file loaded as delivered. Every column is text, so a
   bad value can never stop the load; problems are found and handled in
   silver, where they can be counted and explained.

   The folder comes from the SQLCMD variable DataPath set in run_all.sql.
   SQL Server reads the files with its own service account, so that account
   needs read access to the folder.
============================================================================= */

USE NbaPlayerImpact;
GO

DROP TABLE IF EXISTS bronze.raptor_player_seasons;
CREATE TABLE bronze.raptor_player_seasons (
    player_name                  NVARCHAR(200) NULL,
    player_id                    NVARCHAR(200) NULL,
    season                       NVARCHAR(200) NULL,
    poss                         NVARCHAR(200) NULL,
    mp                           NVARCHAR(200) NULL,
    raptor_box_offense           NVARCHAR(200) NULL,
    raptor_box_defense           NVARCHAR(200) NULL,
    raptor_box_total             NVARCHAR(200) NULL,
    raptor_onoff_offense         NVARCHAR(200) NULL,
    raptor_onoff_defense         NVARCHAR(200) NULL,
    raptor_onoff_total           NVARCHAR(200) NULL,
    raptor_offense               NVARCHAR(200) NULL,
    raptor_defense               NVARCHAR(200) NULL,
    raptor_total                 NVARCHAR(200) NULL,
    war_total                    NVARCHAR(200) NULL,
    war_reg_season               NVARCHAR(200) NULL,
    war_playoffs                 NVARCHAR(200) NULL,
    predator_offense             NVARCHAR(200) NULL,
    predator_defense             NVARCHAR(200) NULL,
    predator_total               NVARCHAR(200) NULL,
    pace_impact                  NVARCHAR(200) NULL
);

BULK INSERT bronze.raptor_player_seasons
FROM '$(DataPath)\raptor_player_seasons.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'raptor_player_seasons', COUNT(*) FROM bronze.raptor_player_seasons;
GO
