/* =============================================================================
   01_build_silver.sql
   silver.team                 GRAIN: one Premier League club
   silver.player_fixture       GRAIN: one player in one fixture. Double
                               gameweeks give a player two rows in one
                               gameweek, so gameweek is NOT part of the key.
   silver.player_fixture_event GRAIN: one player, one fixture, one scoring
                               event (long format, input to the engine)

   Cleaning steps, each counted in ops.cleaning_log:
     1. ISO kick-off text '2023-08-12T14:00:00Z' converted to DATETIME2.
     2. 'True' / 'False' text converted to 1 / 0.
     3. Price stored in tenths (55 = 5.5 million) converted to millions.
     4. Opponent team ID resolved to a club name.
     5. Players who changed club during the season are identified; the
        club is stored per fixture, so their history stays correct.
============================================================================= */

USE FantasyPoints;
GO

DROP TABLE IF EXISTS silver.player_fixture_event;
DROP TABLE IF EXISTS silver.player_fixture;
DROP TABLE IF EXISTS silver.team;
GO

CREATE TABLE silver.team (
    team_id     INT           NOT NULL PRIMARY KEY,
    team_name   VARCHAR(40)   NOT NULL UNIQUE,
    short_name  VARCHAR(3)    NOT NULL
);

INSERT INTO silver.team
SELECT CAST(id AS INT), name, short_name FROM bronze.fpl_teams;

CREATE TABLE silver.player_fixture (
    player_id        INT            NOT NULL,
    fixture_id       INT            NOT NULL,
    player_name      NVARCHAR(60)   NOT NULL,
    position         VARCHAR(3)     NOT NULL,
    team_name        VARCHAR(40)    NOT NULL,
    opponent_name    VARCHAR(40)    NOT NULL,
    gameweek         SMALLINT       NOT NULL,
    kickoff_utc      DATETIME2(0)   NOT NULL,
    is_home          SMALLINT       NOT NULL,
    minutes          SMALLINT       NOT NULL,
    goals_scored     SMALLINT       NOT NULL,
    assists          SMALLINT       NOT NULL,
    clean_sheets     SMALLINT       NOT NULL,
    goals_conceded   SMALLINT       NOT NULL,
    own_goals        SMALLINT       NOT NULL,
    penalties_saved  SMALLINT       NOT NULL,
    penalties_missed SMALLINT       NOT NULL,
    yellow_cards     SMALLINT       NOT NULL,
    red_cards        SMALLINT       NOT NULL,
    saves            SMALLINT       NOT NULL,
    bonus            SMALLINT       NOT NULL,
    official_points  SMALLINT       NOT NULL,
    expected_points  DECIMAL(5, 2)  NOT NULL,   -- the game's own forecast (xP)
    price_millions   DECIMAL(4, 1)  NOT NULL,
    selected_by      INT            NOT NULL,
    PRIMARY KEY (player_id, fixture_id)
);

INSERT INTO silver.player_fixture
SELECT CAST(b.element AS INT),
       CAST(b.fixture AS INT),
       b.name,
       b.position,
       b.team,
       t.team_name,
       CAST(b.gw AS SMALLINT),
       CAST(REPLACE(REPLACE(b.kickoff_time, 'T', ' '), 'Z', '') AS DATETIME2(0)),
       CASE WHEN b.was_home = 'True' THEN 1 ELSE 0 END,
       CAST(b.minutes AS SMALLINT),
       CAST(b.goals_scored AS SMALLINT),
       CAST(b.assists AS SMALLINT),
       CAST(b.clean_sheets AS SMALLINT),
       CAST(b.goals_conceded AS SMALLINT),
       CAST(b.own_goals AS SMALLINT),
       CAST(b.penalties_saved AS SMALLINT),
       CAST(b.penalties_missed AS SMALLINT),
       CAST(b.yellow_cards AS SMALLINT),
       CAST(b.red_cards AS SMALLINT),
       CAST(b.saves AS SMALLINT),
       CAST(b.bonus AS SMALLINT),
       CAST(b.total_points AS SMALLINT),
       CAST(b.xp AS DECIMAL(5, 2)),
       CAST(b.value AS DECIMAL(5, 1)) / 10,
       CAST(b.selected AS INT)
FROM bronze.fpl_player_gameweeks AS b
INNER JOIN silver.team AS t ON t.team_id = CAST(b.opponent_team AS INT);
GO

/* ---- Long format: one row per scoring event ------------------------------ */
CREATE TABLE silver.player_fixture_event (
    player_id   INT          NOT NULL,
    fixture_id  INT          NOT NULL,
    event       VARCHAR(30)  NOT NULL,
    quantity    INT          NOT NULL,
    PRIMARY KEY (player_id, fixture_id, event)
);

INSERT INTO silver.player_fixture_event
SELECT p.player_id, p.fixture_id, v.event, v.quantity
FROM silver.player_fixture AS p
CROSS APPLY (VALUES ('appearance',     CASE WHEN p.minutes > 0 THEN 1 ELSE 0 END),
                    ('played_60',      CASE WHEN p.minutes >= 60 THEN 1 ELSE 0 END),
                    ('goal',           p.goals_scored),
                    ('assist',         p.assists),
                    ('clean_sheet',    p.clean_sheets),
                    ('saves',          p.saves),
                    ('penalty_saved',  p.penalties_saved),
                    ('penalty_missed', p.penalties_missed),
                    ('goals_conceded', p.goals_conceded),
                    ('yellow_card',    p.yellow_cards),
                    ('red_card',       p.red_cards),
                    ('own_goal',       p.own_goals),
                    ('bonus',          p.bonus)) AS v (event, quantity)
WHERE v.quantity <> 0;
GO

INSERT INTO ops.cleaning_log (step_no, table_name, step_name, rows_affected)
SELECT 1, 'player_fixture', 'ISO kick-off text converted to DATETIME2', COUNT(*) FROM silver.player_fixture
UNION ALL
SELECT 2, 'player_fixture', 'True / False text converted to 1 / 0', COUNT(*) FROM silver.player_fixture
UNION ALL
SELECT 3, 'player_fixture', 'Price converted from tenths to millions', COUNT(*) FROM silver.player_fixture
UNION ALL
SELECT 4, 'player_fixture', 'Opponent team ID resolved to a club name', COUNT(*) FROM silver.player_fixture
UNION ALL
SELECT 5, 'player_fixture', 'Players who changed club during the season',
       COUNT(*) FROM (SELECT player_id FROM silver.player_fixture
                      GROUP BY player_id HAVING COUNT(DISTINCT team_name) > 1) AS x
UNION ALL
SELECT 6, 'player_fixture', 'Rows from double gameweeks (player has two fixtures in one gameweek)',
       COUNT(*) FROM silver.player_fixture AS p
       WHERE EXISTS (SELECT 1 FROM silver.player_fixture AS q
                     WHERE q.player_id = p.player_id AND q.gameweek = p.gameweek AND q.fixture_id <> p.fixture_id);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'silver', 'player_fixture',       COUNT(*) FROM silver.player_fixture UNION ALL
SELECT 'silver', 'player_fixture_event', COUNT(*) FROM silver.player_fixture_event;
GO
