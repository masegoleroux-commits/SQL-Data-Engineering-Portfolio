/* =============================================================================
   01_load_bronze.sql
   Bronze layer: each file loaded as delivered. Every column is text, so a
   bad value can never stop the load; problems are found and handled in
   silver, where they can be counted and explained.

   The folder comes from the SQLCMD variable DataPath set in run_all.sql.
   SQL Server reads the files with its own service account, so that account
   needs read access to the folder.
============================================================================= */

USE NbaElo;
GO

DROP TABLE IF EXISTS bronze.nba_elo_games;
CREATE TABLE bronze.nba_elo_games (
    gameorder                    NVARCHAR(200) NULL,
    game_id                      NVARCHAR(200) NULL,
    lg_id                        NVARCHAR(200) NULL,
    _iscopy                      NVARCHAR(200) NULL,
    year_id                      NVARCHAR(200) NULL,
    date_game                    NVARCHAR(200) NULL,
    seasongame                   NVARCHAR(200) NULL,
    is_playoffs                  NVARCHAR(200) NULL,
    team_id                      NVARCHAR(200) NULL,
    fran_id                      NVARCHAR(200) NULL,
    pts                          NVARCHAR(200) NULL,
    elo_i                        NVARCHAR(200) NULL,
    elo_n                        NVARCHAR(200) NULL,
    win_equiv                    NVARCHAR(200) NULL,
    opp_id                       NVARCHAR(200) NULL,
    opp_fran                     NVARCHAR(200) NULL,
    opp_pts                      NVARCHAR(200) NULL,
    opp_elo_i                    NVARCHAR(200) NULL,
    opp_elo_n                    NVARCHAR(200) NULL,
    game_location                NVARCHAR(200) NULL,
    game_result                  NVARCHAR(200) NULL,
    forecast                     NVARCHAR(200) NULL,
    notes                        NVARCHAR(200) NULL
);

BULK INSERT bronze.nba_elo_games
FROM '$(DataPath)\nba_elo_games.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'nba_elo_games', COUNT(*) FROM bronze.nba_elo_games;
GO
