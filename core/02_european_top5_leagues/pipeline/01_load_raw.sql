/* =============================================================================
   01_load_raw.sql
   Stage 1: load the 15 season files into raw.match, one block per file.

   Each block lands the file in raw.match_landing, records the delivery in
   raw.load_log, copies the rows to raw.match under that load_id, and empties
   the landing table. The folder comes from the SQLCMD variable DataPath set
   in run_all.sql. The SQL Server service reads the files, so the folder
   must be one the service account can open: C:\SQL_Boulevard\ works; a
   folder inside your user profile or OneDrive usually does not.

   Each run appends a new delivery per file (new load_id). Raw is never
   updated or deleted, so earlier deliveries stay available for comparison.
   Staging always picks the latest load_id of each file.

   source_row_no is the line number in the file (header excluded), taken
   from the landing table's identity column, which TRUNCATE resets.

   ROWTERMINATOR is a bare line feed (0x0a). The files use Unix line
   endings. If Git converts them to Windows endings (CR LF), the CR ends up
   in the last column; staging strips it and counts how often it happened.
   The repository's .gitattributes keeps *.csv byte-for-byte to avoid that.
============================================================================= */

USE EuroLeagues;
GO

SET NOCOUNT ON;
TRUNCATE TABLE raw.match_landing;
GO

-- premier-league_2223.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\premier-league_2223.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'premier-league_2223.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'premier-league_2223.csv'), 'premier-league_2223.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- premier-league_2324.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\premier-league_2324.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'premier-league_2324.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'premier-league_2324.csv'), 'premier-league_2324.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- premier-league_2425.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\premier-league_2425.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'premier-league_2425.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'premier-league_2425.csv'), 'premier-league_2425.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- la-liga_2223.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\la-liga_2223.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'la-liga_2223.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'la-liga_2223.csv'), 'la-liga_2223.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- la-liga_2324.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\la-liga_2324.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'la-liga_2324.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'la-liga_2324.csv'), 'la-liga_2324.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- la-liga_2425.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\la-liga_2425.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'la-liga_2425.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'la-liga_2425.csv'), 'la-liga_2425.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- serie-a_2223.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\serie-a_2223.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'serie-a_2223.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'serie-a_2223.csv'), 'serie-a_2223.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- serie-a_2324.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\serie-a_2324.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'serie-a_2324.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'serie-a_2324.csv'), 'serie-a_2324.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- serie-a_2425.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\serie-a_2425.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'serie-a_2425.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'serie-a_2425.csv'), 'serie-a_2425.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- bundesliga_2223.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\bundesliga_2223.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'bundesliga_2223.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'bundesliga_2223.csv'), 'bundesliga_2223.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- bundesliga_2324.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\bundesliga_2324.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'bundesliga_2324.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'bundesliga_2324.csv'), 'bundesliga_2324.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- bundesliga_2425.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\bundesliga_2425.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'bundesliga_2425.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'bundesliga_2425.csv'), 'bundesliga_2425.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- ligue-1_2223.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\ligue-1_2223.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'ligue-1_2223.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'ligue-1_2223.csv'), 'ligue-1_2223.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- ligue-1_2324.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\ligue-1_2324.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'ligue-1_2324.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'ligue-1_2324.csv'), 'ligue-1_2324.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- ligue-1_2425.csv
BULK INSERT raw.v_match_landing
FROM '$(DataPath)\ligue-1_2425.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a', CODEPAGE = '65001', TABLOCK);

INSERT INTO raw.load_log (file_name, rows_loaded)
SELECT 'ligue-1_2425.csv', COUNT(*) FROM raw.match_landing;

INSERT INTO raw.match
    (load_id, file_name, source_row_no, [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR)
SELECT (SELECT MAX(load_id) FROM raw.load_log WHERE file_name = 'ligue-1_2425.csv'), 'ligue-1_2425.csv',
       source_row_no - (SELECT MIN(source_row_no) FROM raw.match_landing) + 1,
       [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee, HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;

TRUNCATE TABLE raw.match_landing;
GO

-- Expected: 15 files, 5,330 rows
SELECT file_name, rows_loaded, loaded_at
FROM raw.load_log
WHERE load_id IN (SELECT MAX(load_id) FROM raw.load_log GROUP BY file_name)
ORDER BY file_name;
GO
