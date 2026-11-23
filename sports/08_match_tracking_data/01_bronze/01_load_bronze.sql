/* =============================================================================
   01_load_bronze.sql
   Bronze layer: each file loaded as delivered. Every column is text, so a
   bad value can never stop the load; problems are found and handled in
   silver, where they can be counted and explained.

   The folder comes from the SQLCMD variable DataPath set in run_all.sql.
   SQL Server reads the files with its own service account, so that account
   needs read access to the folder.

   The tracking files have THREE header rows:
       row 1   team name over each player's pair of columns
       row 2   shirt number
       row 3   Period, Frame, Time [s], Player11, (blank), Player1, (blank) ...
   Each player has two unnamed columns (x, then y), so the files cannot be
   loaded by header name. The data rows are loaded into generic slot
   columns (slot01_x, slot01_y ...) from row 4, and rows 1 to 3 are loaded
   separately into a header table. Silver uses row 3 to work out which
   player is in which slot, so a file with a different squad still loads.

   The files are the provider's 25-frames-per-second data reduced to every
   5th frame (5 per second) to keep the repository small.
============================================================================= */

USE MatchTracking;
GO

DROP TABLE IF EXISTS bronze.tracking_home_header;
CREATE TABLE bronze.tracking_home_header (
    period         VARCHAR(20) NULL,
    frame          VARCHAR(20) NULL,
    time_s         VARCHAR(20) NULL,
    slot01_x       VARCHAR(20) NULL,
    slot01_y       VARCHAR(20) NULL,
    slot02_x       VARCHAR(20) NULL,
    slot02_y       VARCHAR(20) NULL,
    slot03_x       VARCHAR(20) NULL,
    slot03_y       VARCHAR(20) NULL,
    slot04_x       VARCHAR(20) NULL,
    slot04_y       VARCHAR(20) NULL,
    slot05_x       VARCHAR(20) NULL,
    slot05_y       VARCHAR(20) NULL,
    slot06_x       VARCHAR(20) NULL,
    slot06_y       VARCHAR(20) NULL,
    slot07_x       VARCHAR(20) NULL,
    slot07_y       VARCHAR(20) NULL,
    slot08_x       VARCHAR(20) NULL,
    slot08_y       VARCHAR(20) NULL,
    slot09_x       VARCHAR(20) NULL,
    slot09_y       VARCHAR(20) NULL,
    slot10_x       VARCHAR(20) NULL,
    slot10_y       VARCHAR(20) NULL,
    slot11_x       VARCHAR(20) NULL,
    slot11_y       VARCHAR(20) NULL,
    slot12_x       VARCHAR(20) NULL,
    slot12_y       VARCHAR(20) NULL,
    slot13_x       VARCHAR(20) NULL,
    slot13_y       VARCHAR(20) NULL,
    slot14_x       VARCHAR(20) NULL,
    slot14_y       VARCHAR(20) NULL,
    ball_x         VARCHAR(20) NULL,
    ball_y         VARCHAR(20) NULL
);

BULK INSERT bronze.tracking_home_header
FROM '$(DataPath)\tracking_home_5hz.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 1, LASTROW = 3, ROWTERMINATOR = '0x0a', TABLOCK);

DROP TABLE IF EXISTS bronze.tracking_home;
CREATE TABLE bronze.tracking_home (
    period         VARCHAR(20) NULL,
    frame          VARCHAR(20) NULL,
    time_s         VARCHAR(20) NULL,
    slot01_x       VARCHAR(20) NULL,
    slot01_y       VARCHAR(20) NULL,
    slot02_x       VARCHAR(20) NULL,
    slot02_y       VARCHAR(20) NULL,
    slot03_x       VARCHAR(20) NULL,
    slot03_y       VARCHAR(20) NULL,
    slot04_x       VARCHAR(20) NULL,
    slot04_y       VARCHAR(20) NULL,
    slot05_x       VARCHAR(20) NULL,
    slot05_y       VARCHAR(20) NULL,
    slot06_x       VARCHAR(20) NULL,
    slot06_y       VARCHAR(20) NULL,
    slot07_x       VARCHAR(20) NULL,
    slot07_y       VARCHAR(20) NULL,
    slot08_x       VARCHAR(20) NULL,
    slot08_y       VARCHAR(20) NULL,
    slot09_x       VARCHAR(20) NULL,
    slot09_y       VARCHAR(20) NULL,
    slot10_x       VARCHAR(20) NULL,
    slot10_y       VARCHAR(20) NULL,
    slot11_x       VARCHAR(20) NULL,
    slot11_y       VARCHAR(20) NULL,
    slot12_x       VARCHAR(20) NULL,
    slot12_y       VARCHAR(20) NULL,
    slot13_x       VARCHAR(20) NULL,
    slot13_y       VARCHAR(20) NULL,
    slot14_x       VARCHAR(20) NULL,
    slot14_y       VARCHAR(20) NULL,
    ball_x         VARCHAR(20) NULL,
    ball_y         VARCHAR(20) NULL
);

BULK INSERT bronze.tracking_home
FROM '$(DataPath)\tracking_home_5hz.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 4, ROWTERMINATOR = '0x0a', TABLOCK);

DROP TABLE IF EXISTS bronze.tracking_away_header;
CREATE TABLE bronze.tracking_away_header (
    period         VARCHAR(20) NULL,
    frame          VARCHAR(20) NULL,
    time_s         VARCHAR(20) NULL,
    slot01_x       VARCHAR(20) NULL,
    slot01_y       VARCHAR(20) NULL,
    slot02_x       VARCHAR(20) NULL,
    slot02_y       VARCHAR(20) NULL,
    slot03_x       VARCHAR(20) NULL,
    slot03_y       VARCHAR(20) NULL,
    slot04_x       VARCHAR(20) NULL,
    slot04_y       VARCHAR(20) NULL,
    slot05_x       VARCHAR(20) NULL,
    slot05_y       VARCHAR(20) NULL,
    slot06_x       VARCHAR(20) NULL,
    slot06_y       VARCHAR(20) NULL,
    slot07_x       VARCHAR(20) NULL,
    slot07_y       VARCHAR(20) NULL,
    slot08_x       VARCHAR(20) NULL,
    slot08_y       VARCHAR(20) NULL,
    slot09_x       VARCHAR(20) NULL,
    slot09_y       VARCHAR(20) NULL,
    slot10_x       VARCHAR(20) NULL,
    slot10_y       VARCHAR(20) NULL,
    slot11_x       VARCHAR(20) NULL,
    slot11_y       VARCHAR(20) NULL,
    slot12_x       VARCHAR(20) NULL,
    slot12_y       VARCHAR(20) NULL,
    slot13_x       VARCHAR(20) NULL,
    slot13_y       VARCHAR(20) NULL,
    slot14_x       VARCHAR(20) NULL,
    slot14_y       VARCHAR(20) NULL,
    ball_x         VARCHAR(20) NULL,
    ball_y         VARCHAR(20) NULL
);

BULK INSERT bronze.tracking_away_header
FROM '$(DataPath)\tracking_away_5hz.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 1, LASTROW = 3, ROWTERMINATOR = '0x0a', TABLOCK);

DROP TABLE IF EXISTS bronze.tracking_away;
CREATE TABLE bronze.tracking_away (
    period         VARCHAR(20) NULL,
    frame          VARCHAR(20) NULL,
    time_s         VARCHAR(20) NULL,
    slot01_x       VARCHAR(20) NULL,
    slot01_y       VARCHAR(20) NULL,
    slot02_x       VARCHAR(20) NULL,
    slot02_y       VARCHAR(20) NULL,
    slot03_x       VARCHAR(20) NULL,
    slot03_y       VARCHAR(20) NULL,
    slot04_x       VARCHAR(20) NULL,
    slot04_y       VARCHAR(20) NULL,
    slot05_x       VARCHAR(20) NULL,
    slot05_y       VARCHAR(20) NULL,
    slot06_x       VARCHAR(20) NULL,
    slot06_y       VARCHAR(20) NULL,
    slot07_x       VARCHAR(20) NULL,
    slot07_y       VARCHAR(20) NULL,
    slot08_x       VARCHAR(20) NULL,
    slot08_y       VARCHAR(20) NULL,
    slot09_x       VARCHAR(20) NULL,
    slot09_y       VARCHAR(20) NULL,
    slot10_x       VARCHAR(20) NULL,
    slot10_y       VARCHAR(20) NULL,
    slot11_x       VARCHAR(20) NULL,
    slot11_y       VARCHAR(20) NULL,
    slot12_x       VARCHAR(20) NULL,
    slot12_y       VARCHAR(20) NULL,
    slot13_x       VARCHAR(20) NULL,
    slot13_y       VARCHAR(20) NULL,
    slot14_x       VARCHAR(20) NULL,
    slot14_y       VARCHAR(20) NULL,
    ball_x         VARCHAR(20) NULL,
    ball_y         VARCHAR(20) NULL
);

BULK INSERT bronze.tracking_away
FROM '$(DataPath)\tracking_away_5hz.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 4, ROWTERMINATOR = '0x0a', TABLOCK);

DROP TABLE IF EXISTS bronze.match_events;
CREATE TABLE bronze.match_events (
    team                         NVARCHAR(200) NULL,
    type                         NVARCHAR(200) NULL,
    subtype                      NVARCHAR(200) NULL,
    period                       NVARCHAR(200) NULL,
    start_frame                  NVARCHAR(200) NULL,
    start_time_s                 NVARCHAR(200) NULL,
    end_frame                    NVARCHAR(200) NULL,
    end_time_s                   NVARCHAR(200) NULL,
    from_player                  NVARCHAR(200) NULL,   -- "From" in the file (a reserved word)
    to_player                    NVARCHAR(200) NULL,   -- "To" in the file
    start_x                      NVARCHAR(200) NULL,
    start_y                      NVARCHAR(200) NULL,
    end_x                        NVARCHAR(200) NULL,
    end_y                        NVARCHAR(200) NULL
);

BULK INSERT bronze.match_events
FROM '$(DataPath)\match_events.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'tracking_home', COUNT(*) FROM bronze.tracking_home UNION ALL
SELECT 'bronze', 'tracking_away', COUNT(*) FROM bronze.tracking_away UNION ALL
SELECT 'bronze', 'match_events', COUNT(*) FROM bronze.match_events;
GO
