/* =============================================================================
   01_shred_json.sql
   Silver step 1: turn the landed JSON documents into rows.

   silver.source_file   GRAIN: one landed document (league + season)
   silver.match_raw     GRAIN: one match as written in the source, all text

   Each landing line looks like this (payload shortened):

   {"source_file":"en.1_2023-24.json", "league_code":"en.1", "season":"2023-24",
    "payload":{"name":"English Premier League 2023/24",
               "matches":[{"round":"Matchday 1","date":"2023-08-11","time":"20:00",
                           "team1":"Burnley FC","team2":"Manchester City FC",
                           "score":{"ht":[0,2],"ft":[0,3]}}, ...]}}

   OPENJSON with a WITH clause maps JSON paths to columns. Paths that do not
   exist in a document return NULL instead of failing, which matters here:
   about 700 matches have no half-time score, 101 have no kick-off time and
   121 have an empty score object.
============================================================================= */

USE FootballLeagues;
GO

DROP TABLE IF EXISTS silver.match_raw;
DROP TABLE IF EXISTS silver.source_file;
GO

/* ---- 1. Documents that are not valid JSON go to quarantine --------------- */
INSERT INTO ops.quarantine (source_table, record_key, rule_code, detail)
SELECT 'api_landing', LEFT(raw_document, 60), 'INVALID_JSON', 'line could not be parsed as JSON'
FROM bronze.api_landing
WHERE ISJSON(raw_document) = 0;
GO

/* ---- 2. The envelope: one row per landed document ------------------------ */
CREATE TABLE silver.source_file (
    source_file       VARCHAR(40)    NOT NULL PRIMARY KEY,
    league_code       VARCHAR(5)     NOT NULL,
    season_label      VARCHAR(7)     NOT NULL,     -- 2023-24
    season_start      SMALLINT       NOT NULL,     -- 2023
    competition_name  NVARCHAR(100)  NOT NULL,
    matches_in_file   INT            NOT NULL
);

INSERT INTO silver.source_file
SELECT e.source_file,
       e.league_code,
       e.season,
       CAST(LEFT(e.season, 4) AS SMALLINT),
       e.competition_name,
       (SELECT COUNT(*) FROM OPENJSON(b.raw_document, '$.payload.matches'))
FROM bronze.api_landing AS b
CROSS APPLY OPENJSON(b.raw_document)
     WITH (source_file       VARCHAR(40)    '$.source_file',
           league_code       VARCHAR(5)     '$.league_code',
           season            VARCHAR(7)     '$.season',
           competition_name  NVARCHAR(100)  '$.payload.name') AS e
WHERE ISJSON(b.raw_document) = 1;
GO

/* ---- 3. The matches array: one row per match, still text ----------------- */
CREATE TABLE silver.match_raw (
    source_file   VARCHAR(40)    NOT NULL,
    round_name    VARCHAR(20)    NULL,
    match_date    VARCHAR(10)    NULL,
    kickoff_time  VARCHAR(5)     NULL,
    team1         NVARCHAR(60)   NULL,
    team2         NVARCHAR(60)   NULL,
    status        VARCHAR(20)    NULL,
    ht_home       VARCHAR(3)     NULL,
    ht_away       VARCHAR(3)     NULL,
    ft_home       VARCHAR(3)     NULL,
    ft_away       VARCHAR(3)     NULL
);

INSERT INTO silver.match_raw
SELECT JSON_VALUE(b.raw_document, '$.source_file'),
       m.round_name, m.match_date, m.kickoff_time, m.team1, m.team2, m.status,
       m.ht_home, m.ht_away, m.ft_home, m.ft_away
FROM bronze.api_landing AS b
CROSS APPLY OPENJSON(b.raw_document, '$.payload.matches')
     WITH (round_name    VARCHAR(20)   '$.round',
           match_date    VARCHAR(10)   '$.date',
           kickoff_time  VARCHAR(5)    '$.time',
           team1         NVARCHAR(60)  '$.team1',
           team2         NVARCHAR(60)  '$.team2',
           status        VARCHAR(20)   '$.status',
           ht_home       VARCHAR(3)    '$.score.ht[0]',
           ht_away       VARCHAR(3)    '$.score.ht[1]',
           ft_home       VARCHAR(3)    '$.score.ft[0]',
           ft_away       VARCHAR(3)    '$.score.ft[1]') AS m
WHERE ISJSON(b.raw_document) = 1;
GO

INSERT INTO ops.cleaning_log (step_no, table_name, step_name, rows_affected)
SELECT 1, 'api_landing', 'Landed documents that are not valid JSON (quarantined)',
       COUNT(*) FROM ops.quarantine WHERE rule_code = 'INVALID_JSON'
UNION ALL
SELECT 2, 'match_raw', 'Matches shredded from JSON arrays', COUNT(*) FROM silver.match_raw;

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'silver', 'source_file', COUNT(*) FROM silver.source_file UNION ALL
SELECT 'silver', 'match_raw',   COUNT(*) FROM silver.match_raw;
GO
