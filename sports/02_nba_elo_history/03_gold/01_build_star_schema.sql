/* =============================================================================
   01_build_star_schema.sql
   Gold layer.

   dim_franchise   one row per franchise (Lakers, Kings, Nets ...)
   dim_team        TYPE 2 SLOWLY CHANGING DIMENSION: one row per spell a
                   franchise spent under one team code. A franchise that
                   moves city gets a new row; the old row is closed.
   dim_season      one row per season
   fact_game       GRAIN: one game
   fact_team_game  GRAIN: one team in one game (two rows per game)

   Why Type 2: the Kings have played as ROC, CIN, KCO, KCK and SAC. A report
   on "the franchise" must join all five; a report on "Kansas City" must
   join only the right years. Both work from the same dimension.
============================================================================= */

USE NbaElo;
GO

DROP TABLE IF EXISTS gold.fact_team_game;
DROP TABLE IF EXISTS gold.fact_game;
DROP TABLE IF EXISTS gold.dim_team;
DROP TABLE IF EXISTS gold.dim_season;
DROP TABLE IF EXISTS gold.dim_franchise;
GO

/* ---- dim_franchise ----------------------------------------------------- */
CREATE TABLE gold.dim_franchise (
    franchise_key   INT          NOT NULL PRIMARY KEY,
    franchise_id    VARCHAR(20)  NOT NULL UNIQUE,
    first_season    SMALLINT     NOT NULL,
    last_season     SMALLINT     NOT NULL,
    seasons_played  SMALLINT     NOT NULL,
    team_codes_used SMALLINT     NOT NULL
);

INSERT INTO gold.dim_franchise
SELECT ROW_NUMBER() OVER (ORDER BY franchise_id),
       franchise_id, MIN(season), MAX(season), COUNT(DISTINCT season), COUNT(DISTINCT team_id)
FROM silver.team_game
GROUP BY franchise_id;

/* ---- dim_season --------------------------------------------------------- */
CREATE TABLE gold.dim_season (
    season         SMALLINT     NOT NULL PRIMARY KEY,
    season_label   VARCHAR(7)   NOT NULL,     -- 1946-47
    nba_teams      SMALLINT     NOT NULL,
    aba_teams      SMALLINT     NOT NULL
);

INSERT INTO gold.dim_season
SELECT season,
       CONCAT(season - 1, '-', RIGHT(CAST(season AS VARCHAR(4)), 2)),
       COUNT(DISTINCT CASE WHEN league = 'NBA' THEN team_id END),
       COUNT(DISTINCT CASE WHEN league = 'ABA' THEN team_id END)
FROM silver.team_game
GROUP BY season;
GO

/* ---- dim_team (SCD Type 2) ---------------------------------------------- */
CREATE TABLE gold.dim_team (
    team_key        INT          NOT NULL PRIMARY KEY,
    franchise_key   INT          NOT NULL REFERENCES gold.dim_franchise (franchise_key),
    team_code       VARCHAR(3)   NOT NULL,
    league          VARCHAR(3)   NOT NULL,
    valid_from      SMALLINT     NOT NULL,   -- first season of this spell
    valid_to        SMALLINT     NOT NULL,   -- last season of this spell
    version_no      SMALLINT     NOT NULL,   -- 1 = the franchise's first identity
    is_current      SMALLINT     NOT NULL
);

-- Gaps and islands: list each franchise's seasons in order with the code it
-- used. A new island starts whenever the code differs from the season
-- before. The New Orleans Hornets show why this matters: NOH, then NOK for
-- two seasons after Hurricane Katrina, then NOH again. Grouping by code
-- alone would merge the two NOH spells into one row covering the NOK years.
WITH franchise_season AS (
    SELECT DISTINCT franchise_id, season, team_id, league
    FROM silver.team_game
),
marked AS (
    SELECT fs.*,
           CASE WHEN LAG(team_id) OVER (PARTITION BY franchise_id ORDER BY season) = team_id
                THEN 0 ELSE 1 END AS is_new_spell
    FROM franchise_season AS fs
),
numbered AS (
    SELECT m.*,
           SUM(is_new_spell) OVER (PARTITION BY franchise_id ORDER BY season
                                   ROWS UNBOUNDED PRECEDING) AS spell_no
    FROM marked AS m
),
spells AS (
    SELECT franchise_id, spell_no, MIN(team_id) AS team_code, MIN(league) AS league,
           MIN(season) AS valid_from, MAX(season) AS valid_to
    FROM numbered
    GROUP BY franchise_id, spell_no
)
INSERT INTO gold.dim_team
SELECT ROW_NUMBER() OVER (ORDER BY s.franchise_id, s.spell_no),
       f.franchise_key, s.team_code, s.league, s.valid_from, s.valid_to,
       s.spell_no,
       CASE WHEN s.valid_to = f.last_season THEN 1 ELSE 0 END
FROM spells AS s
INNER JOIN gold.dim_franchise AS f ON f.franchise_id = s.franchise_id;
GO

/* ---- fact_game ---------------------------------------------------------- */
CREATE TABLE gold.fact_game (
    game_key         INT            NOT NULL PRIMARY KEY,
    game_id          VARCHAR(12)    NOT NULL UNIQUE,
    season           SMALLINT       NOT NULL REFERENCES gold.dim_season (season),
    game_date        DATE           NOT NULL,
    home_team_key    INT            NOT NULL REFERENCES gold.dim_team (team_key),
    away_team_key    INT            NOT NULL REFERENCES gold.dim_team (team_key),
    home_pts         SMALLINT       NOT NULL,
    away_pts         SMALLINT       NOT NULL,
    home_elo_before  DECIMAL(9, 4)  NOT NULL,
    away_elo_before  DECIMAL(9, 4)  NOT NULL,
    home_forecast    DECIMAL(9, 8)  NOT NULL,
    home_win         SMALLINT       NOT NULL,
    is_playoffs      SMALLINT       NOT NULL,
    is_neutral       SMALLINT       NOT NULL,
    is_forfeit       SMALLINT       NOT NULL,
    site_name        VARCHAR(100)   NULL
);

-- the team key is found by code AND season, which picks the right spell
INSERT INTO gold.fact_game
SELECT ROW_NUMBER() OVER (ORDER BY g.game_order, g.game_id),
       g.game_id, g.season, g.game_date, th.team_key, ta.team_key,
       g.home_pts, g.away_pts, g.home_elo_before, g.away_elo_before, g.home_forecast,
       CASE WHEN g.home_pts > g.away_pts THEN 1 ELSE 0 END,
       g.is_playoffs, g.is_neutral, g.is_forfeit, g.site_name
FROM silver.game AS g
INNER JOIN gold.dim_team AS th
        ON th.team_code = g.home_team_id AND g.season BETWEEN th.valid_from AND th.valid_to
INNER JOIN gold.dim_team AS ta
        ON ta.team_code = g.away_team_id AND g.season BETWEEN ta.valid_from AND ta.valid_to;

/* ---- fact_team_game ----------------------------------------------------- */
CREATE TABLE gold.fact_team_game (
    game_key         INT            NOT NULL REFERENCES gold.fact_game (game_key),
    team_key         INT            NOT NULL REFERENCES gold.dim_team (team_key),
    opp_team_key     INT            NOT NULL REFERENCES gold.dim_team (team_key),
    franchise_key    INT            NOT NULL REFERENCES gold.dim_franchise (franchise_key),
    season           SMALLINT       NOT NULL,
    game_date        DATE           NOT NULL,
    team_game_no     INT            NOT NULL,   -- running count of the franchise's games
    is_home          SMALLINT       NOT NULL,
    is_playoffs      SMALLINT       NOT NULL,
    pts              SMALLINT       NOT NULL,
    opp_pts          SMALLINT       NOT NULL,
    is_win           SMALLINT       NOT NULL,
    elo_before       DECIMAL(9, 4)  NOT NULL,
    elo_after        DECIMAL(9, 4)  NOT NULL,
    opp_elo_before   DECIMAL(9, 4)  NOT NULL,
    forecast         DECIMAL(9, 8)  NOT NULL,
    PRIMARY KEY (game_key, team_key)
);

INSERT INTO gold.fact_team_game
SELECT fg.game_key, t.team_key, o.team_key, t.franchise_key, tg.season, tg.game_date,
       ROW_NUMBER() OVER (PARTITION BY t.franchise_key ORDER BY tg.game_order),
       CASE WHEN tg.game_location = 'H' THEN 1 ELSE 0 END,
       tg.is_playoffs, tg.pts, tg.opp_pts,
       CASE WHEN tg.game_result = 'W' THEN 1 ELSE 0 END,
       tg.elo_before, tg.elo_after, tg.opp_elo_before, tg.forecast
FROM silver.team_game AS tg
INNER JOIN gold.fact_game AS fg ON fg.game_id = tg.game_id
INNER JOIN gold.dim_team  AS t
        ON t.team_code = tg.team_id AND tg.season BETWEEN t.valid_from AND t.valid_to
INNER JOIN gold.dim_team  AS o
        ON o.team_code = tg.opp_team_id AND tg.season BETWEEN o.valid_from AND o.valid_to;
GO

/* ---- Mart: one row per franchise per season ------------------------------ */
CREATE OR ALTER VIEW gold.v_franchise_season
AS
SELECT tg.franchise_key,
       tg.season,
       MIN(t.team_code)                                              AS team_code,
       SUM(CASE WHEN tg.is_playoffs = 0 THEN 1 ELSE 0 END)           AS games,
       SUM(CASE WHEN tg.is_playoffs = 0 THEN tg.is_win ELSE 0 END)   AS wins,
       SUM(tg.is_playoffs)                                           AS playoff_games,
       MAX(tg.elo_after)                                             AS peak_elo,
       AVG(tg.elo_after)                                             AS avg_elo
FROM gold.fact_team_game AS tg
INNER JOIN gold.dim_team AS t ON t.team_key = tg.team_key
GROUP BY tg.franchise_key, tg.season;
GO

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'gold', 'dim_franchise',  COUNT(*) FROM gold.dim_franchise UNION ALL
SELECT 'gold', 'dim_season',     COUNT(*) FROM gold.dim_season UNION ALL
SELECT 'gold', 'dim_team',       COUNT(*) FROM gold.dim_team UNION ALL
SELECT 'gold', 'fact_game',      COUNT(*) FROM gold.fact_game UNION ALL
SELECT 'gold', 'fact_team_game', COUNT(*) FROM gold.fact_team_game;
GO
