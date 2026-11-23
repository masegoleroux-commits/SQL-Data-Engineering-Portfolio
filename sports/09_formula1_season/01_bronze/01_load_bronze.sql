/* =============================================================================
   01_load_bronze.sql
   Bronze layer: each file loaded as delivered. Every column is text, so a
   bad value can never stop the load; problems are found and handled in
   silver, where they can be counted and explained.

   The folder comes from the SQLCMD variable DataPath set in run_all.sql.
   SQL Server reads the files with its own service account, so that account
   needs read access to the folder.
============================================================================= */

USE Formula1;
GO

DROP TABLE IF EXISTS bronze.calendar;
CREATE TABLE bronze.calendar (
    round                        NVARCHAR(200) NULL,
    race_date                    NVARCHAR(200) NULL,
    gp_name                      NVARCHAR(200) NULL,
    country                      NVARCHAR(200) NULL,
    city                         NVARCHAR(200) NULL,
    circuit_name                 NVARCHAR(200) NULL,
    first_gp                     NVARCHAR(200) NULL,
    number_of_laps               NVARCHAR(200) NULL,
    circuit_length_km            NVARCHAR(200) NULL,
    race_distance_km             NVARCHAR(200) NULL,
    lap_record                   NVARCHAR(200) NULL,
    record_owner                 NVARCHAR(200) NULL,
    record_year                  NVARCHAR(200) NULL,
    turns                        NVARCHAR(200) NULL,
    drs_zones                    NVARCHAR(200) NULL
);

BULK INSERT bronze.calendar
FROM '$(DataPath)\calendar.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

DROP TABLE IF EXISTS bronze.teams;
CREATE TABLE bronze.teams (
    team                         NVARCHAR(200) NULL,
    full_team_name               NVARCHAR(200) NULL,
    base                         NVARCHAR(200) NULL,
    team_chief                   NVARCHAR(200) NULL,
    technical_chief              NVARCHAR(200) NULL,
    chassis                      NVARCHAR(200) NULL,
    power_unit                   NVARCHAR(200) NULL,
    first_team_entry             NVARCHAR(200) NULL,
    world_championships          NVARCHAR(200) NULL,
    highest_race_finish          NVARCHAR(200) NULL,
    pole_positions               NVARCHAR(200) NULL,
    fastest_laps                 NVARCHAR(200) NULL
);

BULK INSERT bronze.teams
FROM '$(DataPath)\teams.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

DROP TABLE IF EXISTS bronze.drivers;
CREATE TABLE bronze.drivers (
    driver                       NVARCHAR(200) NULL,
    abbreviation                 NVARCHAR(200) NULL,
    no                           NVARCHAR(200) NULL,
    team                         NVARCHAR(200) NULL,
    country                      NVARCHAR(200) NULL,
    podiums                      NVARCHAR(200) NULL,
    points                       NVARCHAR(200) NULL,
    grands_prix_entered          NVARCHAR(200) NULL,
    world_championships          NVARCHAR(200) NULL,
    highest_race_finish          NVARCHAR(200) NULL,
    highest_grid_position        NVARCHAR(200) NULL,
    date_of_birth                NVARCHAR(200) NULL,
    place_of_birth               NVARCHAR(200) NULL
);

BULK INSERT bronze.drivers
FROM '$(DataPath)\drivers.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

DROP TABLE IF EXISTS bronze.qualifying_results;
CREATE TABLE bronze.qualifying_results (
    track                        NVARCHAR(200) NULL,
    position                     NVARCHAR(200) NULL,
    no                           NVARCHAR(200) NULL,
    driver                       NVARCHAR(200) NULL,
    team                         NVARCHAR(200) NULL,
    q1                           NVARCHAR(200) NULL,
    q2                           NVARCHAR(200) NULL,
    q3                           NVARCHAR(200) NULL,
    laps                         NVARCHAR(200) NULL
);

BULK INSERT bronze.qualifying_results
FROM '$(DataPath)\qualifying_results.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

DROP TABLE IF EXISTS bronze.sprint_results;
CREATE TABLE bronze.sprint_results (
    track                        NVARCHAR(200) NULL,
    position                     NVARCHAR(200) NULL,
    no                           NVARCHAR(200) NULL,
    driver                       NVARCHAR(200) NULL,
    team                         NVARCHAR(200) NULL,
    starting_grid                NVARCHAR(200) NULL,
    laps                         NVARCHAR(200) NULL,
    time_retired                 NVARCHAR(200) NULL,
    points                       NVARCHAR(200) NULL
);

BULK INSERT bronze.sprint_results
FROM '$(DataPath)\sprint_results.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

DROP TABLE IF EXISTS bronze.race_results;
CREATE TABLE bronze.race_results (
    track                        NVARCHAR(200) NULL,
    position                     NVARCHAR(200) NULL,
    no                           NVARCHAR(200) NULL,
    driver                       NVARCHAR(200) NULL,
    team                         NVARCHAR(200) NULL,
    starting_grid                NVARCHAR(200) NULL,
    laps                         NVARCHAR(200) NULL,
    time_retired                 NVARCHAR(200) NULL,
    points                       NVARCHAR(200) NULL,
    set_fastest_lap              NVARCHAR(200) NULL,
    fastest_lap_time             NVARCHAR(200) NULL
);

BULK INSERT bronze.race_results
FROM '$(DataPath)\race_results.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'calendar', COUNT(*) FROM bronze.calendar UNION ALL
SELECT 'bronze', 'teams', COUNT(*) FROM bronze.teams UNION ALL
SELECT 'bronze', 'drivers', COUNT(*) FROM bronze.drivers UNION ALL
SELECT 'bronze', 'qualifying_results', COUNT(*) FROM bronze.qualifying_results UNION ALL
SELECT 'bronze', 'sprint_results', COUNT(*) FROM bronze.sprint_results UNION ALL
SELECT 'bronze', 'race_results', COUNT(*) FROM bronze.race_results;
GO
