/* =============================================================================
   03_pipeline_tables.sql
   Tables for stages 1-3: raw, staging and clean.

   raw.match        every row of every delivery, every column as text,
                    with the file name, load id and row number it came from.
                    Nothing is ever rejected or changed here, so any later
                    number can be traced back to a line in a file.
   stg.match        latest delivery of each file, converted to proper types.
                    A value that will not convert becomes NULL and is counted
                    in type_errors, so bad values are visible, not hidden.
   cln.match        one row per real match, team names standardised, every
                    validation rule applied.
   cln.match_issue  rows held back from cln.match and why (quarantine).
   cln.cleaning_log one row per cleaning step with rows in/out/affected.
============================================================================= */

USE EuroLeagues;
GO

DROP VIEW  IF EXISTS raw.v_match_landing;
DROP TABLE IF EXISTS raw.match_landing;
DROP TABLE IF EXISTS raw.match;
DROP TABLE IF EXISTS raw.load_log;
DROP TABLE IF EXISTS stg.match;
DROP TABLE IF EXISTS cln.match;
DROP TABLE IF EXISTS cln.match_issue;
DROP TABLE IF EXISTS cln.cleaning_log;
GO

/* ---- Stage 1: raw ------------------------------------------------------- */

-- Landing table for one file at a time. The identity column records the
-- line number in the file; BULK INSERT loads through the view below so the
-- identity is filled automatically.
CREATE TABLE raw.match_landing (
    source_row_no   INT IDENTITY(1, 1) NOT NULL,
    [Date]      NVARCHAR(50) NULL, HomeTeam NVARCHAR(100) NULL, AwayTeam NVARCHAR(100) NULL,
    FTHG        NVARCHAR(20) NULL, FTAG     NVARCHAR(20)  NULL, FTR      NVARCHAR(20)  NULL,
    HTHG        NVARCHAR(20) NULL, HTAG     NVARCHAR(20)  NULL, HTR      NVARCHAR(20)  NULL,
    Referee     NVARCHAR(100) NULL,
    HS NVARCHAR(20) NULL, [AS] NVARCHAR(20) NULL, HST NVARCHAR(20) NULL, AST NVARCHAR(20) NULL,
    HF NVARCHAR(20) NULL, AF   NVARCHAR(20) NULL, HC  NVARCHAR(20) NULL, AC  NVARCHAR(20) NULL,
    HY NVARCHAR(20) NULL, AY   NVARCHAR(20) NULL, HR  NVARCHAR(20) NULL, AR  NVARCHAR(20) NULL
);
GO

CREATE VIEW raw.v_match_landing
AS
SELECT [Date], HomeTeam, AwayTeam, FTHG, FTAG, FTR, HTHG, HTAG, HTR, Referee,
       HS, [AS], HST, AST, HF, AF, HC, AC, HY, AY, HR, AR
FROM raw.match_landing;
GO

CREATE TABLE raw.load_log (
    load_id         INT IDENTITY(1, 1) NOT NULL,
    file_name       VARCHAR(60)        NOT NULL,
    rows_loaded     INT                NOT NULL,
    loaded_at       DATETIME2(0)       NOT NULL CONSTRAINT df_load_log_at DEFAULT SYSDATETIME(),
    loaded_by       SYSNAME            NOT NULL CONSTRAINT df_load_log_by DEFAULT SUSER_SNAME(),
    CONSTRAINT pk_raw_load_log PRIMARY KEY (load_id)
);

CREATE TABLE raw.match (
    load_id         INT            NOT NULL,
    file_name       VARCHAR(60)    NOT NULL,
    source_row_no   INT            NOT NULL,
    [Date]      NVARCHAR(50) NULL, HomeTeam NVARCHAR(100) NULL, AwayTeam NVARCHAR(100) NULL,
    FTHG        NVARCHAR(20) NULL, FTAG     NVARCHAR(20)  NULL, FTR      NVARCHAR(20)  NULL,
    HTHG        NVARCHAR(20) NULL, HTAG     NVARCHAR(20)  NULL, HTR      NVARCHAR(20)  NULL,
    Referee     NVARCHAR(100) NULL,
    HS NVARCHAR(20) NULL, [AS] NVARCHAR(20) NULL, HST NVARCHAR(20) NULL, AST NVARCHAR(20) NULL,
    HF NVARCHAR(20) NULL, AF   NVARCHAR(20) NULL, HC  NVARCHAR(20) NULL, AC  NVARCHAR(20) NULL,
    HY NVARCHAR(20) NULL, AY   NVARCHAR(20) NULL, HR  NVARCHAR(20) NULL, AR  NVARCHAR(20) NULL,
    CONSTRAINT pk_raw_match PRIMARY KEY (load_id, source_row_no),
    CONSTRAINT fk_raw_match_load FOREIGN KEY (load_id) REFERENCES raw.load_log (load_id)
);
GO

/* ---- Stage 2: staging (typed) ------------------------------------------- */
CREATE TABLE stg.match (
    load_id             INT            NOT NULL,
    file_name           VARCHAR(60)    NOT NULL,
    source_row_no       INT            NOT NULL,
    league_code         CHAR(3)        NOT NULL,
    season_start_year   SMALLINT       NOT NULL,
    match_date          DATE           NULL,
    home_team_src       NVARCHAR(100)  NULL,
    away_team_src       NVARCHAR(100)  NULL,
    ft_home_goals       TINYINT NULL, ft_away_goals TINYINT NULL, ft_result CHAR(1) NULL,
    ht_home_goals       TINYINT NULL, ht_away_goals TINYINT NULL, ht_result CHAR(1) NULL,
    referee             NVARCHAR(100)  NULL,
    home_shots          TINYINT NULL, away_shots          TINYINT NULL,
    home_shots_on_target TINYINT NULL, away_shots_on_target TINYINT NULL,
    home_fouls          TINYINT NULL, away_fouls          TINYINT NULL,
    home_corners        TINYINT NULL, away_corners        TINYINT NULL,
    home_yellows        TINYINT NULL, away_yellows        TINYINT NULL,
    home_reds           TINYINT NULL, away_reds           TINYINT NULL,
    type_errors         TINYINT        NOT NULL,
    had_carriage_return BIT            NOT NULL,
    CONSTRAINT pk_stg_match PRIMARY KEY (load_id, source_row_no)
);
GO

/* ---- Stage 3: clean ----------------------------------------------------- */
CREATE TABLE cln.match (
    match_id            INT            NOT NULL,     -- stable id: league, season, date, home team
    league_code         CHAR(3)        NOT NULL,
    season_start_year   SMALLINT       NOT NULL,
    match_date          DATE           NOT NULL,
    home_team           NVARCHAR(60)   NOT NULL,
    away_team           NVARCHAR(60)   NOT NULL,
    ft_home_goals       TINYINT        NOT NULL,
    ft_away_goals       TINYINT        NOT NULL,
    ft_result           CHAR(1)        NOT NULL,
    ht_home_goals       TINYINT NULL, ht_away_goals TINYINT NULL, ht_result CHAR(1) NULL,
    referee             NVARCHAR(100)  NULL,
    home_shots          TINYINT NULL, away_shots          TINYINT NULL,
    home_shots_on_target TINYINT NULL, away_shots_on_target TINYINT NULL,
    home_fouls          TINYINT NULL, away_fouls          TINYINT NULL,
    home_corners        TINYINT NULL, away_corners        TINYINT NULL,
    home_yellows        TINYINT NULL, away_yellows        TINYINT NULL,
    home_reds           TINYINT NULL, away_reds           TINYINT NULL,
    stats_complete      BIT            NOT NULL,     -- 0 = result known, match statistics missing
    referee_supplied    BIT            NOT NULL,
    source_file         VARCHAR(60)    NOT NULL,
    source_row_no       INT            NOT NULL,
    CONSTRAINT pk_cln_match PRIMARY KEY (match_id),
    CONSTRAINT uq_cln_match UNIQUE (league_code, season_start_year, home_team, away_team),
    CONSTRAINT ck_cln_match_result CHECK (ft_result IN ('H', 'D', 'A'))
);

CREATE TABLE cln.match_issue (
    issue_id        INT IDENTITY(1, 1) NOT NULL,
    rule_code       VARCHAR(40)        NOT NULL,
    load_id         INT                NOT NULL,
    source_row_no   INT                NOT NULL,
    file_name       VARCHAR(60)        NOT NULL,
    detail          NVARCHAR(400)      NULL,
    logged_at       DATETIME2(0)       NOT NULL CONSTRAINT df_match_issue_at DEFAULT SYSDATETIME(),
    CONSTRAINT pk_cln_match_issue PRIMARY KEY (issue_id)
);

CREATE TABLE cln.cleaning_log (
    step_no         TINYINT        NOT NULL,
    step_type       VARCHAR(12)    NOT NULL,     -- START, STANDARDISE, QUARANTINE, FLAG, END
    step_name       NVARCHAR(120)  NOT NULL,
    rows_in         INT            NULL,
    rows_affected   INT            NOT NULL,
    rows_out        INT            NULL,
    logged_at       DATETIME2(0)   NOT NULL CONSTRAINT df_cleaning_log_at DEFAULT SYSDATETIME(),
    CONSTRAINT pk_cln_cleaning_log PRIMARY KEY (step_no)
);
GO
