/* =============================================================================
   01_load_bronze.sql
   Bronze layer: each CSV loaded as delivered. Every column is text, so a
   bad value can never stop the load; problems are found and handled in
   silver, where they can be counted and explained.

   The file path comes from the SQLCMD variable DataPath set in run_all.sql.
   SQL Server reads the files with its own service account, so the folder
   must be readable by that account (see the README).
============================================================================= */

USE WorldCup;
GO

DROP TABLE IF EXISTS bronze.tournaments;
CREATE TABLE bronze.tournaments (
    key_id                       NVARCHAR(200) NULL,
    tournament_id                NVARCHAR(200) NULL,
    tournament_name              NVARCHAR(200) NULL,
    year                         NVARCHAR(200) NULL,
    start_date                   NVARCHAR(200) NULL,
    end_date                     NVARCHAR(200) NULL,
    host_country                 NVARCHAR(200) NULL,
    winner                       NVARCHAR(200) NULL,
    host_won                     NVARCHAR(200) NULL,
    count_teams                  NVARCHAR(200) NULL,
    group_stage                  NVARCHAR(200) NULL,
    second_group_stage           NVARCHAR(200) NULL,
    final_round                  NVARCHAR(200) NULL,
    round_of_16                  NVARCHAR(200) NULL,
    quarter_finals               NVARCHAR(200) NULL,
    semi_finals                  NVARCHAR(200) NULL,
    third_place_match            NVARCHAR(200) NULL,
    final                        NVARCHAR(200) NULL
);

BULK INSERT bronze.tournaments
FROM '$(DataPath)\tournaments.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'tournaments', COUNT(*) FROM bronze.tournaments;
GO

DROP TABLE IF EXISTS bronze.teams;
CREATE TABLE bronze.teams (
    key_id                       NVARCHAR(200) NULL,
    team_id                      NVARCHAR(200) NULL,
    team_name                    NVARCHAR(200) NULL,
    team_code                    NVARCHAR(200) NULL,
    mens_team                    NVARCHAR(200) NULL,
    womens_team                  NVARCHAR(200) NULL,
    federation_name              NVARCHAR(200) NULL,
    region_name                  NVARCHAR(200) NULL,
    confederation_id             NVARCHAR(200) NULL,
    confederation_name           NVARCHAR(200) NULL,
    confederation_code           NVARCHAR(200) NULL,
    mens_team_wikipedia_link     NVARCHAR(1000) NULL,
    womens_team_wikipedia_link   NVARCHAR(1000) NULL,
    federation_wikipedia_link    NVARCHAR(1000) NULL
);

BULK INSERT bronze.teams
FROM '$(DataPath)\teams.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'teams', COUNT(*) FROM bronze.teams;
GO

DROP TABLE IF EXISTS bronze.matches;
CREATE TABLE bronze.matches (
    key_id                       NVARCHAR(200) NULL,
    tournament_id                NVARCHAR(200) NULL,
    tournament_name              NVARCHAR(200) NULL,
    match_id                     NVARCHAR(200) NULL,
    match_name                   NVARCHAR(200) NULL,
    stage_name                   NVARCHAR(200) NULL,
    group_name                   NVARCHAR(200) NULL,
    group_stage                  NVARCHAR(200) NULL,
    knockout_stage               NVARCHAR(200) NULL,
    replayed                     NVARCHAR(200) NULL,
    replay                       NVARCHAR(200) NULL,
    match_date                   NVARCHAR(200) NULL,
    match_time                   NVARCHAR(200) NULL,
    stadium_id                   NVARCHAR(200) NULL,
    stadium_name                 NVARCHAR(200) NULL,
    city_name                    NVARCHAR(200) NULL,
    country_name                 NVARCHAR(200) NULL,
    home_team_id                 NVARCHAR(200) NULL,
    home_team_name               NVARCHAR(200) NULL,
    home_team_code               NVARCHAR(200) NULL,
    away_team_id                 NVARCHAR(200) NULL,
    away_team_name               NVARCHAR(200) NULL,
    away_team_code               NVARCHAR(200) NULL,
    score                        NVARCHAR(200) NULL,
    home_team_score              NVARCHAR(200) NULL,
    away_team_score              NVARCHAR(200) NULL,
    home_team_score_margin       NVARCHAR(200) NULL,
    away_team_score_margin       NVARCHAR(200) NULL,
    extra_time                   NVARCHAR(200) NULL,
    penalty_shootout             NVARCHAR(200) NULL,
    score_penalties              NVARCHAR(200) NULL,
    home_team_score_penalties    NVARCHAR(200) NULL,
    away_team_score_penalties    NVARCHAR(200) NULL,
    result                       NVARCHAR(200) NULL,
    home_team_win                NVARCHAR(200) NULL,
    away_team_win                NVARCHAR(200) NULL,
    draw                         NVARCHAR(200) NULL
);

BULK INSERT bronze.matches
FROM '$(DataPath)\matches.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'matches', COUNT(*) FROM bronze.matches;
GO

DROP TABLE IF EXISTS bronze.goals;
CREATE TABLE bronze.goals (
    key_id                       NVARCHAR(200) NULL,
    goal_id                      NVARCHAR(200) NULL,
    tournament_id                NVARCHAR(200) NULL,
    tournament_name              NVARCHAR(200) NULL,
    match_id                     NVARCHAR(200) NULL,
    match_name                   NVARCHAR(200) NULL,
    match_date                   NVARCHAR(200) NULL,
    stage_name                   NVARCHAR(200) NULL,
    group_name                   NVARCHAR(200) NULL,
    team_id                      NVARCHAR(200) NULL,
    team_name                    NVARCHAR(200) NULL,
    team_code                    NVARCHAR(200) NULL,
    home_team                    NVARCHAR(200) NULL,
    away_team                    NVARCHAR(200) NULL,
    player_id                    NVARCHAR(200) NULL,
    family_name                  NVARCHAR(200) NULL,
    given_name                   NVARCHAR(200) NULL,
    shirt_number                 NVARCHAR(200) NULL,
    player_team_id               NVARCHAR(200) NULL,
    player_team_name             NVARCHAR(200) NULL,
    player_team_code             NVARCHAR(200) NULL,
    minute_label                 NVARCHAR(200) NULL,
    minute_regulation            NVARCHAR(200) NULL,
    minute_stoppage              NVARCHAR(200) NULL,
    match_period                 NVARCHAR(200) NULL,
    own_goal                     NVARCHAR(200) NULL,
    penalty                      NVARCHAR(200) NULL
);

BULK INSERT bronze.goals
FROM '$(DataPath)\goals.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'goals', COUNT(*) FROM bronze.goals;
GO

DROP TABLE IF EXISTS bronze.bookings;
CREATE TABLE bronze.bookings (
    key_id                       NVARCHAR(200) NULL,
    booking_id                   NVARCHAR(200) NULL,
    tournament_id                NVARCHAR(200) NULL,
    tournament_name              NVARCHAR(200) NULL,
    match_id                     NVARCHAR(200) NULL,
    match_name                   NVARCHAR(200) NULL,
    match_date                   NVARCHAR(200) NULL,
    stage_name                   NVARCHAR(200) NULL,
    group_name                   NVARCHAR(200) NULL,
    team_id                      NVARCHAR(200) NULL,
    team_name                    NVARCHAR(200) NULL,
    team_code                    NVARCHAR(200) NULL,
    home_team                    NVARCHAR(200) NULL,
    away_team                    NVARCHAR(200) NULL,
    player_id                    NVARCHAR(200) NULL,
    family_name                  NVARCHAR(200) NULL,
    given_name                   NVARCHAR(200) NULL,
    shirt_number                 NVARCHAR(200) NULL,
    minute_label                 NVARCHAR(200) NULL,
    minute_regulation            NVARCHAR(200) NULL,
    minute_stoppage              NVARCHAR(200) NULL,
    match_period                 NVARCHAR(200) NULL,
    yellow_card                  NVARCHAR(200) NULL,
    red_card                     NVARCHAR(200) NULL,
    second_yellow_card           NVARCHAR(200) NULL,
    sending_off                  NVARCHAR(200) NULL
);

BULK INSERT bronze.bookings
FROM '$(DataPath)\bookings.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'bookings', COUNT(*) FROM bronze.bookings;
GO

DROP TABLE IF EXISTS bronze.players;
CREATE TABLE bronze.players (
    key_id                       NVARCHAR(200) NULL,
    player_id                    NVARCHAR(200) NULL,
    family_name                  NVARCHAR(200) NULL,
    given_name                   NVARCHAR(200) NULL,
    birth_date                   NVARCHAR(200) NULL,
    female                       NVARCHAR(200) NULL,
    goal_keeper                  NVARCHAR(200) NULL,
    defender                     NVARCHAR(200) NULL,
    midfielder                   NVARCHAR(200) NULL,
    forward                      NVARCHAR(200) NULL,
    count_tournaments            NVARCHAR(200) NULL,
    list_tournaments             NVARCHAR(1000) NULL,
    player_wikipedia_link        NVARCHAR(1000) NULL
);

BULK INSERT bronze.players
FROM '$(DataPath)\players.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'players', COUNT(*) FROM bronze.players;
GO

DROP TABLE IF EXISTS bronze.player_appearances;
CREATE TABLE bronze.player_appearances (
    key_id                       NVARCHAR(200) NULL,
    tournament_id                NVARCHAR(200) NULL,
    tournament_name              NVARCHAR(200) NULL,
    match_id                     NVARCHAR(200) NULL,
    match_name                   NVARCHAR(200) NULL,
    match_date                   NVARCHAR(200) NULL,
    stage_name                   NVARCHAR(200) NULL,
    group_name                   NVARCHAR(200) NULL,
    team_id                      NVARCHAR(200) NULL,
    team_name                    NVARCHAR(200) NULL,
    team_code                    NVARCHAR(200) NULL,
    home_team                    NVARCHAR(200) NULL,
    away_team                    NVARCHAR(200) NULL,
    player_id                    NVARCHAR(200) NULL,
    family_name                  NVARCHAR(200) NULL,
    given_name                   NVARCHAR(200) NULL,
    shirt_number                 NVARCHAR(200) NULL,
    position_name                NVARCHAR(200) NULL,
    position_code                NVARCHAR(200) NULL,
    starter                      NVARCHAR(200) NULL,
    substitute                   NVARCHAR(200) NULL
);

BULK INSERT bronze.player_appearances
FROM '$(DataPath)\player_appearances.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'player_appearances', COUNT(*) FROM bronze.player_appearances;
GO

DROP TABLE IF EXISTS bronze.penalty_kicks;
CREATE TABLE bronze.penalty_kicks (
    key_id                       NVARCHAR(200) NULL,
    penalty_kick_id              NVARCHAR(200) NULL,
    tournament_id                NVARCHAR(200) NULL,
    tournament_name              NVARCHAR(200) NULL,
    match_id                     NVARCHAR(200) NULL,
    match_name                   NVARCHAR(200) NULL,
    match_date                   NVARCHAR(200) NULL,
    stage_name                   NVARCHAR(200) NULL,
    group_name                   NVARCHAR(200) NULL,
    team_id                      NVARCHAR(200) NULL,
    team_name                    NVARCHAR(200) NULL,
    team_code                    NVARCHAR(200) NULL,
    home_team                    NVARCHAR(200) NULL,
    away_team                    NVARCHAR(200) NULL,
    player_id                    NVARCHAR(200) NULL,
    family_name                  NVARCHAR(200) NULL,
    given_name                   NVARCHAR(200) NULL,
    shirt_number                 NVARCHAR(200) NULL,
    converted                    NVARCHAR(200) NULL
);

BULK INSERT bronze.penalty_kicks
FROM '$(DataPath)\penalty_kicks.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'penalty_kicks', COUNT(*) FROM bronze.penalty_kicks;
GO

SELECT layer, table_name, row_count
FROM ops.load_log
WHERE layer = 'bronze'
ORDER BY table_name;
GO
