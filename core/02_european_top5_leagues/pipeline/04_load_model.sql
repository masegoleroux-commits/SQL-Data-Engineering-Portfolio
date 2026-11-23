/* =============================================================================
   04_load_model.sql
   Stage 4: load the star schema from cln.match.

   The whole model is rebuilt inside one transaction. If any statement fails
   (for example a CHECK constraint), the previous model stays in place.
============================================================================= */

USE EuroLeagues;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @points_win  TINYINT = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'points_win'),
        @points_draw TINYINT = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'points_draw'),
        @first_day   DATE    = (SELECT MIN(match_date) FROM cln.match),
        @day_count   INT     = (SELECT DATEDIFF(DAY, MIN(match_date), MAX(match_date)) + 1 FROM cln.match);

BEGIN TRANSACTION;

    DELETE FROM dw.fact_team_match;
    DELETE FROM dw.fact_match;
    DELETE FROM dw.dim_date;
    DELETE FROM dw.dim_referee;
    DELETE FROM dw.dim_team;
    DELETE FROM dw.dim_season;
    DELETE FROM dw.dim_league;

    -- Restart surrogate keys at 1 on a reload. RESEED is only safe on a table
    -- that has held rows before (on a brand-new table it would start at 0).
    IF (SELECT last_value FROM sys.identity_columns WHERE object_id = OBJECT_ID(N'dw.dim_league')) IS NOT NULL
        DBCC CHECKIDENT ('dw.dim_league', RESEED, 0) WITH NO_INFOMSGS;
    IF (SELECT last_value FROM sys.identity_columns WHERE object_id = OBJECT_ID(N'dw.dim_team')) IS NOT NULL
        DBCC CHECKIDENT ('dw.dim_team', RESEED, 0) WITH NO_INFOMSGS;
    IF (SELECT last_value FROM sys.identity_columns WHERE object_id = OBJECT_ID(N'dw.dim_referee')) IS NOT NULL
        DBCC CHECKIDENT ('dw.dim_referee', RESEED, 0) WITH NO_INFOMSGS;

    /* ---- Dimensions ----------------------------------------------------- */
    INSERT INTO dw.dim_league (league_code, league_name, country)
    SELECT league_code, league_name, country
    FROM cfg.league
    ORDER BY league_code;

    INSERT INTO dw.dim_season (season_key, season_label)
    SELECT DISTINCT season_start_year,
           CONCAT(season_start_year, '/', RIGHT(CAST(season_start_year + 1 AS CHAR(4)), 2))
    FROM cln.match;

    INSERT INTO dw.dim_team (team_name, league_key)
    SELECT DISTINCT t.team_name, l.league_key
    FROM (SELECT league_code, home_team AS team_name FROM cln.match
          UNION
          SELECT league_code, away_team FROM cln.match) AS t
    INNER JOIN dw.dim_league AS l ON l.league_code = t.league_code;

    -- Unknown member with a fixed key of -1, then the real referees
    SET IDENTITY_INSERT dw.dim_referee ON;
    INSERT INTO dw.dim_referee (referee_key, referee_name) VALUES (-1, N'Not supplied');
    SET IDENTITY_INSERT dw.dim_referee OFF;

    INSERT INTO dw.dim_referee (referee_name)
    SELECT DISTINCT referee FROM cln.match WHERE referee IS NOT NULL;

    -- Calendar from the first to the last match date. The tally is just a
    -- list of numbers 0..n-1 built from a system view.
    WITH tally AS (
        SELECT TOP (@day_count)
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
        FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b
    )
    INSERT INTO dw.dim_date (date_key, full_date, day_name, is_weekend, month_number, month_name, calendar_year)
    SELECT CONVERT(INT, CONVERT(CHAR(8), d.full_date, 112)),
           d.full_date,
           DATENAME(WEEKDAY, d.full_date),
           -- ISO weekday (Mon = 1 ... Sun = 7) regardless of the server's DATEFIRST setting
           CASE WHEN (DATEPART(WEEKDAY, d.full_date) + @@DATEFIRST - 2) % 7 + 1 >= 6 THEN 1 ELSE 0 END,
           MONTH(d.full_date),
           DATENAME(MONTH, d.full_date),
           YEAR(d.full_date)
    FROM tally
    CROSS APPLY (SELECT DATEADD(DAY, tally.n, @first_day) AS full_date) AS d;

    /* ---- fact_match ----------------------------------------------------- */
    INSERT INTO dw.fact_match
        (match_key, date_key, league_key, season_key, home_team_key, away_team_key, referee_key,
         ft_home_goals, ft_away_goals, ft_result, ht_home_goals, ht_away_goals, ht_result,
         home_shots, away_shots, home_shots_on_target, away_shots_on_target,
         home_fouls, away_fouls, home_corners, away_corners,
         home_yellows, away_yellows, home_reds, away_reds, stats_complete)
    SELECT
        m.match_id,
        CONVERT(INT, CONVERT(CHAR(8), m.match_date, 112)),
        l.league_key,
        m.season_start_year,
        th.team_key,
        ta.team_key,
        COALESCE(r.referee_key, -1),
        m.ft_home_goals, m.ft_away_goals, m.ft_result, m.ht_home_goals, m.ht_away_goals, m.ht_result,
        m.home_shots, m.away_shots, m.home_shots_on_target, m.away_shots_on_target,
        m.home_fouls, m.away_fouls, m.home_corners, m.away_corners,
        m.home_yellows, m.away_yellows, m.home_reds, m.away_reds, m.stats_complete
    FROM cln.match AS m
    INNER JOIN dw.dim_league  AS l  ON l.league_code  = m.league_code
    INNER JOIN dw.dim_team    AS th ON th.team_name   = m.home_team
    INNER JOIN dw.dim_team    AS ta ON ta.team_name   = m.away_team
    LEFT  JOIN dw.dim_referee AS r  ON r.referee_name = m.referee;

    /* ---- fact_team_match: each match seen from both sides --------------- */
    -- CROSS APPLY (VALUES ...) turns one match row into two team rows
    -- without reading fact_match twice.
    INSERT INTO dw.fact_team_match
        (match_key, team_key, opponent_key, date_key, league_key, season_key, is_home,
         goals_for, goals_against, result, points, ht_goals_for, ht_goals_against,
         shots_for, shots_against, shots_on_target_for, shots_on_target_against,
         fouls, corners, yellows, reds, stats_complete)
    SELECT
        f.match_key, v.team_key, v.opponent_key, f.date_key, f.league_key, f.season_key, v.is_home,
        v.goals_for, v.goals_against,
        CASE WHEN v.goals_for > v.goals_against THEN 'W' WHEN v.goals_for < v.goals_against THEN 'L' ELSE 'D' END,
        CASE WHEN v.goals_for > v.goals_against THEN @points_win
             WHEN v.goals_for = v.goals_against THEN @points_draw ELSE 0 END,
        v.ht_for, v.ht_against, v.shots_for, v.shots_against, v.sot_for, v.sot_against,
        v.fouls, v.corners, v.yellows, v.reds, f.stats_complete
    FROM dw.fact_match AS f
    CROSS APPLY (VALUES
        (f.home_team_key, f.away_team_key, 1, f.ft_home_goals, f.ft_away_goals, f.ht_home_goals, f.ht_away_goals,
         f.home_shots, f.away_shots, f.home_shots_on_target, f.away_shots_on_target,
         f.home_fouls, f.home_corners, f.home_yellows, f.home_reds),
        (f.away_team_key, f.home_team_key, 0, f.ft_away_goals, f.ft_home_goals, f.ht_away_goals, f.ht_home_goals,
         f.away_shots, f.home_shots, f.away_shots_on_target, f.home_shots_on_target,
         f.away_fouls, f.away_corners, f.away_yellows, f.away_reds)
    ) AS v (team_key, opponent_key, is_home, goals_for, goals_against, ht_for, ht_against,
            shots_for, shots_against, sot_for, sot_against, fouls, corners, yellows, reds);

COMMIT TRANSACTION;

SELECT 'dim_league' AS table_name, COUNT(*) AS row_count FROM dw.dim_league
UNION ALL SELECT 'dim_season',      COUNT(*) FROM dw.dim_season
UNION ALL SELECT 'dim_team',        COUNT(*) FROM dw.dim_team
UNION ALL SELECT 'dim_referee',     COUNT(*) FROM dw.dim_referee
UNION ALL SELECT 'dim_date',        COUNT(*) FROM dw.dim_date
UNION ALL SELECT 'fact_match',      COUNT(*) FROM dw.fact_match
UNION ALL SELECT 'fact_team_match', COUNT(*) FROM dw.fact_team_match;
GO
