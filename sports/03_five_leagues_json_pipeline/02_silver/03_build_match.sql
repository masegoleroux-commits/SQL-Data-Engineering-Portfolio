/* =============================================================================
   03_build_match.sql
   Silver step 3: typed, cleaned matches.

   silver.match   GRAIN: one scheduled match (league, season, home, away)

   Every match in the source is kept, including those that were never
   played, because "how many matches were cancelled" is a fair question.
   match_status says which results can be used:

     played          normal result
     awarded         result decided off the pitch (a 3-0 or 0-2 awarded
                     by the league); counts in the table, not in goal stats
     cancelled       never played (Ligue 1 stopped in March 2020)
     result missing  scheduled, no score in the source. The 2024-25 La Liga
                     and Serie A files stop before the last round

   Cleaning steps, each counted in ops.cleaning_log.
============================================================================= */

USE FootballLeagues;
GO

DROP TABLE IF EXISTS silver.match;
GO

CREATE TABLE silver.match (
    match_id         VARCHAR(80)    NOT NULL PRIMARY KEY,
    league_code      VARCHAR(5)     NOT NULL,
    season_start     SMALLINT       NOT NULL,
    matchday         SMALLINT       NOT NULL,
    match_date       DATE           NOT NULL,
    kickoff_time     TIME(0)        NULL,
    home_team        NVARCHAR(60)   NOT NULL,     -- canonical name
    away_team        NVARCHAR(60)   NOT NULL,
    match_status     VARCHAR(20)    NOT NULL,
    ht_home          SMALLINT       NULL,
    ht_away          SMALLINT       NULL,
    ft_home          SMALLINT       NULL,
    ft_away          SMALLINT       NULL,
    has_half_time    SMALLINT       NOT NULL
);

INSERT INTO silver.match
SELECT CONCAT(f.league_code, '|', f.season_start, '|', r.match_date, '|', ah.canonical_name),
       f.league_code,
       f.season_start,
       CAST(REPLACE(r.round_name, 'Matchday ', '') AS SMALLINT),
       CAST(r.match_date AS DATE),
       CAST(r.kickoff_time AS TIME(0)),
       ah.canonical_name,
       aa.canonical_name,
       CASE WHEN r.status = 'cancelled' THEN 'cancelled'
            WHEN r.status = 'awarded'   THEN 'awarded'
            WHEN r.ft_home IS NULL      THEN 'result missing'
            ELSE 'played' END,
       CAST(r.ht_home AS SMALLINT),
       CAST(r.ht_away AS SMALLINT),
       CAST(r.ft_home AS SMALLINT),
       CAST(r.ft_away AS SMALLINT),
       CASE WHEN r.ht_home IS NULL THEN 0 ELSE 1 END
FROM silver.match_raw AS r
INNER JOIN silver.source_file AS f  ON f.source_file  = r.source_file
INNER JOIN silver.team_alias  AS ah ON ah.league_code = f.league_code AND ah.source_name = r.team1
INNER JOIN silver.team_alias  AS aa ON aa.league_code = f.league_code AND aa.source_name = r.team2;
GO

INSERT INTO ops.cleaning_log (step_no, table_name, step_name, rows_affected)
SELECT 6, 'match', 'Team names replaced with canonical names (match sides changed)',
       (SELECT COUNT(*) FROM silver.match_raw AS r
        INNER JOIN silver.source_file AS f ON f.source_file = r.source_file
        INNER JOIN silver.team_alias  AS a ON a.league_code = f.league_code AND a.source_name = r.team1
        WHERE a.matched_by <> 'itself')
     + (SELECT COUNT(*) FROM silver.match_raw AS r
        INNER JOIN silver.source_file AS f ON f.source_file = r.source_file
        INNER JOIN silver.team_alias  AS a ON a.league_code = f.league_code AND a.source_name = r.team2
        WHERE a.matched_by <> 'itself')
UNION ALL
SELECT 7, 'match', 'Cancelled matches kept, flagged, no score', COUNT(*) FROM silver.match WHERE match_status = 'cancelled'
UNION ALL
SELECT 8, 'match', 'Matches with no result in the source flagged', COUNT(*) FROM silver.match WHERE match_status = 'result missing'
UNION ALL
SELECT 9, 'match', 'Awarded results flagged (kept out of goal statistics)', COUNT(*) FROM silver.match WHERE match_status = 'awarded'
UNION ALL
SELECT 10, 'match', 'Played matches with no half-time score (half-time left NULL)', COUNT(*)
FROM silver.match WHERE match_status = 'played' AND has_half_time = 0
UNION ALL
SELECT 11, 'match', 'Matches with no kick-off time (time left NULL)', COUNT(*) FROM silver.match WHERE kickoff_time IS NULL
UNION ALL
SELECT 12, 'match', 'Matchday text (''Matchday 12'') converted to a number', COUNT(*) FROM silver.match;

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'silver', 'match', COUNT(*) FROM silver.match;
GO
