/* =============================================================================
   01_build_silver.sql
   Silver layer for the NBA / ABA Elo file (FiveThirtyEight, 1946-47 to 2014-15).

   The source stores every game TWICE: once from each team's side, with
   _iscopy = 1 on the mirror row. Silver keeps both shapes:

     silver.team_game  GRAIN: one team in one game  (both rows, typed)
     silver.game       GRAIN: one game              (home side, copy dropped)

   Cleaning steps, each counted in ops.cleaning_log:
     1. Dates arrive as M/D/YYYY text and are converted with style 101.
     2. The literal text 'NULL' in notes becomes a real NULL, and stray
        leading spaces are trimmed (one Seattle note arrives as
        ' Edmundson Pavillion)', cut off before it reached this file).
     3. Games whose two rows do not mirror each other are quarantined.
     4. Forfeits are flagged from the notes column.
     5. Neutral-site games are flagged and the venue is taken from the
        notes ('at Richmond VA; forfeit to VIR' -> 'Richmond VA').
     6. Mirror rows are removed for the game-level table.
============================================================================= */

USE NbaElo;
GO

DROP TABLE IF EXISTS silver.game;
DROP TABLE IF EXISTS silver.team_game;
GO

/* ---- Step 3 first: find games that do not mirror cleanly ---------------- */
-- a clean game has exactly two rows, and each row's points and Elo are the
-- other row's opponent points and opponent Elo
INSERT INTO ops.quarantine (source_table, record_key, rule_code, detail)
SELECT 'nba_elo_games', a.game_id, 'MIRROR_MISMATCH', 'rows do not mirror each other'
FROM bronze.nba_elo_games AS a
LEFT JOIN bronze.nba_elo_games AS b
       ON b.game_id = a.game_id AND b._iscopy <> a._iscopy
WHERE a._iscopy = '0'
  AND (b.game_id IS NULL
       OR a.pts     <> b.opp_pts   OR a.opp_pts   <> b.pts
       OR a.elo_i   <> b.opp_elo_i OR a.opp_elo_i <> b.elo_i
       OR a.team_id <> b.opp_id);

INSERT INTO ops.quarantine (source_table, record_key, rule_code, detail)
SELECT 'nba_elo_games', game_id, 'ROW_COUNT', CONCAT(COUNT(*), ' rows for one game')
FROM bronze.nba_elo_games
GROUP BY game_id
HAVING COUNT(*) <> 2;
GO

/* ---- silver.team_game ---------------------------------------------------- */
CREATE TABLE silver.team_game (
    game_id         VARCHAR(12)     NOT NULL,
    team_id         VARCHAR(3)      NOT NULL,
    is_copy         SMALLINT        NOT NULL,
    game_order      INT             NOT NULL,
    league          VARCHAR(3)      NOT NULL,
    season          SMALLINT        NOT NULL,   -- year the season ended
    game_date       DATE            NOT NULL,
    season_game     SMALLINT        NOT NULL,
    is_playoffs     SMALLINT        NOT NULL,
    franchise_id    VARCHAR(20)     NOT NULL,
    pts             SMALLINT        NOT NULL,
    elo_before      DECIMAL(9, 4)   NOT NULL,
    elo_after       DECIMAL(9, 4)   NOT NULL,
    win_equiv       DECIMAL(9, 4)   NOT NULL,
    opp_team_id     VARCHAR(3)      NOT NULL,
    opp_franchise_id VARCHAR(20)    NOT NULL,
    opp_pts         SMALLINT        NOT NULL,
    opp_elo_before  DECIMAL(9, 4)   NOT NULL,
    opp_elo_after   DECIMAL(9, 4)   NOT NULL,
    game_location   CHAR(1)         NOT NULL,   -- H / A / N
    game_result     CHAR(1)         NOT NULL,   -- W / L
    forecast        DECIMAL(9, 8)   NOT NULL,   -- pre-game win probability
    notes           VARCHAR(100)    NULL,
    is_forfeit      SMALLINT        NOT NULL,
    site_name       VARCHAR(100)     NULL,
    PRIMARY KEY (game_id, team_id)
);

INSERT INTO silver.team_game
SELECT b.game_id,
       b.team_id,
       CAST(b._iscopy AS SMALLINT),
       CAST(b.gameorder AS INT),
       b.lg_id,
       CAST(b.year_id AS SMALLINT),
       CONVERT(DATE, b.date_game, 101),                         -- step 1
       CAST(b.seasongame AS SMALLINT),
       CAST(b.is_playoffs AS SMALLINT),
       b.fran_id,
       CAST(b.pts AS SMALLINT),
       CAST(b.elo_i AS DECIMAL(9, 4)),
       CAST(b.elo_n AS DECIMAL(9, 4)),
       CAST(b.win_equiv AS DECIMAL(9, 4)),
       b.opp_id,
       b.opp_fran,
       CAST(b.opp_pts AS SMALLINT),
       CAST(b.opp_elo_i AS DECIMAL(9, 4)),
       CAST(b.opp_elo_n AS DECIMAL(9, 4)),
       b.game_location,
       b.game_result,
       CAST(b.forecast AS DECIMAL(9, 8)),
       CASE WHEN b.notes = 'NULL' THEN NULL ELSE TRIM(b.notes) END,  -- step 2
       CASE WHEN b.notes LIKE '%forfeit%' THEN 1 ELSE 0 END,   -- step 4
       CASE WHEN b.notes LIKE 'at %'                           -- step 5
            THEN SUBSTRING(b.notes, 4,
                     CASE WHEN CHARINDEX(';', b.notes) > 0
                          THEN CHARINDEX(';', b.notes) - 4
                          ELSE LEN(b.notes) - 3 END)
       END
FROM bronze.nba_elo_games AS b
WHERE b.game_id NOT IN (SELECT record_key FROM ops.quarantine);
GO

/* ---- silver.game: one row per game, seen from the home side ------------- */
CREATE TABLE silver.game (
    game_id          VARCHAR(12)    NOT NULL PRIMARY KEY,
    game_order       INT            NOT NULL,
    league           VARCHAR(3)     NOT NULL,
    season           SMALLINT       NOT NULL,
    game_date        DATE           NOT NULL,
    is_playoffs      SMALLINT       NOT NULL,
    is_neutral       SMALLINT       NOT NULL,
    is_forfeit       SMALLINT       NOT NULL,
    site_name        VARCHAR(100)   NULL,
    home_team_id     VARCHAR(3)     NOT NULL,   -- first-listed team at a neutral site
    away_team_id     VARCHAR(3)     NOT NULL,
    home_pts         SMALLINT       NOT NULL,
    away_pts         SMALLINT       NOT NULL,
    home_elo_before  DECIMAL(9, 4)  NOT NULL,
    away_elo_before  DECIMAL(9, 4)  NOT NULL,
    home_forecast    DECIMAL(9, 8)  NOT NULL
);

-- keep the row written from the home side; at a neutral site keep the
-- original (non-copy) row
INSERT INTO silver.game
SELECT game_id, game_order, league, season, game_date, is_playoffs,
       CASE WHEN game_location = 'N' THEN 1 ELSE 0 END,
       is_forfeit, site_name,
       team_id, opp_team_id, pts, opp_pts, elo_before, opp_elo_before, forecast
FROM silver.team_game
WHERE game_location = 'H'
   OR (game_location = 'N' AND is_copy = 0);
GO

/* ---- Cleaning log ------------------------------------------------------- */
INSERT INTO ops.cleaning_log (step_no, table_name, step_name, rows_affected)
SELECT 1, 'team_game', 'Dates converted from M/D/YYYY text', COUNT(*) FROM silver.team_game
UNION ALL
SELECT 2, 'team_game', 'Text ''NULL'' in notes replaced with a real NULL',
       COUNT(*) FROM bronze.nba_elo_games WHERE notes = 'NULL'
UNION ALL
SELECT 2, 'team_game', 'Leading spaces trimmed from notes',
       COUNT(*) FROM bronze.nba_elo_games WHERE notes LIKE ' %'
UNION ALL
SELECT 3, 'team_game', 'Games whose two rows do not mirror (quarantined)',
       COUNT(*) FROM ops.quarantine
UNION ALL
SELECT 4, 'team_game', 'Forfeit games flagged (rows)', SUM(is_forfeit) FROM silver.team_game
UNION ALL
SELECT 5, 'team_game', 'Neutral-site games flagged (rows)',
       SUM(CASE WHEN game_location = 'N' THEN 1 ELSE 0 END) FROM silver.team_game
UNION ALL
SELECT 6, 'game', 'Mirror rows removed for the one-row-per-game table',
       (SELECT COUNT(*) FROM silver.team_game) - (SELECT COUNT(*) FROM silver.game);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'silver', 'team_game', COUNT(*) FROM silver.team_game UNION ALL
SELECT 'silver', 'game',      COUNT(*) FROM silver.game;
GO
