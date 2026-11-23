/* =============================================================================
   01_load_bronze.sql
   Bronze layer: each file loaded as delivered. Every column is text, so a
   bad value can never stop the load; problems are found and handled in
   silver, where they can be counted and explained.

   The folder comes from the SQLCMD variable DataPath set in run_all.sql.
   SQL Server reads the files with its own service account, so that account
   needs read access to the folder.
============================================================================= */

USE TransferMarket;
GO

DROP TABLE IF EXISTS bronze.premier_league_transfers;
CREATE TABLE bronze.premier_league_transfers (
    club_name                    NVARCHAR(200) NULL,
    player_name                  NVARCHAR(200) NULL,
    age                          NVARCHAR(200) NULL,
    position                     NVARCHAR(200) NULL,
    club_involved_name           NVARCHAR(200) NULL,
    fee                          NVARCHAR(200) NULL,
    transfer_movement            NVARCHAR(200) NULL,
    transfer_period              NVARCHAR(200) NULL,
    fee_cleaned                  NVARCHAR(200) NULL,
    league_name                  NVARCHAR(200) NULL,
    year                         NVARCHAR(200) NULL,
    season                       NVARCHAR(200) NULL,
    country                      NVARCHAR(200) NULL
);

BULK INSERT bronze.premier_league_transfers
FROM '$(DataPath)\premier_league_transfers.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'premier_league_transfers', COUNT(*) FROM bronze.premier_league_transfers;
GO
