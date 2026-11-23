/* =============================================================================
   01_load_bronze.sql
   Bronze layer: each file loaded as delivered. Every column is text, so a
   bad value can never stop the load; problems are found and handled in
   silver, where they can be counted and explained.

   The folder comes from the SQLCMD variable DataPath set in run_all.sql.
   SQL Server reads the files with its own service account, so that account
   needs read access to the folder.
============================================================================= */

USE FantasyPoints;
GO

DROP TABLE IF EXISTS bronze.fpl_teams;
CREATE TABLE bronze.fpl_teams (
    code                         NVARCHAR(200) NULL,
    draw                         NVARCHAR(200) NULL,
    form                         NVARCHAR(200) NULL,
    id                           NVARCHAR(200) NULL,
    loss                         NVARCHAR(200) NULL,
    name                         NVARCHAR(200) NULL,
    played                       NVARCHAR(200) NULL,
    points                       NVARCHAR(200) NULL,
    position                     NVARCHAR(200) NULL,
    short_name                   NVARCHAR(200) NULL,
    strength                     NVARCHAR(200) NULL,
    team_division                NVARCHAR(200) NULL,
    unavailable                  NVARCHAR(200) NULL,
    win                          NVARCHAR(200) NULL,
    strength_overall_home        NVARCHAR(200) NULL,
    strength_overall_away        NVARCHAR(200) NULL,
    strength_attack_home         NVARCHAR(200) NULL,
    strength_attack_away         NVARCHAR(200) NULL,
    strength_defence_home        NVARCHAR(200) NULL,
    strength_defence_away        NVARCHAR(200) NULL,
    pulse_id                     NVARCHAR(200) NULL
);

BULK INSERT bronze.fpl_teams
FROM '$(DataPath)\fpl_teams.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

DROP TABLE IF EXISTS bronze.fpl_player_gameweeks;
CREATE TABLE bronze.fpl_player_gameweeks (
    name                         NVARCHAR(200) NULL,
    position                     NVARCHAR(200) NULL,
    team                         NVARCHAR(200) NULL,
    xp                           NVARCHAR(200) NULL,
    assists                      NVARCHAR(200) NULL,
    bonus                        NVARCHAR(200) NULL,
    bps                          NVARCHAR(200) NULL,
    clean_sheets                 NVARCHAR(200) NULL,
    creativity                   NVARCHAR(200) NULL,
    element                      NVARCHAR(200) NULL,
    expected_assists             NVARCHAR(200) NULL,
    expected_goal_involvements   NVARCHAR(200) NULL,
    expected_goals               NVARCHAR(200) NULL,
    expected_goals_conceded      NVARCHAR(200) NULL,
    fixture                      NVARCHAR(200) NULL,
    goals_conceded               NVARCHAR(200) NULL,
    goals_scored                 NVARCHAR(200) NULL,
    ict_index                    NVARCHAR(200) NULL,
    influence                    NVARCHAR(200) NULL,
    kickoff_time                 NVARCHAR(200) NULL,
    minutes                      NVARCHAR(200) NULL,
    opponent_team                NVARCHAR(200) NULL,
    own_goals                    NVARCHAR(200) NULL,
    penalties_missed             NVARCHAR(200) NULL,
    penalties_saved              NVARCHAR(200) NULL,
    red_cards                    NVARCHAR(200) NULL,
    round                        NVARCHAR(200) NULL,
    saves                        NVARCHAR(200) NULL,
    selected                     NVARCHAR(200) NULL,
    starts                       NVARCHAR(200) NULL,
    team_a_score                 NVARCHAR(200) NULL,
    team_h_score                 NVARCHAR(200) NULL,
    threat                       NVARCHAR(200) NULL,
    total_points                 NVARCHAR(200) NULL,
    transfers_balance            NVARCHAR(200) NULL,
    transfers_in                 NVARCHAR(200) NULL,
    transfers_out                NVARCHAR(200) NULL,
    value                        NVARCHAR(200) NULL,
    was_home                     NVARCHAR(200) NULL,
    yellow_cards                 NVARCHAR(200) NULL,
    gw                           NVARCHAR(200) NULL
);

BULK INSERT bronze.fpl_player_gameweeks
FROM '$(DataPath)\fpl_player_gameweeks.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, CODEPAGE = '65001', ROWTERMINATOR = '0x0a', TABLOCK);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'bronze', 'fpl_teams', COUNT(*) FROM bronze.fpl_teams UNION ALL
SELECT 'bronze', 'fpl_player_gameweeks', COUNT(*) FROM bronze.fpl_player_gameweeks;
GO
