/* =============================================================================
   03_load_facts.sql
   Reloads the four fact tables from staging.

   Each source row is resolved to its surrogate keys with INNER JOINs to the
   dimensions. Because 02_load_dimensions.sql runs first, every staging row has
   a match; tests/03_reconciliation.sql proves no rows were dropped.

   The facts are small (< 700 rows each), so a full reload inside one
   transaction is simpler and safer than an incremental merge. If anything
   fails, the previous load stays in place.

   Source correction: in disciplinary.csv the red and yellow columns are
   swapped (492 "red" cards against 25 "yellow" across the season, and no
   player can collect four reds in 13 games). They are mapped the right way
   round below. See docs/data_quality.md.
============================================================================= */

USE UCL;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

    /* ---- fact_attacking -------------------------------------------------- */
    TRUNCATE TABLE dbo.fact_attacking;

    INSERT INTO dbo.fact_attacking
        (player_key, club_key, matches_played, assists, corners_taken, offsides, dribbles)
    SELECT
        p.player_key,
        c.club_key,
        s.match_played,
        s.assists,
        s.corner_taken,
        s.offsides,
        s.dribbles
    FROM dbo.stg_attacking AS s
    INNER JOIN dbo.dim_player AS p
        ON  p.player_name = LTRIM(RTRIM(s.player_name))
        AND p.club_name   = LTRIM(RTRIM(s.club))
    INNER JOIN dbo.dim_club AS c
        ON  c.club_name   = p.club_name;

    /* ---- fact_defending -------------------------------------------------- */
    TRUNCATE TABLE dbo.fact_defending;

    INSERT INTO dbo.fact_defending
        (player_key, club_key, matches_played, balls_recovered, tackles, tackles_won, tackles_lost, clearances_attempted)
    SELECT
        p.player_key,
        c.club_key,
        s.match_played,
        s.balls_recoverd,
        s.tackles,
        s.t_won,
        s.t_lost,
        s.clearance_attempted
    FROM dbo.stg_defending AS s
    INNER JOIN dbo.dim_player AS p
        ON  p.player_name = LTRIM(RTRIM(s.player_name))
        AND p.club_name   = LTRIM(RTRIM(s.club))
    INNER JOIN dbo.dim_club AS c
        ON  c.club_name   = p.club_name;

    /* ---- fact_distribution ----------------------------------------------- */
    TRUNCATE TABLE dbo.fact_distribution;

    INSERT INTO dbo.fact_distribution
        (player_key, club_key, matches_played, passes_attempted, passes_completed,
         crosses_attempted, crosses_completed, free_kicks_taken, pass_accuracy_src)
    SELECT
        p.player_key,
        c.club_key,
        s.match_played,
        s.pass_attempted,
        s.pass_completed,
        s.cross_attempted,
        s.cross_complted,
        s.freekicks_taken,
        s.pass_accuracy
    FROM dbo.stg_distribution AS s
    INNER JOIN dbo.dim_player AS p
        ON  p.player_name = LTRIM(RTRIM(s.player_name))
        AND p.club_name   = LTRIM(RTRIM(s.club))
    INNER JOIN dbo.dim_club AS c
        ON  c.club_name   = p.club_name;

    /* ---- fact_discipline ------------------------------------------------- */
    TRUNCATE TABLE dbo.fact_discipline;

    INSERT INTO dbo.fact_discipline
        (player_key, club_key, matches_played, minutes_played, fouls_committed, fouls_suffered, yellow_cards, red_cards)
    SELECT
        p.player_key,
        c.club_key,
        s.match_played,
        s.minutes_played,
        s.fouls_committed,
        s.fouls_suffered,
        s.red,              -- source "red" column holds yellow cards
        s.yellow            -- source "yellow" column holds red cards
    FROM dbo.stg_disciplinary AS s
    INNER JOIN dbo.dim_player AS p
        ON  p.player_name = LTRIM(RTRIM(s.player_name))
        AND p.club_name   = LTRIM(RTRIM(s.club))
    INNER JOIN dbo.dim_club AS c
        ON  c.club_name   = p.club_name;

COMMIT TRANSACTION;

SELECT 'fact_attacking'    AS table_name, COUNT(*) AS row_count FROM dbo.fact_attacking
UNION ALL
SELECT 'fact_defending',                  COUNT(*)              FROM dbo.fact_defending
UNION ALL
SELECT 'fact_distribution',               COUNT(*)              FROM dbo.fact_distribution
UNION ALL
SELECT 'fact_discipline',                 COUNT(*)              FROM dbo.fact_discipline;
GO
