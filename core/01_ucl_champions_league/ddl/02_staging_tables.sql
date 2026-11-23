/* =============================================================================
   02_staging_tables.sql
   Landing tables for the four raw CSV extracts in data/raw/.

   Staging mirrors the source files column for column, including the source
   spelling (balls_recoverd, cross_complted). Names are corrected on the way
   into the dimensional model, not here, so a reload never has to remap columns.

   Columns are nullable on purpose: staging accepts whatever the file contains
   and the checks in tests/ decide whether it is fit to load.

   Grain (all four tables): one row per player per club, UCL season 2021/22.
============================================================================= */

USE UCL;
GO

DROP TABLE IF EXISTS dbo.stg_attacking;
CREATE TABLE dbo.stg_attacking (
    serial              VARCHAR(10)     NULL,
    player_name         NVARCHAR(100)   NULL,
    club                NVARCHAR(100)   NULL,
    position            NVARCHAR(20)    NULL,
    assists             INT             NULL,
    corner_taken        INT             NULL,
    offsides            INT             NULL,
    dribbles            INT             NULL,
    match_played        INT             NULL
);
GO

DROP TABLE IF EXISTS dbo.stg_defending;
CREATE TABLE dbo.stg_defending (
    serial              VARCHAR(10)     NULL,
    player_name         NVARCHAR(100)   NULL,
    club                NVARCHAR(100)   NULL,
    position            NVARCHAR(20)    NULL,
    balls_recoverd      INT             NULL,
    tackles             INT             NULL,
    t_won               INT             NULL,
    t_lost              INT             NULL,
    clearance_attempted INT             NULL,
    match_played        INT             NULL
);
GO

DROP TABLE IF EXISTS dbo.stg_distribution;
CREATE TABLE dbo.stg_distribution (
    serial              VARCHAR(10)     NULL,
    player_name         NVARCHAR(100)   NULL,
    club                NVARCHAR(100)   NULL,
    position            NVARCHAR(20)    NULL,
    pass_accuracy       DECIMAL(5, 1)   NULL,
    pass_attempted      INT             NULL,
    pass_completed      INT             NULL,
    cross_accuracy      DECIMAL(5, 1)   NULL,
    cross_attempted     INT             NULL,
    cross_complted      INT             NULL,
    freekicks_taken     INT             NULL,
    match_played        INT             NULL
);
GO

DROP TABLE IF EXISTS dbo.stg_disciplinary;
CREATE TABLE dbo.stg_disciplinary (
    serial              VARCHAR(10)     NULL,
    player_name         NVARCHAR(100)   NULL,
    club                NVARCHAR(100)   NULL,
    position            NVARCHAR(20)    NULL,
    fouls_committed     INT             NULL,
    fouls_suffered      INT             NULL,
    red                 INT             NULL,
    yellow              INT             NULL,
    minutes_played      INT             NULL,
    match_played        INT             NULL
);
GO
