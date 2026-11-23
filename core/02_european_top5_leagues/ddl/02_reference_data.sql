/* =============================================================================
   02_reference_data.sql
   Stage 0: reference data and business parameters (schema cfg).

   cfg.business_parameter  numbers the business can change without touching
                           code: points per result, Elo settings, the
                           train/test split, the form window
   cfg.league              the five competitions
   cfg.source_file         the 15 files and the league/season each one holds
                           (the CSVs do not contain league or season columns)
   cfg.league_season       teams and automatic relegation places per season
   cfg.team_alias          source team name -> one standard name per club

   Rebuilding this file resets every parameter to its default.
============================================================================= */

USE EuroLeagues;
GO

DROP TABLE IF EXISTS cfg.team_alias;
DROP TABLE IF EXISTS cfg.league_season;
DROP TABLE IF EXISTS cfg.source_file;
DROP TABLE IF EXISTS cfg.league;
DROP TABLE IF EXISTS cfg.business_parameter;
GO

/* ---- Business parameters ------------------------------------------------ */
CREATE TABLE cfg.business_parameter (
    param_name      VARCHAR(50)     NOT NULL,
    param_value     DECIMAL(12, 4)  NOT NULL,
    unit            VARCHAR(20)     NOT NULL,
    description     NVARCHAR(200)   NOT NULL,
    updated_by      SYSNAME         NOT NULL CONSTRAINT df_bp_by DEFAULT SUSER_SNAME(),
    updated_at      DATETIME2(0)    NOT NULL CONSTRAINT df_bp_at DEFAULT SYSDATETIME(),
    CONSTRAINT pk_business_parameter PRIMARY KEY (param_name)
);

INSERT INTO cfg.business_parameter (param_name, param_value, unit, description)
VALUES
    ('points_win',            3,    'points',  N'League points for a win'),
    ('points_draw',           1,    'points',  N'League points for a draw'),
    ('form_window',           5,    'matches', N'Number of previous matches used for rolling form features'),
    ('elo_initial_rating',    1500, 'rating',  N'Starting Elo rating for every team in the first season'),
    ('elo_promoted_rating',   1450, 'rating',  N'Starting Elo rating for a team first seen in a later season (promoted)'),
    ('elo_k_factor',          20,   'rating',  N'How far one result moves a rating'),
    ('elo_home_advantage',    60,   'rating',  N'Rating points added to the home team when predicting'),
    ('elo_season_carryover',  0.8,  'ratio',   N'Share of a rating''s distance from 1500 kept into the next season'),
    ('calibration_bins',      10,   'bins',    N'Number of probability bands used to calibrate the model'),
    ('burn_in_season',        2022, 'season',  N'Season used only to warm up the ratings'),
    ('train_season',          2023, 'season',  N'Season used to learn outcome probabilities'),
    ('test_season',           2024, 'season',  N'Season held back to measure accuracy'),
    ('min_referee_matches',   10,   'matches', N'Minimum matches before a referee appears in the strictness ranking');

/* ---- Leagues ------------------------------------------------------------ */
CREATE TABLE cfg.league (
    league_code     CHAR(3)         NOT NULL,
    league_name     NVARCHAR(50)    NOT NULL,
    country         NVARCHAR(50)    NOT NULL,
    CONSTRAINT pk_cfg_league PRIMARY KEY (league_code)
);

INSERT INTO cfg.league VALUES
    ('EPL', N'Premier League', N'England'),
    ('LLA', N'La Liga',        N'Spain'),
    ('SEA', N'Serie A',        N'Italy'),
    ('BUN', N'Bundesliga',     N'Germany'),
    ('LI1', N'Ligue 1',        N'France');

/* ---- Source files ------------------------------------------------------- */
CREATE TABLE cfg.source_file (
    file_name           VARCHAR(60)     NOT NULL,
    league_code         CHAR(3)         NOT NULL,
    season_start_year   SMALLINT        NOT NULL,
    CONSTRAINT pk_cfg_source_file PRIMARY KEY (file_name),
    CONSTRAINT fk_cfg_source_file_league FOREIGN KEY (league_code) REFERENCES cfg.league (league_code),
    CONSTRAINT uq_cfg_source_file UNIQUE (league_code, season_start_year)
);

INSERT INTO cfg.source_file VALUES
    ('premier-league_2223.csv', 'EPL', 2022), ('premier-league_2324.csv', 'EPL', 2023), ('premier-league_2425.csv', 'EPL', 2024),
    ('la-liga_2223.csv',        'LLA', 2022), ('la-liga_2324.csv',        'LLA', 2023), ('la-liga_2425.csv',        'LLA', 2024),
    ('serie-a_2223.csv',        'SEA', 2022), ('serie-a_2324.csv',        'SEA', 2023), ('serie-a_2425.csv',        'SEA', 2024),
    ('bundesliga_2223.csv',     'BUN', 2022), ('bundesliga_2324.csv',     'BUN', 2023), ('bundesliga_2425.csv',     'BUN', 2024),
    ('ligue-1_2223.csv',        'LI1', 2022), ('ligue-1_2324.csv',        'LI1', 2023), ('ligue-1_2425.csv',        'LI1', 2024);

/* ---- League seasons ----------------------------------------------------- */
-- Ligue 1 went from 20 to 18 clubs in 2023/24, so 2022/23 had four
-- automatic relegation places and later seasons have two plus a play-off.
CREATE TABLE cfg.league_season (
    league_code         CHAR(3)     NOT NULL,
    season_start_year   SMALLINT    NOT NULL,
    teams               TINYINT     NOT NULL,
    relegation_places   TINYINT     NOT NULL,
    CONSTRAINT pk_cfg_league_season PRIMARY KEY (league_code, season_start_year),
    CONSTRAINT fk_cfg_league_season_league FOREIGN KEY (league_code) REFERENCES cfg.league (league_code)
);

INSERT INTO cfg.league_season VALUES
    ('EPL', 2022, 20, 3), ('EPL', 2023, 20, 3), ('EPL', 2024, 20, 3),
    ('LLA', 2022, 20, 3), ('LLA', 2023, 20, 3), ('LLA', 2024, 20, 3),
    ('SEA', 2022, 20, 3), ('SEA', 2023, 20, 3), ('SEA', 2024, 20, 3),
    ('BUN', 2022, 18, 2), ('BUN', 2023, 18, 2), ('BUN', 2024, 18, 2),
    ('LI1', 2022, 20, 4), ('LI1', 2023, 18, 2), ('LI1', 2024, 18, 2);

/* ---- Team aliases ------------------------------------------------------- */
-- The source abbreviates names ("Man City", "Nott'm Forest", "Ath Madrid").
-- Every name that appears in a file must be listed here, even when it is
-- already the standard name, so an unknown name is caught instead of
-- silently creating a new team.
CREATE TABLE cfg.team_alias (
    league_code     CHAR(3)         NOT NULL,
    source_name     NVARCHAR(60)    NOT NULL,
    team_name       NVARCHAR(60)    NOT NULL,
    CONSTRAINT pk_cfg_team_alias PRIMARY KEY (source_name),
    CONSTRAINT fk_cfg_team_alias_league FOREIGN KEY (league_code) REFERENCES cfg.league (league_code)
);

INSERT INTO cfg.team_alias (league_code, source_name, team_name) VALUES
    -- Premier League
    ('EPL', N'Arsenal',          N'Arsenal'),
    ('EPL', N'Aston Villa',      N'Aston Villa'),
    ('EPL', N'Bournemouth',      N'AFC Bournemouth'),
    ('EPL', N'Brentford',        N'Brentford'),
    ('EPL', N'Brighton',         N'Brighton & Hove Albion'),
    ('EPL', N'Burnley',          N'Burnley'),
    ('EPL', N'Chelsea',          N'Chelsea'),
    ('EPL', N'Crystal Palace',   N'Crystal Palace'),
    ('EPL', N'Everton',          N'Everton'),
    ('EPL', N'Fulham',           N'Fulham'),
    ('EPL', N'Ipswich',          N'Ipswich Town'),
    ('EPL', N'Leeds',            N'Leeds United'),
    ('EPL', N'Leicester',        N'Leicester City'),
    ('EPL', N'Liverpool',        N'Liverpool'),
    ('EPL', N'Luton',            N'Luton Town'),
    ('EPL', N'Man City',         N'Manchester City'),
    ('EPL', N'Man United',       N'Manchester United'),
    ('EPL', N'Newcastle',        N'Newcastle United'),
    ('EPL', N'Nott''m Forest',   N'Nottingham Forest'),
    ('EPL', N'Sheffield United', N'Sheffield United'),
    ('EPL', N'Southampton',      N'Southampton'),
    ('EPL', N'Tottenham',        N'Tottenham Hotspur'),
    ('EPL', N'West Ham',         N'West Ham United'),
    ('EPL', N'Wolves',           N'Wolverhampton Wanderers'),
    -- La Liga
    ('LLA', N'Alaves',           N'Alaves'),
    ('LLA', N'Almeria',          N'Almeria'),
    ('LLA', N'Ath Bilbao',       N'Athletic Bilbao'),
    ('LLA', N'Ath Madrid',       N'Atletico Madrid'),
    ('LLA', N'Barcelona',        N'Barcelona'),
    ('LLA', N'Betis',            N'Real Betis'),
    ('LLA', N'Cadiz',            N'Cadiz'),
    ('LLA', N'Celta',            N'Celta Vigo'),
    ('LLA', N'Elche',            N'Elche'),
    ('LLA', N'Espanol',          N'Espanyol'),
    ('LLA', N'Getafe',           N'Getafe'),
    ('LLA', N'Girona',           N'Girona'),
    ('LLA', N'Granada',          N'Granada'),
    ('LLA', N'Las Palmas',       N'Las Palmas'),
    ('LLA', N'Leganes',          N'Leganes'),
    ('LLA', N'Mallorca',         N'Mallorca'),
    ('LLA', N'Osasuna',          N'Osasuna'),
    ('LLA', N'Real Madrid',      N'Real Madrid'),
    ('LLA', N'Sevilla',          N'Sevilla'),
    ('LLA', N'Sociedad',         N'Real Sociedad'),
    ('LLA', N'Valencia',         N'Valencia'),
    ('LLA', N'Valladolid',       N'Real Valladolid'),
    ('LLA', N'Vallecano',        N'Rayo Vallecano'),
    ('LLA', N'Villarreal',       N'Villarreal'),
    -- Serie A
    ('SEA', N'Atalanta',         N'Atalanta'),
    ('SEA', N'Bologna',          N'Bologna'),
    ('SEA', N'Cagliari',         N'Cagliari'),
    ('SEA', N'Como',             N'Como'),
    ('SEA', N'Cremonese',        N'Cremonese'),
    ('SEA', N'Empoli',           N'Empoli'),
    ('SEA', N'Fiorentina',       N'Fiorentina'),
    ('SEA', N'Frosinone',        N'Frosinone'),
    ('SEA', N'Genoa',            N'Genoa'),
    ('SEA', N'Inter',            N'Inter Milan'),
    ('SEA', N'Juventus',         N'Juventus'),
    ('SEA', N'Lazio',            N'Lazio'),
    ('SEA', N'Lecce',            N'Lecce'),
    ('SEA', N'Milan',            N'AC Milan'),
    ('SEA', N'Monza',            N'Monza'),
    ('SEA', N'Napoli',           N'Napoli'),
    ('SEA', N'Parma',            N'Parma'),
    ('SEA', N'Roma',             N'AS Roma'),
    ('SEA', N'Salernitana',      N'Salernitana'),
    ('SEA', N'Sampdoria',        N'Sampdoria'),
    ('SEA', N'Sassuolo',         N'Sassuolo'),
    ('SEA', N'Spezia',           N'Spezia'),
    ('SEA', N'Torino',           N'Torino'),
    ('SEA', N'Udinese',          N'Udinese'),
    ('SEA', N'Venezia',          N'Venezia'),
    ('SEA', N'Verona',           N'Hellas Verona'),
    -- Bundesliga
    ('BUN', N'Augsburg',         N'Augsburg'),
    ('BUN', N'Bayern Munich',    N'Bayern Munich'),
    ('BUN', N'Bochum',           N'VfL Bochum'),
    ('BUN', N'Darmstadt',        N'Darmstadt'),
    ('BUN', N'Dortmund',         N'Borussia Dortmund'),
    ('BUN', N'Ein Frankfurt',    N'Eintracht Frankfurt'),
    ('BUN', N'FC Koln',          N'FC Koln'),
    ('BUN', N'Freiburg',         N'Freiburg'),
    ('BUN', N'Heidenheim',       N'Heidenheim'),
    ('BUN', N'Hertha',           N'Hertha Berlin'),
    ('BUN', N'Hoffenheim',       N'Hoffenheim'),
    ('BUN', N'Holstein Kiel',    N'Holstein Kiel'),
    ('BUN', N'Leverkusen',       N'Bayer Leverkusen'),
    ('BUN', N'M''gladbach',      N'Borussia Monchengladbach'),
    ('BUN', N'Mainz',            N'Mainz'),
    ('BUN', N'RB Leipzig',       N'RB Leipzig'),
    ('BUN', N'Schalke 04',       N'Schalke 04'),
    ('BUN', N'St Pauli',         N'St Pauli'),
    ('BUN', N'Stuttgart',        N'Stuttgart'),
    ('BUN', N'Union Berlin',     N'Union Berlin'),
    ('BUN', N'Werder Bremen',    N'Werder Bremen'),
    ('BUN', N'Wolfsburg',        N'Wolfsburg'),
    -- Ligue 1
    ('LI1', N'Ajaccio',          N'Ajaccio'),
    ('LI1', N'Angers',           N'Angers'),
    ('LI1', N'Auxerre',          N'Auxerre'),
    ('LI1', N'Brest',            N'Brest'),
    ('LI1', N'Clermont',         N'Clermont'),
    ('LI1', N'Le Havre',         N'Le Havre'),
    ('LI1', N'Lens',             N'Lens'),
    ('LI1', N'Lille',            N'Lille'),
    ('LI1', N'Lorient',          N'Lorient'),
    ('LI1', N'Lyon',             N'Lyon'),
    ('LI1', N'Marseille',        N'Marseille'),
    ('LI1', N'Metz',             N'Metz'),
    ('LI1', N'Monaco',           N'Monaco'),
    ('LI1', N'Montpellier',      N'Montpellier'),
    ('LI1', N'Nantes',           N'Nantes'),
    ('LI1', N'Nice',             N'Nice'),
    ('LI1', N'Paris SG',         N'Paris Saint-Germain'),
    ('LI1', N'Reims',            N'Reims'),
    ('LI1', N'Rennes',           N'Rennes'),
    ('LI1', N'St Etienne',       N'Saint-Etienne'),
    ('LI1', N'Strasbourg',       N'Strasbourg'),
    ('LI1', N'Toulouse',         N'Toulouse'),
    ('LI1', N'Troyes',           N'Troyes');
GO

SELECT 'business_parameter' AS table_name, COUNT(*) AS row_count FROM cfg.business_parameter
UNION ALL SELECT 'league',        COUNT(*) FROM cfg.league
UNION ALL SELECT 'source_file',   COUNT(*) FROM cfg.source_file
UNION ALL SELECT 'league_season', COUNT(*) FROM cfg.league_season
UNION ALL SELECT 'team_alias',    COUNT(*) FROM cfg.team_alias;
GO
