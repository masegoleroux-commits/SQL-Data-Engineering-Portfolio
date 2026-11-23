/* =============================================================================
   01_build_star_schema.sql
   Gold layer.

   dim_league        one row per league
   dim_season        one row per season
   dim_team          one row per club per league (canonical names only)
   fact_match        GRAIN: one scheduled match
   fact_team_match   GRAIN: one team in one match (two rows per match),
                     results only for matches that count in the table
   v_league_table    one row per team per league per season, ranked
============================================================================= */

USE FootballLeagues;
GO

DROP VIEW IF EXISTS gold.v_league_table;
DROP TABLE IF EXISTS gold.fact_team_match;
DROP TABLE IF EXISTS gold.fact_match;
DROP TABLE IF EXISTS gold.dim_team;
DROP TABLE IF EXISTS gold.dim_season;
DROP TABLE IF EXISTS gold.dim_league;
GO

CREATE TABLE gold.dim_league (
    league_key     INT            NOT NULL PRIMARY KEY,
    league_code    VARCHAR(5)     NOT NULL UNIQUE,
    league_name    VARCHAR(40)    NOT NULL,
    country        VARCHAR(20)    NOT NULL
);

INSERT INTO gold.dim_league VALUES
    (1, 'en.1', 'Premier League', 'England'),
    (2, 'es.1', 'La Liga',        'Spain'),
    (3, 'de.1', 'Bundesliga',     'Germany'),
    (4, 'it.1', 'Serie A',        'Italy'),
    (5, 'fr.1', 'Ligue 1',        'France');

CREATE TABLE gold.dim_season (
    season_key     INT          NOT NULL PRIMARY KEY,   -- season start year
    season_label   VARCHAR(7)   NOT NULL UNIQUE
);

INSERT INTO gold.dim_season
SELECT DISTINCT season_start, season_label FROM silver.source_file;

CREATE TABLE gold.dim_team (
    team_key       INT            NOT NULL PRIMARY KEY,
    league_key     INT            NOT NULL REFERENCES gold.dim_league (league_key),
    team_name      NVARCHAR(60)   NOT NULL,
    seasons_in_data SMALLINT      NOT NULL,
    name_variants  SMALLINT       NOT NULL,
    UNIQUE (league_key, team_name)
);

INSERT INTO gold.dim_team
SELECT ROW_NUMBER() OVER (ORDER BY l.league_key, t.team_name),
       l.league_key, t.team_name, t.seasons, t.variants
FROM (
    SELECT m.league_code, m.home_team AS team_name, COUNT(DISTINCT m.season_start) AS seasons,
           (SELECT COUNT(*) FROM silver.team_alias AS a
            WHERE a.league_code = m.league_code AND a.canonical_name = m.home_team) AS variants
    FROM silver.match AS m
    GROUP BY m.league_code, m.home_team
) AS t
INNER JOIN gold.dim_league AS l ON l.league_code = t.league_code;
GO

CREATE TABLE gold.fact_match (
    match_key       INT            NOT NULL PRIMARY KEY,
    match_id        VARCHAR(80)    NOT NULL UNIQUE,
    league_key      INT            NOT NULL REFERENCES gold.dim_league (league_key),
    season_key      INT            NOT NULL REFERENCES gold.dim_season (season_key),
    matchday        SMALLINT       NOT NULL,
    match_date      DATE           NOT NULL,
    home_team_key   INT            NOT NULL REFERENCES gold.dim_team (team_key),
    away_team_key   INT            NOT NULL REFERENCES gold.dim_team (team_key),
    match_status    VARCHAR(20)    NOT NULL,
    counts_in_table SMALLINT       NOT NULL,   -- played or awarded
    counts_in_goals SMALLINT       NOT NULL,   -- played only
    ht_home         SMALLINT       NULL,
    ht_away         SMALLINT       NULL,
    ft_home         SMALLINT       NULL,
    ft_away         SMALLINT       NULL,
    result          CHAR(1)        NULL        -- H / D / A
);

INSERT INTO gold.fact_match
SELECT ROW_NUMBER() OVER (ORDER BY m.match_date, m.league_code, m.home_team),
       m.match_id, l.league_key, m.season_start, m.matchday, m.match_date,
       th.team_key, ta.team_key, m.match_status,
       CASE WHEN m.match_status IN ('played', 'awarded') THEN 1 ELSE 0 END,
       CASE WHEN m.match_status = 'played' THEN 1 ELSE 0 END,
       m.ht_home, m.ht_away, m.ft_home, m.ft_away,
       CASE WHEN m.ft_home > m.ft_away THEN 'H'
            WHEN m.ft_home < m.ft_away THEN 'A'
            WHEN m.ft_home = m.ft_away THEN 'D' END
FROM silver.match AS m
INNER JOIN gold.dim_league AS l  ON l.league_code = m.league_code
INNER JOIN gold.dim_team   AS th ON th.league_key = l.league_key AND th.team_name = m.home_team
INNER JOIN gold.dim_team   AS ta ON ta.league_key = l.league_key AND ta.team_name = m.away_team;
GO

CREATE TABLE gold.fact_team_match (
    match_key      INT       NOT NULL REFERENCES gold.fact_match (match_key),
    team_key       INT       NOT NULL REFERENCES gold.dim_team (team_key),
    opponent_key   INT       NOT NULL REFERENCES gold.dim_team (team_key),
    league_key     INT       NOT NULL,
    season_key     INT       NOT NULL,
    match_date     DATE      NOT NULL,
    is_home        SMALLINT  NOT NULL,
    goals_for      SMALLINT  NOT NULL,
    goals_against  SMALLINT  NOT NULL,
    outcome        CHAR(1)   NOT NULL,      -- W / D / L
    points         SMALLINT  NOT NULL,
    counts_in_goals SMALLINT NOT NULL,
    PRIMARY KEY (match_key, team_key)
);

DECLARE @win  DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'points_win');
DECLARE @draw DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'points_draw');

INSERT INTO gold.fact_team_match
SELECT x.match_key, x.team_key, x.opponent_key, x.league_key, x.season_key, x.match_date,
       x.is_home, x.gf, x.ga,
       CASE WHEN x.gf > x.ga THEN 'W' WHEN x.gf = x.ga THEN 'D' ELSE 'L' END,
       CASE WHEN x.gf > x.ga THEN @win WHEN x.gf = x.ga THEN @draw ELSE 0 END,
       x.counts_in_goals
FROM (
    SELECT match_key, home_team_key AS team_key, away_team_key AS opponent_key, league_key, season_key,
           match_date, 1 AS is_home, ft_home AS gf, ft_away AS ga, counts_in_goals
    FROM gold.fact_match WHERE counts_in_table = 1
    UNION ALL
    SELECT match_key, away_team_key, home_team_key, league_key, season_key,
           match_date, 0, ft_away, ft_home, counts_in_goals
    FROM gold.fact_match WHERE counts_in_table = 1
) AS x;
GO

-- Ranked on points, then goal difference, then goals scored. Some leagues
-- use head-to-head before goal difference (La Liga, Serie A); this view
-- applies one rule to all five so the leagues can be compared.
CREATE VIEW gold.v_league_table
AS
SELECT t.league_key, t.season_key, t.team_key,
       t.played, t.won, t.drawn, t.lost, t.goals_for, t.goals_against,
       t.goals_for - t.goals_against AS goal_difference,
       t.points,
       RANK() OVER (PARTITION BY t.league_key, t.season_key
                    ORDER BY t.points DESC, t.goals_for - t.goals_against DESC, t.goals_for DESC) AS position
FROM (
    SELECT league_key, season_key, team_key,
           COUNT(*)                                        AS played,
           SUM(CASE WHEN outcome = 'W' THEN 1 ELSE 0 END)  AS won,
           SUM(CASE WHEN outcome = 'D' THEN 1 ELSE 0 END)  AS drawn,
           SUM(CASE WHEN outcome = 'L' THEN 1 ELSE 0 END)  AS lost,
           SUM(goals_for)                                  AS goals_for,
           SUM(goals_against)                              AS goals_against,
           SUM(points)                                     AS points
    FROM gold.fact_team_match
    GROUP BY league_key, season_key, team_key
) AS t;
GO

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'gold', 'dim_league',      COUNT(*) FROM gold.dim_league UNION ALL
SELECT 'gold', 'dim_season',      COUNT(*) FROM gold.dim_season UNION ALL
SELECT 'gold', 'dim_team',        COUNT(*) FROM gold.dim_team UNION ALL
SELECT 'gold', 'fact_match',      COUNT(*) FROM gold.fact_match UNION ALL
SELECT 'gold', 'fact_team_match', COUNT(*) FROM gold.fact_team_match;
GO
