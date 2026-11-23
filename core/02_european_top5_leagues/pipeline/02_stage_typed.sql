/* =============================================================================
   02_stage_typed.sql
   Stage 2: convert the latest delivery of each file into typed columns.

   For every column:
     1. strip carriage returns, trim spaces, turn '' into NULL
     2. TRY_CONVERT to the target type (returns NULL instead of failing)
     3. if a value was present but did not convert, count it in type_errors

   Dates are read as ISO (yyyy-mm-dd) first and dd/mm/yyyy second, because
   older football-data.co.uk files use the second format.
   League and season come from cfg.source_file, not from the rows.
============================================================================= */

USE EuroLeagues;
GO

SET NOCOUNT ON;

TRUNCATE TABLE stg.match;

WITH latest AS (
    SELECT file_name, MAX(load_id) AS load_id
    FROM raw.load_log
    GROUP BY file_name
),
txt AS (
    -- step 1: clean text
    SELECT r.load_id, r.file_name, r.source_row_no, f.league_code, f.season_start_year,
           CASE WHEN CHARINDEX(CHAR(13), CONCAT(r.[Date], r.AR)) > 0 THEN 1 ELSE 0 END AS had_cr,
           NULLIF(LTRIM(RTRIM(REPLACE(r.[Date],   CHAR(13), ''))), '') AS d,
           NULLIF(LTRIM(RTRIM(REPLACE(r.HomeTeam, CHAR(13), ''))), '') AS home,
           NULLIF(LTRIM(RTRIM(REPLACE(r.AwayTeam, CHAR(13), ''))), '') AS away,
           NULLIF(LTRIM(RTRIM(REPLACE(r.FTHG, CHAR(13), ''))), '') AS fthg,
           NULLIF(LTRIM(RTRIM(REPLACE(r.FTAG, CHAR(13), ''))), '') AS ftag,
           NULLIF(LTRIM(RTRIM(REPLACE(r.FTR,  CHAR(13), ''))), '') AS ftr,
           NULLIF(LTRIM(RTRIM(REPLACE(r.HTHG, CHAR(13), ''))), '') AS hthg,
           NULLIF(LTRIM(RTRIM(REPLACE(r.HTAG, CHAR(13), ''))), '') AS htag,
           NULLIF(LTRIM(RTRIM(REPLACE(r.HTR,  CHAR(13), ''))), '') AS htr,
           NULLIF(LTRIM(RTRIM(REPLACE(r.Referee, CHAR(13), ''))), '') AS referee,
           NULLIF(LTRIM(RTRIM(REPLACE(r.HS,   CHAR(13), ''))), '') AS hs,
           NULLIF(LTRIM(RTRIM(REPLACE(r.[AS], CHAR(13), ''))), '') AS as_,
           NULLIF(LTRIM(RTRIM(REPLACE(r.HST,  CHAR(13), ''))), '') AS hst,
           NULLIF(LTRIM(RTRIM(REPLACE(r.AST,  CHAR(13), ''))), '') AS ast,
           NULLIF(LTRIM(RTRIM(REPLACE(r.HF,   CHAR(13), ''))), '') AS hf,
           NULLIF(LTRIM(RTRIM(REPLACE(r.AF,   CHAR(13), ''))), '') AS af,
           NULLIF(LTRIM(RTRIM(REPLACE(r.HC,   CHAR(13), ''))), '') AS hc,
           NULLIF(LTRIM(RTRIM(REPLACE(r.AC,   CHAR(13), ''))), '') AS ac,
           NULLIF(LTRIM(RTRIM(REPLACE(r.HY,   CHAR(13), ''))), '') AS hy,
           NULLIF(LTRIM(RTRIM(REPLACE(r.AY,   CHAR(13), ''))), '') AS ay,
           NULLIF(LTRIM(RTRIM(REPLACE(r.HR,   CHAR(13), ''))), '') AS hr,
           NULLIF(LTRIM(RTRIM(REPLACE(r.AR,   CHAR(13), ''))), '') AS ar
    FROM raw.match AS r
    INNER JOIN latest AS l
        ON  l.file_name = r.file_name
        AND l.load_id   = r.load_id
    INNER JOIN cfg.source_file AS f
        ON  f.file_name = r.file_name
),
typed AS (
    -- step 2: convert
    SELECT t.*,
           COALESCE(TRY_CONVERT(DATE, t.d, 23), TRY_CONVERT(DATE, t.d, 103)) AS match_date,
           TRY_CONVERT(TINYINT, t.fthg) AS ft_home_goals, TRY_CONVERT(TINYINT, t.ftag) AS ft_away_goals,
           CASE WHEN t.ftr IN ('H', 'D', 'A') THEN t.ftr END AS ft_result,
           TRY_CONVERT(TINYINT, t.hthg) AS ht_home_goals, TRY_CONVERT(TINYINT, t.htag) AS ht_away_goals,
           CASE WHEN t.htr IN ('H', 'D', 'A') THEN t.htr END AS ht_result,
           TRY_CONVERT(TINYINT, t.hs)  AS home_shots,  TRY_CONVERT(TINYINT, t.as_) AS away_shots,
           TRY_CONVERT(TINYINT, t.hst) AS home_sot,    TRY_CONVERT(TINYINT, t.ast) AS away_sot,
           TRY_CONVERT(TINYINT, t.hf)  AS home_fouls,  TRY_CONVERT(TINYINT, t.af)  AS away_fouls,
           TRY_CONVERT(TINYINT, t.hc)  AS home_corners, TRY_CONVERT(TINYINT, t.ac) AS away_corners,
           TRY_CONVERT(TINYINT, t.hy)  AS home_yellows, TRY_CONVERT(TINYINT, t.ay) AS away_yellows,
           TRY_CONVERT(TINYINT, t.hr)  AS home_reds,   TRY_CONVERT(TINYINT, t.ar)  AS away_reds
    FROM txt AS t
)
INSERT INTO stg.match
    (load_id, file_name, source_row_no, league_code, season_start_year, match_date,
     home_team_src, away_team_src, ft_home_goals, ft_away_goals, ft_result,
     ht_home_goals, ht_away_goals, ht_result, referee,
     home_shots, away_shots, home_shots_on_target, away_shots_on_target,
     home_fouls, away_fouls, home_corners, away_corners,
     home_yellows, away_yellows, home_reds, away_reds,
     type_errors, had_carriage_return)
SELECT
    load_id, file_name, source_row_no, league_code, season_start_year, match_date,
    home, away, ft_home_goals, ft_away_goals, ft_result,
    ht_home_goals, ht_away_goals, ht_result, referee,
    home_shots, away_shots, home_sot, away_sot,
    home_fouls, away_fouls, home_corners, away_corners,
    home_yellows, away_yellows, home_reds, away_reds,
    -- step 3: count values that were present but did not convert
      CASE WHEN d    IS NOT NULL AND match_date    IS NULL THEN 1 ELSE 0 END
    + CASE WHEN fthg IS NOT NULL AND ft_home_goals IS NULL THEN 1 ELSE 0 END
    + CASE WHEN ftag IS NOT NULL AND ft_away_goals IS NULL THEN 1 ELSE 0 END
    + CASE WHEN ftr  IS NOT NULL AND ft_result     IS NULL THEN 1 ELSE 0 END
    + CASE WHEN hthg IS NOT NULL AND ht_home_goals IS NULL THEN 1 ELSE 0 END
    + CASE WHEN htag IS NOT NULL AND ht_away_goals IS NULL THEN 1 ELSE 0 END
    + CASE WHEN htr  IS NOT NULL AND ht_result     IS NULL THEN 1 ELSE 0 END
    + CASE WHEN hs   IS NOT NULL AND home_shots    IS NULL THEN 1 ELSE 0 END
    + CASE WHEN as_  IS NOT NULL AND away_shots    IS NULL THEN 1 ELSE 0 END
    + CASE WHEN hst  IS NOT NULL AND home_sot      IS NULL THEN 1 ELSE 0 END
    + CASE WHEN ast  IS NOT NULL AND away_sot      IS NULL THEN 1 ELSE 0 END
    + CASE WHEN hf   IS NOT NULL AND home_fouls    IS NULL THEN 1 ELSE 0 END
    + CASE WHEN af   IS NOT NULL AND away_fouls    IS NULL THEN 1 ELSE 0 END
    + CASE WHEN hc   IS NOT NULL AND home_corners  IS NULL THEN 1 ELSE 0 END
    + CASE WHEN ac   IS NOT NULL AND away_corners  IS NULL THEN 1 ELSE 0 END
    + CASE WHEN hy   IS NOT NULL AND home_yellows  IS NULL THEN 1 ELSE 0 END
    + CASE WHEN ay   IS NOT NULL AND away_yellows  IS NULL THEN 1 ELSE 0 END
    + CASE WHEN hr   IS NOT NULL AND home_reds     IS NULL THEN 1 ELSE 0 END
    + CASE WHEN ar   IS NOT NULL AND away_reds     IS NULL THEN 1 ELSE 0 END,
    had_cr
FROM typed;

SELECT COUNT(*)                                        AS staged_rows,
       SUM(CASE WHEN type_errors > 0 THEN 1 ELSE 0 END) AS rows_with_type_errors,
       SUM(CAST(had_carriage_return AS INT))            AS rows_with_carriage_return,
       SUM(CASE WHEN referee IS NULL THEN 1 ELSE 0 END)  AS rows_without_referee,
       SUM(CASE WHEN home_shots IS NULL THEN 1 ELSE 0 END) AS rows_without_shots
FROM stg.match;
GO
