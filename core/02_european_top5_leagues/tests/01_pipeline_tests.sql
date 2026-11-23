/* =============================================================================
   01_pipeline_tests.sql
   Proves each stage hands the next one exactly what it should.
   Every row shows the expected value, the actual value and PASS/FAIL.
   The script raises an error at the end if anything failed, which stops
   run_all.sql (SQLCMD :on error exit).
============================================================================= */

USE EuroLeagues;
GO

SET NOCOUNT ON;

DECLARE @points_win  INT = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'points_win'),
        @points_draw INT = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'points_draw');

DROP TABLE IF EXISTS #pipeline_results;
CREATE TABLE #pipeline_results (
    test_id     INT IDENTITY(1, 1),
    stage       VARCHAR(20),
    test_name   VARCHAR(120),
    expected    BIGINT,
    actual      BIGINT
);

/* ---- Stage 1: raw ------------------------------------------------------- */
-- Expected rows per file come from reference data: teams x (teams - 1)
INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'raw', 'rows loaded = teams x (teams - 1), all files',
       (SELECT SUM(ls.teams * (ls.teams - 1)) FROM cfg.league_season AS ls),
       (SELECT SUM(rows_loaded) FROM raw.load_log
        WHERE load_id IN (SELECT MAX(load_id) FROM raw.load_log GROUP BY file_name));

INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'raw', 'files with the wrong row count', 0, COUNT(*)
FROM cfg.source_file AS f
INNER JOIN cfg.league_season AS ls
    ON ls.league_code = f.league_code AND ls.season_start_year = f.season_start_year
LEFT JOIN (SELECT file_name, rows_loaded FROM raw.load_log
           WHERE load_id IN (SELECT MAX(load_id) FROM raw.load_log GROUP BY file_name)) AS l
    ON l.file_name = f.file_name
WHERE COALESCE(l.rows_loaded, -1) <> ls.teams * (ls.teams - 1);

/* ---- Stage 2: staging --------------------------------------------------- */
INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'stg', 'staged rows = latest raw delivery',
       (SELECT COUNT(*) FROM raw.match WHERE load_id IN (SELECT MAX(load_id) FROM raw.load_log GROUP BY file_name)),
       (SELECT COUNT(*) FROM stg.match);

/* ---- Stage 3: clean ----------------------------------------------------- */
INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'cln', 'clean rows + quarantined rows = staged rows',
       (SELECT COUNT(*) FROM stg.match),
       (SELECT COUNT(*) FROM cln.match) + (SELECT COUNT(*) FROM cln.match_issue);

INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'cln', 'cleaning log END = rows in cln.match',
       (SELECT COUNT(*) FROM cln.match),
       (SELECT rows_out FROM cln.cleaning_log WHERE step_type = 'END');

INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'cln', 'every source team name is in the alias table', 0,
       (SELECT COUNT(*) FROM cln.match_issue WHERE rule_code = 'UNMAPPED_TEAM');

INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'cln', 'each team plays 2 x (teams - 1) matches per season', 0, COUNT(*)
FROM (
    SELECT m.league_code, m.season_start_year, t.team, COUNT(*) AS played
    FROM cln.match AS m
    CROSS APPLY (VALUES (m.home_team), (m.away_team)) AS t (team)
    GROUP BY m.league_code, m.season_start_year, t.team
) AS p
INNER JOIN cfg.league_season AS ls
    ON ls.league_code = p.league_code AND ls.season_start_year = p.season_start_year
WHERE p.played <> 2 * (ls.teams - 1);

INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'cln', 'teams per season match reference data', 0, COUNT(*)
FROM (
    SELECT league_code, season_start_year, COUNT(DISTINCT home_team) AS teams
    FROM cln.match
    GROUP BY league_code, season_start_year
) AS t
INNER JOIN cfg.league_season AS ls
    ON ls.league_code = t.league_code AND ls.season_start_year = t.season_start_year
WHERE t.teams <> ls.teams;

/* ---- Stage 4: model ----------------------------------------------------- */
INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'dw', 'fact_match rows = clean rows',
       (SELECT COUNT(*) FROM cln.match), (SELECT COUNT(*) FROM dw.fact_match);

INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'dw', 'fact_team_match rows = 2 x fact_match',
       (SELECT 2 * COUNT(*) FROM dw.fact_match), (SELECT COUNT(*) FROM dw.fact_team_match);

INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'dw', 'goals control total: clean = model',
       (SELECT SUM(ft_home_goals + ft_away_goals) FROM cln.match),
       (SELECT SUM(goals_for) FROM dw.fact_team_match);

INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'dw', 'every match: goals for one side = goals against the other', 0, COUNT(*)
FROM dw.fact_team_match AS a
INNER JOIN dw.fact_team_match AS b
    ON b.match_key = a.match_key AND b.team_key = a.opponent_key
WHERE a.goals_for <> b.goals_against;

-- Points reconcile: a decisive match hands out points_win, a draw 2 x points_draw
INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'dw', 'points total reconciles to results',
       (SELECT SUM(CASE WHEN ft_result = 'D' THEN 2 * @points_draw ELSE @points_win END)
        FROM dw.fact_match),
       (SELECT SUM(points) FROM dw.fact_team_match);

INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'dw', 'league table: one champion per league season',
       (SELECT COUNT(*) FROM cfg.league_season),
       (SELECT COUNT(*) FROM rpt.v_league_table WHERE position = 1);

INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'dw', 'referee: rows outside the Premier League use the unknown member',
       (SELECT COUNT(*) FROM cln.match WHERE referee IS NULL),
       (SELECT COUNT(*) FROM dw.fact_match WHERE referee_key = -1);

INSERT INTO #pipeline_results (stage, test_name, expected, actual)
SELECT 'dw', 'matches without statistics are flagged, not dropped',
       (SELECT COUNT(*) FROM cln.match WHERE stats_complete = 0),
       (SELECT COUNT(*) FROM dw.fact_match WHERE stats_complete = 0);

/* ---- Results ------------------------------------------------------------ */
SELECT test_id, stage, test_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM #pipeline_results
ORDER BY test_id;

IF EXISTS (SELECT 1 FROM #pipeline_results WHERE expected <> actual OR actual IS NULL)
    THROW 50001, 'Pipeline tests failed. See the results grid.', 1;
GO
