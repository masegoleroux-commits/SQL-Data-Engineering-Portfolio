/* =============================================================================
   03_clean.sql
   Stage 3: standardise, validate and de-duplicate. Output: cln.match.

   Every step writes one line to cln.cleaning_log, so the journey from
   "rows delivered" to "rows trusted" is visible as numbers:

     START        rows arriving from staging
     STANDARDISE  team names mapped to one standard name per club
     QUARANTINE   rows that break a rule move to cln.match_issue, with reason
     FLAG         rows kept but marked (e.g. statistics missing)
     END          rows written to cln.match

   Quarantined rows are never deleted from raw or staging, so a fixed rule
   or a corrected file can be replayed.
============================================================================= */

USE EuroLeagues;
GO

SET NOCOUNT ON;

TRUNCATE TABLE cln.match;
TRUNCATE TABLE cln.match_issue;
TRUNCATE TABLE cln.cleaning_log;

DROP TABLE IF EXISTS #work;

DECLARE @rows_in INT, @affected INT, @step TINYINT = 0;

/* ---- START -------------------------------------------------------------- */
SELECT s.*,
       ah.team_name AS home_team,
       aa.team_name AS away_team
INTO #work
FROM stg.match AS s
LEFT JOIN cfg.team_alias AS ah ON ah.source_name = s.home_team_src AND ah.league_code = s.league_code
LEFT JOIN cfg.team_alias AS aa ON aa.source_name = s.away_team_src AND aa.league_code = s.league_code;

SET @rows_in = @@ROWCOUNT;
SET @step += 1;
INSERT INTO cln.cleaning_log (step_no, step_type, step_name, rows_in, rows_affected, rows_out)
VALUES (@step, 'START', N'Typed rows received from staging', NULL, @rows_in, @rows_in);

/* ---- STANDARDISE -------------------------------------------------------- */
SET @step += 1;
INSERT INTO cln.cleaning_log (step_no, step_type, step_name, rows_in, rows_affected, rows_out)
SELECT @step, 'STANDARDISE', N'Line-ending characters removed from values (done during staging)',
       COUNT(*), SUM(CAST(had_carriage_return AS INT)), COUNT(*)
FROM #work;

SET @step += 1;
INSERT INTO cln.cleaning_log (step_no, step_type, step_name, rows_in, rows_affected, rows_out)
SELECT @step, 'STANDARDISE', N'Abbreviated team names replaced with standard names',
       COUNT(*),
       SUM(CASE WHEN home_team <> home_team_src OR away_team <> away_team_src THEN 1 ELSE 0 END),
       COUNT(*)
FROM #work;

/* ---- QUARANTINE --------------------------------------------------------- */
-- One block per rule. Each block: log the offending rows, remove them from
-- #work, write a cleaning_log line.

-- Q1 team name not in cfg.team_alias
SELECT @rows_in = COUNT(*) FROM #work;
INSERT INTO cln.match_issue (rule_code, load_id, source_row_no, file_name, detail)
SELECT 'UNMAPPED_TEAM', load_id, source_row_no, file_name,
       CONCAT(N'home=', home_team_src, N' away=', away_team_src)
FROM #work WHERE home_team IS NULL OR away_team IS NULL;
DELETE FROM #work WHERE home_team IS NULL OR away_team IS NULL;
SET @affected = @@ROWCOUNT; SET @step += 1;
INSERT INTO cln.cleaning_log VALUES (@step, 'QUARANTINE', N'Team name not in the alias table', @rows_in, @affected, @rows_in - @affected, SYSDATETIME());

-- Q2 a value could not be converted to its type
SELECT @rows_in = COUNT(*) FROM #work;
INSERT INTO cln.match_issue (rule_code, load_id, source_row_no, file_name, detail)
SELECT 'TYPE_ERROR', load_id, source_row_no, file_name, CONCAT(type_errors, N' value(s) failed conversion')
FROM #work WHERE type_errors > 0;
DELETE FROM #work WHERE type_errors > 0;
SET @affected = @@ROWCOUNT; SET @step += 1;
INSERT INTO cln.cleaning_log VALUES (@step, 'QUARANTINE', N'Value could not be converted to its data type', @rows_in, @affected, @rows_in - @affected, SYSDATETIME());

-- Q3 date, score or result missing (a match without these cannot be used)
SELECT @rows_in = COUNT(*) FROM #work;
INSERT INTO cln.match_issue (rule_code, load_id, source_row_no, file_name, detail)
SELECT 'MISSING_RESULT', load_id, source_row_no, file_name, N'date, full-time score or result is empty'
FROM #work WHERE match_date IS NULL OR ft_home_goals IS NULL OR ft_away_goals IS NULL OR ft_result IS NULL;
DELETE FROM #work WHERE match_date IS NULL OR ft_home_goals IS NULL OR ft_away_goals IS NULL OR ft_result IS NULL;
SET @affected = @@ROWCOUNT; SET @step += 1;
INSERT INTO cln.cleaning_log VALUES (@step, 'QUARANTINE', N'Date, score or result missing', @rows_in, @affected, @rows_in - @affected, SYSDATETIME());

-- Q4 result letter disagrees with the score
SELECT @rows_in = COUNT(*) FROM #work;
INSERT INTO cln.match_issue (rule_code, load_id, source_row_no, file_name, detail)
SELECT 'RESULT_MISMATCH', load_id, source_row_no, file_name,
       CONCAT(ft_home_goals, N'-', ft_away_goals, N' recorded as ', ft_result)
FROM #work
WHERE ft_result <> CASE WHEN ft_home_goals > ft_away_goals THEN 'H'
                        WHEN ft_home_goals < ft_away_goals THEN 'A' ELSE 'D' END;
DELETE FROM #work
WHERE ft_result <> CASE WHEN ft_home_goals > ft_away_goals THEN 'H'
                        WHEN ft_home_goals < ft_away_goals THEN 'A' ELSE 'D' END;
SET @affected = @@ROWCOUNT; SET @step += 1;
INSERT INTO cln.cleaning_log VALUES (@step, 'QUARANTINE', N'Result letter disagrees with the score', @rows_in, @affected, @rows_in - @affected, SYSDATETIME());

-- Q5 impossible statistics
SELECT @rows_in = COUNT(*) FROM #work;
INSERT INTO cln.match_issue (rule_code, load_id, source_row_no, file_name, detail)
SELECT 'IMPOSSIBLE_STATS', load_id, source_row_no, file_name,
       N'half-time goals above full-time, or shots on target above shots'
FROM #work
WHERE ht_home_goals > ft_home_goals OR ht_away_goals > ft_away_goals
   OR home_shots_on_target > home_shots OR away_shots_on_target > away_shots;
DELETE FROM #work
WHERE ht_home_goals > ft_home_goals OR ht_away_goals > ft_away_goals
   OR home_shots_on_target > home_shots OR away_shots_on_target > away_shots;
SET @affected = @@ROWCOUNT; SET @step += 1;
INSERT INTO cln.cleaning_log VALUES (@step, 'QUARANTINE', N'Impossible statistics (HT > FT goals, on target > shots)', @rows_in, @affected, @rows_in - @affected, SYSDATETIME());

-- Q6 date outside the season the file belongs to (1 July - 30 June)
SELECT @rows_in = COUNT(*) FROM #work;
INSERT INTO cln.match_issue (rule_code, load_id, source_row_no, file_name, detail)
SELECT 'DATE_OUTSIDE_SEASON', load_id, source_row_no, file_name, CONVERT(NVARCHAR(10), match_date, 23)
FROM #work
WHERE match_date NOT BETWEEN DATEFROMPARTS(season_start_year, 7, 1) AND DATEFROMPARTS(season_start_year + 1, 6, 30);
DELETE FROM #work
WHERE match_date NOT BETWEEN DATEFROMPARTS(season_start_year, 7, 1) AND DATEFROMPARTS(season_start_year + 1, 6, 30);
SET @affected = @@ROWCOUNT; SET @step += 1;
INSERT INTO cln.cleaning_log VALUES (@step, 'QUARANTINE', N'Match date outside the file''s season', @rows_in, @affected, @rows_in - @affected, SYSDATETIME());

-- Q7 duplicate fixture. In a double round-robin each home/away pairing
-- happens once per season. Keep the row from the latest delivery.
SELECT @rows_in = COUNT(*) FROM #work;
WITH ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY league_code, season_start_year, home_team, away_team
                                 ORDER BY load_id DESC, source_row_no DESC) AS rn
    FROM #work
)
INSERT INTO cln.match_issue (rule_code, load_id, source_row_no, file_name, detail)
SELECT 'DUPLICATE_FIXTURE', load_id, source_row_no, file_name, CONCAT(home_team, N' v ', away_team)
FROM ranked WHERE rn > 1;
WITH ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY league_code, season_start_year, home_team, away_team
                                 ORDER BY load_id DESC, source_row_no DESC) AS rn
    FROM #work
)
DELETE FROM ranked WHERE rn > 1;
SET @affected = @@ROWCOUNT; SET @step += 1;
INSERT INTO cln.cleaning_log VALUES (@step, 'QUARANTINE', N'Duplicate fixture (same season, home and away team)', @rows_in, @affected, @rows_in - @affected, SYSDATETIME());

/* ---- FLAG --------------------------------------------------------------- */
-- Kept for results and league tables, excluded from statistics averages.
SET @step += 1;
INSERT INTO cln.cleaning_log (step_no, step_type, step_name, rows_in, rows_affected, rows_out)
SELECT @step, 'FLAG', N'Result present but match statistics missing (kept, stats_complete = 0)',
       COUNT(*),
       SUM(CASE WHEN home_shots IS NULL OR away_shots IS NULL OR home_shots_on_target IS NULL
                  OR away_shots_on_target IS NULL OR ht_home_goals IS NULL THEN 1 ELSE 0 END),
       COUNT(*)
FROM #work;

-- Only the Premier League files carry a referee column with values.
SET @step += 1;
INSERT INTO cln.cleaning_log (step_no, step_type, step_name, rows_in, rows_affected, rows_out)
SELECT @step, 'FLAG', N'Referee not supplied by the source (kept, referee_supplied = 0)',
       COUNT(*), SUM(CASE WHEN referee IS NULL THEN 1 ELSE 0 END), COUNT(*)
FROM #work;

/* ---- END ---------------------------------------------------------------- */
INSERT INTO cln.match
    (match_id, league_code, season_start_year, match_date, home_team, away_team,
     ft_home_goals, ft_away_goals, ft_result, ht_home_goals, ht_away_goals, ht_result, referee,
     home_shots, away_shots, home_shots_on_target, away_shots_on_target,
     home_fouls, away_fouls, home_corners, away_corners,
     home_yellows, away_yellows, home_reds, away_reds,
     stats_complete, referee_supplied, source_file, source_row_no)
SELECT
    ROW_NUMBER() OVER (ORDER BY league_code, season_start_year, match_date, home_team),
    league_code, season_start_year, match_date, home_team, away_team,
    ft_home_goals, ft_away_goals, ft_result, ht_home_goals, ht_away_goals, ht_result, referee,
    home_shots, away_shots, home_shots_on_target, away_shots_on_target,
    home_fouls, away_fouls, home_corners, away_corners,
    home_yellows, away_yellows, home_reds, away_reds,
    CASE WHEN home_shots IS NULL OR away_shots IS NULL OR home_shots_on_target IS NULL
           OR away_shots_on_target IS NULL OR ht_home_goals IS NULL THEN 0 ELSE 1 END,
    CASE WHEN referee IS NULL THEN 0 ELSE 1 END,
    file_name, source_row_no
FROM #work;

SET @affected = @@ROWCOUNT; SET @step += 1;
INSERT INTO cln.cleaning_log (step_no, step_type, step_name, rows_in, rows_affected, rows_out)
VALUES (@step, 'END', N'Clean rows written to cln.match', @affected, @affected, @affected);

DROP TABLE #work;

SELECT step_no, step_type, step_name, rows_in, rows_affected, rows_out
FROM cln.cleaning_log
ORDER BY step_no;
GO
