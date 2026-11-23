/* =============================================================================
   01_build_star_schema.sql
   Gold layer: star schema.

   dim_tournament   one row per tournament (men's and women's)
   dim_team         one row per national team
   dim_player       one row per player
   dim_stage        one row per stage, with its order in a tournament
   fact_match       GRAIN: one row per match
   fact_team_match  GRAIN: one row per team per match (two per match)
   fact_goal        GRAIN: one row per goal
   fact_booking     GRAIN: one row per card

   Surrogate keys are numbered with ROW_NUMBER in a fixed order, so a full
   rebuild always gives every row the same key.
============================================================================= */

USE WorldCup;
GO

DROP TABLE IF EXISTS gold.fact_booking;
DROP TABLE IF EXISTS gold.fact_goal;
DROP TABLE IF EXISTS gold.fact_team_match;
DROP TABLE IF EXISTS gold.fact_match;
DROP TABLE IF EXISTS gold.dim_stage;
DROP TABLE IF EXISTS gold.dim_player;
DROP TABLE IF EXISTS gold.dim_team;
DROP TABLE IF EXISTS gold.dim_tournament;
GO

/* ---- Dimensions -------------------------------------------------------- */
CREATE TABLE gold.dim_tournament (
    tournament_key   INT          NOT NULL PRIMARY KEY,
    tournament_id    VARCHAR(10)  NOT NULL UNIQUE,
    tournament_name  VARCHAR(60)  NOT NULL,
    tournament_year  SMALLINT     NOT NULL,
    gender           VARCHAR(5)   NOT NULL,
    host_country     VARCHAR(60)  NOT NULL,
    winner           VARCHAR(60)  NOT NULL,
    count_teams      SMALLINT     NOT NULL
);

INSERT INTO gold.dim_tournament
SELECT ROW_NUMBER() OVER (ORDER BY tournament_year, gender),
       tournament_id, tournament_name, tournament_year, gender, host_country, winner, count_teams
FROM silver.tournament;

CREATE TABLE gold.dim_team (
    team_key            INT          NOT NULL PRIMARY KEY,
    team_id             VARCHAR(10)  NOT NULL UNIQUE,
    team_name           VARCHAR(60)  NOT NULL,
    team_code           VARCHAR(5)   NOT NULL,
    confederation_code  VARCHAR(10)  NOT NULL,
    region_name         VARCHAR(40)  NOT NULL
);

INSERT INTO gold.dim_team
SELECT ROW_NUMBER() OVER (ORDER BY team_id), team_id, team_name, team_code, confederation_code, region_name
FROM silver.team;

CREATE TABLE gold.dim_player (
    player_key        INT           NOT NULL PRIMARY KEY,
    player_id         VARCHAR(10)   NOT NULL UNIQUE,
    player_name       VARCHAR(210)  NOT NULL,
    birth_date        DATE          NULL,
    gender            VARCHAR(5)    NOT NULL,
    primary_position  VARCHAR(12)   NOT NULL
);

-- 'not applicable' given names belong to players known by one name (e.g. Pele)
INSERT INTO gold.dim_player
SELECT ROW_NUMBER() OVER (ORDER BY player_id),
       player_id,
       CASE WHEN given_name = 'not applicable' THEN family_name ELSE CONCAT(given_name, ' ', family_name) END,
       birth_date,
       CASE WHEN is_female = 1 THEN 'Women' ELSE 'Men' END,
       primary_position
FROM silver.player;

CREATE TABLE gold.dim_stage (
    stage_key    INT          NOT NULL PRIMARY KEY,
    stage_name   VARCHAR(30)  NOT NULL UNIQUE,
    stage_order  SMALLINT     NOT NULL,
    is_knockout  SMALLINT     NOT NULL
);

INSERT INTO gold.dim_stage VALUES
    (1, 'group stage',        1, 0),
    (2, 'second group stage', 2, 0),
    (3, 'final round',        3, 0),
    (4, 'round of 16',        3, 1),
    (5, 'quarter-finals',     4, 1),
    (6, 'semi-finals',        5, 1),
    (7, 'third-place match',  6, 1),
    (8, 'final',              7, 1);
GO

/* ---- fact_match -------------------------------------------------------- */
CREATE TABLE gold.fact_match (
    match_key          INT          NOT NULL PRIMARY KEY,
    match_id           VARCHAR(12)  NOT NULL UNIQUE,
    tournament_key     INT          NOT NULL REFERENCES gold.dim_tournament (tournament_key),
    stage_key          INT          NOT NULL REFERENCES gold.dim_stage (stage_key),
    match_date         DATE         NOT NULL,
    home_team_key      INT          NOT NULL REFERENCES gold.dim_team (team_key),
    away_team_key      INT          NOT NULL REFERENCES gold.dim_team (team_key),
    home_score         SMALLINT     NOT NULL,
    away_score         SMALLINT     NOT NULL,
    extra_time         SMALLINT     NOT NULL,
    penalty_shootout   SMALLINT     NOT NULL,
    home_penalties     SMALLINT     NOT NULL,
    away_penalties     SMALLINT     NOT NULL,
    final_result       CHAR(1)      NOT NULL,
    regulation_result  CHAR(1)      NOT NULL,
    host_team_key      INT          NULL       -- the host nation if it played in this match
);

INSERT INTO gold.fact_match
SELECT ROW_NUMBER() OVER (ORDER BY m.match_date, m.match_id),
       m.match_id, t.tournament_key, s.stage_key, m.match_date, th.team_key, ta.team_key,
       m.home_score, m.away_score, m.extra_time, m.penalty_shootout, m.home_penalties, m.away_penalties,
       m.final_result, m.regulation_result,
       CASE WHEN th.team_name = t.host_country THEN th.team_key
            WHEN ta.team_name = t.host_country THEN ta.team_key END
FROM silver.match AS m
INNER JOIN gold.dim_tournament AS t  ON t.tournament_id = m.tournament_id
INNER JOIN gold.dim_stage      AS s  ON s.stage_name    = m.stage_name
INNER JOIN gold.dim_team       AS th ON th.team_id      = m.home_team_id
INNER JOIN gold.dim_team       AS ta ON ta.team_id      = m.away_team_id;

/* ---- fact_team_match: each match seen from both sides ------------------- */
CREATE TABLE gold.fact_team_match (
    match_key       INT       NOT NULL REFERENCES gold.fact_match (match_key),
    team_key        INT       NOT NULL REFERENCES gold.dim_team (team_key),
    opponent_key    INT       NOT NULL REFERENCES gold.dim_team (team_key),
    tournament_key  INT       NOT NULL,
    stage_key       INT       NOT NULL,
    is_host         SMALLINT  NOT NULL,
    goals_for       SMALLINT  NOT NULL,
    goals_against   SMALLINT  NOT NULL,
    outcome         CHAR(1)   NOT NULL,   -- W / D / L on the score (shootouts count as D)
    went_through    SMALLINT  NOT NULL,   -- won the match outright or on penalties
    PRIMARY KEY (match_key, team_key)
);

INSERT INTO gold.fact_team_match
SELECT f.match_key, f.home_team_key, f.away_team_key, f.tournament_key, f.stage_key,
       CASE WHEN f.host_team_key = f.home_team_key THEN 1 ELSE 0 END,
       f.home_score, f.away_score,
       CASE f.regulation_result WHEN 'H' THEN 'W' WHEN 'A' THEN 'L' ELSE 'D' END,
       CASE WHEN f.final_result = 'H' THEN 1 ELSE 0 END
FROM gold.fact_match AS f
UNION ALL
SELECT f.match_key, f.away_team_key, f.home_team_key, f.tournament_key, f.stage_key,
       CASE WHEN f.host_team_key = f.away_team_key THEN 1 ELSE 0 END,
       f.away_score, f.home_score,
       CASE f.regulation_result WHEN 'A' THEN 'W' WHEN 'H' THEN 'L' ELSE 'D' END,
       CASE WHEN f.final_result = 'A' THEN 1 ELSE 0 END
FROM gold.fact_match AS f;

/* ---- fact_goal and fact_booking ----------------------------------------- */
CREATE TABLE gold.fact_goal (
    goal_id            VARCHAR(12)  NOT NULL PRIMARY KEY,
    match_key          INT          NOT NULL REFERENCES gold.fact_match (match_key),
    team_key           INT          NOT NULL REFERENCES gold.dim_team (team_key),
    player_key         INT          NOT NULL REFERENCES gold.dim_player (player_key),
    minute_regulation  SMALLINT     NOT NULL,
    minute_stoppage    SMALLINT     NOT NULL,
    is_extra_time      SMALLINT     NOT NULL,
    is_own_goal        SMALLINT     NOT NULL,
    is_penalty         SMALLINT     NOT NULL
);

INSERT INTO gold.fact_goal
SELECT g.goal_id, f.match_key, t.team_key, p.player_key,
       g.minute_regulation, g.minute_stoppage,
       CASE WHEN g.minute_regulation > 90 THEN 1 ELSE 0 END,
       g.is_own_goal, g.is_penalty
FROM silver.goal AS g
INNER JOIN gold.fact_match AS f ON f.match_id  = g.match_id
INNER JOIN gold.dim_team   AS t ON t.team_id   = g.team_id
INNER JOIN gold.dim_player AS p ON p.player_id = g.player_id;

CREATE TABLE gold.fact_booking (
    booking_id         VARCHAR(12)  NOT NULL PRIMARY KEY,
    match_key          INT          NOT NULL REFERENCES gold.fact_match (match_key),
    team_key           INT          NOT NULL REFERENCES gold.dim_team (team_key),
    player_key         INT          NOT NULL REFERENCES gold.dim_player (player_key),
    minute_regulation  SMALLINT     NOT NULL,
    is_yellow          SMALLINT     NOT NULL,
    is_red             SMALLINT     NOT NULL,
    is_second_yellow   SMALLINT     NOT NULL
);

INSERT INTO gold.fact_booking
SELECT b.booking_id, f.match_key, t.team_key, p.player_key, b.minute_regulation,
       b.is_yellow, b.is_red, b.is_second_yellow
FROM silver.booking AS b
INNER JOIN gold.fact_match AS f ON f.match_id  = b.match_id
INNER JOIN gold.dim_team   AS t ON t.team_id   = b.team_id
INNER JOIN gold.dim_player AS p ON p.player_id = b.player_id;
GO

/* ---- Mart: one row per team per tournament ------------------------------ */
CREATE OR ALTER VIEW gold.v_team_tournament
AS
SELECT tm.tournament_key,
       tm.team_key,
       COUNT(*)                                              AS matches,
       SUM(CASE WHEN tm.outcome = 'W' THEN 1 ELSE 0 END)     AS wins,
       SUM(CASE WHEN tm.outcome = 'D' THEN 1 ELSE 0 END)     AS draws,
       SUM(CASE WHEN tm.outcome = 'L' THEN 1 ELSE 0 END)     AS losses,
       SUM(tm.goals_for)                                     AS goals_for,
       SUM(tm.goals_against)                                 AS goals_against,
       MAX(s.stage_order)                                    AS furthest_stage_order,
       MAX(tm.is_host)                                       AS is_host
FROM gold.fact_team_match AS tm
INNER JOIN gold.dim_stage AS s ON s.stage_key = tm.stage_key
GROUP BY tm.tournament_key, tm.team_key;
GO

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'gold', 'dim_tournament',  COUNT(*) FROM gold.dim_tournament UNION ALL
SELECT 'gold', 'dim_team',        COUNT(*) FROM gold.dim_team UNION ALL
SELECT 'gold', 'dim_player',      COUNT(*) FROM gold.dim_player UNION ALL
SELECT 'gold', 'fact_match',      COUNT(*) FROM gold.fact_match UNION ALL
SELECT 'gold', 'fact_team_match', COUNT(*) FROM gold.fact_team_match UNION ALL
SELECT 'gold', 'fact_goal',       COUNT(*) FROM gold.fact_goal UNION ALL
SELECT 'gold', 'fact_booking',    COUNT(*) FROM gold.fact_booking;
GO
