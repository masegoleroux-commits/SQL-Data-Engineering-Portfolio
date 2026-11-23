/* =============================================================================
   04_model_tables.sql
   Stage 4: star schema (schema dw).

   dim_league       one row per competition
   dim_season       one row per season (key = start year, e.g. 2024 = 2024/25)
   dim_team         one row per club (standard name)
   dim_referee      one row per referee; -1 = not supplied by the source
   dim_date         one row per calendar day in the data range
   fact_match       GRAIN: one row per match
   fact_team_match  GRAIN: one row per team per match (two rows per match).
                    Same facts seen from each team's side, which makes
                    league tables and "team form" queries simple.
============================================================================= */

USE EuroLeagues;
GO

DROP TABLE IF EXISTS dw.fact_team_match;
DROP TABLE IF EXISTS dw.fact_match;
DROP TABLE IF EXISTS dw.dim_date;
DROP TABLE IF EXISTS dw.dim_referee;
DROP TABLE IF EXISTS dw.dim_team;
DROP TABLE IF EXISTS dw.dim_season;
DROP TABLE IF EXISTS dw.dim_league;
GO

CREATE TABLE dw.dim_league (
    league_key      TINYINT IDENTITY(1, 1) NOT NULL,
    league_code     CHAR(3)       NOT NULL,
    league_name     NVARCHAR(50)  NOT NULL,
    country         NVARCHAR(50)  NOT NULL,
    CONSTRAINT pk_dim_league PRIMARY KEY (league_key),
    CONSTRAINT uq_dim_league UNIQUE (league_code)
);

CREATE TABLE dw.dim_season (
    season_key      SMALLINT      NOT NULL,     -- start year
    season_label    CHAR(7)       NOT NULL,     -- '2024/25'
    CONSTRAINT pk_dim_season PRIMARY KEY (season_key)
);

CREATE TABLE dw.dim_team (
    team_key        SMALLINT IDENTITY(1, 1) NOT NULL,
    team_name       NVARCHAR(60)  NOT NULL,
    league_key      TINYINT       NOT NULL,
    CONSTRAINT pk_dim_team PRIMARY KEY (team_key),
    CONSTRAINT uq_dim_team UNIQUE (team_name),
    CONSTRAINT fk_dim_team_league FOREIGN KEY (league_key) REFERENCES dw.dim_league (league_key)
);

CREATE TABLE dw.dim_referee (
    referee_key     SMALLINT IDENTITY(1, 1) NOT NULL,
    referee_name    NVARCHAR(100) NOT NULL,
    CONSTRAINT pk_dim_referee PRIMARY KEY (referee_key),
    CONSTRAINT uq_dim_referee UNIQUE (referee_name)
);

CREATE TABLE dw.dim_date (
    date_key        INT           NOT NULL,     -- yyyymmdd
    full_date       DATE          NOT NULL,
    day_name        VARCHAR(10)   NOT NULL,
    is_weekend      BIT           NOT NULL,
    month_number    TINYINT       NOT NULL,
    month_name      VARCHAR(10)   NOT NULL,
    calendar_year   SMALLINT      NOT NULL,
    CONSTRAINT pk_dim_date PRIMARY KEY (date_key),
    CONSTRAINT uq_dim_date UNIQUE (full_date)
);

CREATE TABLE dw.fact_match (
    match_key           INT           NOT NULL,     -- = cln.match.match_id
    date_key            INT           NOT NULL,
    league_key          TINYINT       NOT NULL,
    season_key          SMALLINT      NOT NULL,
    home_team_key       SMALLINT      NOT NULL,
    away_team_key       SMALLINT      NOT NULL,
    referee_key         SMALLINT      NOT NULL,
    ft_home_goals       TINYINT       NOT NULL,
    ft_away_goals       TINYINT       NOT NULL,
    ft_result           CHAR(1)       NOT NULL,
    ht_home_goals       TINYINT NULL, ht_away_goals TINYINT NULL, ht_result CHAR(1) NULL,
    home_shots          TINYINT NULL, away_shots          TINYINT NULL,
    home_shots_on_target TINYINT NULL, away_shots_on_target TINYINT NULL,
    home_fouls          TINYINT NULL, away_fouls          TINYINT NULL,
    home_corners        TINYINT NULL, away_corners        TINYINT NULL,
    home_yellows        TINYINT NULL, away_yellows        TINYINT NULL,
    home_reds           TINYINT NULL, away_reds           TINYINT NULL,
    stats_complete      BIT           NOT NULL,
    CONSTRAINT pk_fact_match PRIMARY KEY (match_key),
    CONSTRAINT uq_fact_match UNIQUE (league_key, season_key, home_team_key, away_team_key),
    CONSTRAINT fk_fact_match_date    FOREIGN KEY (date_key)      REFERENCES dw.dim_date (date_key),
    CONSTRAINT fk_fact_match_league  FOREIGN KEY (league_key)    REFERENCES dw.dim_league (league_key),
    CONSTRAINT fk_fact_match_season  FOREIGN KEY (season_key)    REFERENCES dw.dim_season (season_key),
    CONSTRAINT fk_fact_match_home    FOREIGN KEY (home_team_key) REFERENCES dw.dim_team (team_key),
    CONSTRAINT fk_fact_match_away    FOREIGN KEY (away_team_key) REFERENCES dw.dim_team (team_key),
    CONSTRAINT fk_fact_match_referee FOREIGN KEY (referee_key)   REFERENCES dw.dim_referee (referee_key),
    CONSTRAINT ck_fact_match_teams   CHECK (home_team_key <> away_team_key),
    CONSTRAINT ck_fact_match_ht      CHECK (ht_home_goals IS NULL OR (ht_home_goals <= ft_home_goals AND ht_away_goals <= ft_away_goals)),
    CONSTRAINT ck_fact_match_sot     CHECK (home_shots_on_target IS NULL OR (home_shots_on_target <= home_shots AND away_shots_on_target <= away_shots))
);

CREATE TABLE dw.fact_team_match (
    match_key           INT           NOT NULL,
    team_key            SMALLINT      NOT NULL,
    opponent_key        SMALLINT      NOT NULL,
    date_key            INT           NOT NULL,
    league_key          TINYINT       NOT NULL,
    season_key          SMALLINT      NOT NULL,
    is_home             BIT           NOT NULL,
    goals_for           TINYINT       NOT NULL,
    goals_against       TINYINT       NOT NULL,
    result              CHAR(1)       NOT NULL,     -- W / D / L from this team's side
    points              TINYINT       NOT NULL,
    ht_goals_for        TINYINT NULL, ht_goals_against TINYINT NULL,
    shots_for           TINYINT NULL, shots_against    TINYINT NULL,
    shots_on_target_for TINYINT NULL, shots_on_target_against TINYINT NULL,
    fouls               TINYINT NULL, corners TINYINT NULL,
    yellows             TINYINT NULL, reds    TINYINT NULL,
    stats_complete      BIT           NOT NULL,
    CONSTRAINT pk_fact_team_match PRIMARY KEY (match_key, team_key),
    CONSTRAINT fk_fact_team_match_match FOREIGN KEY (match_key)    REFERENCES dw.fact_match (match_key),
    CONSTRAINT fk_fact_team_match_team  FOREIGN KEY (team_key)     REFERENCES dw.dim_team (team_key),
    CONSTRAINT fk_fact_team_match_opp   FOREIGN KEY (opponent_key) REFERENCES dw.dim_team (team_key),
    CONSTRAINT ck_fact_team_match_res   CHECK (result IN ('W', 'D', 'L'))
);

-- Team-by-date lookups drive the form features and league tables
CREATE NONCLUSTERED INDEX ix_fact_team_match_team_date
    ON dw.fact_team_match (team_key, date_key)
    INCLUDE (points, goals_for, goals_against, shots_on_target_for, stats_complete);

CREATE NONCLUSTERED INDEX ix_fact_match_league_season
    ON dw.fact_match (league_key, season_key)
    INCLUDE (ft_result, ft_home_goals, ft_away_goals);
GO
