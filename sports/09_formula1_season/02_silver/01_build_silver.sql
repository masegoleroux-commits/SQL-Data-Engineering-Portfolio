/* =============================================================================
   01_build_silver.sql
   silver.race          GRAIN: one calendar round (including a cancelled one)
   silver.team          GRAIN: one constructor
   silver.driver        GRAIN: one driver who started a session in 2023
   silver.result        GRAIN: one driver in one race or sprint
   silver.qualifying    GRAIN: one driver in one qualifying session

   Cleaning steps, each counted in ops.cleaning_log:
     1. Calendar dates in DD/MM/YYYY converted with style 103.
     2. Results matched to the calendar: by city, then by country where the
        country has one race, then by the override table.
     3. Rounds on the calendar with no results flagged as cancelled.
     4. Result team names include the engine ('Red Bull Racing Honda RBPT');
        they are matched to the constructor by the leading name, after
        dropping the ' F1 Team' suffix from 'Haas F1 Team'. A misspelt
        team name takes the driver's team from the same weekend's race.
     5. Time/Retired text split into a status and a gap:
            '1:33:56.736' winner's race time   -> finished, gap 0
            '+11.987'     seconds behind       -> finished, gap 11.987
            '+1 lap'      laps behind          -> finished, laps_down 1
            'DNF' / 'DNS' did not finish / did not start
        Position 'NC' (not classified) and 'DQ' (disqualified) kept as
        statuses with no numeric position.
     6. Qualifying lap times 'm:ss.sss' converted to seconds, after
        repairing one time written with a colon instead of a decimal point.
============================================================================= */

USE Formula1;
GO

DROP TABLE IF EXISTS silver.qualifying;
DROP TABLE IF EXISTS silver.result;
DROP TABLE IF EXISTS silver.driver;
DROP TABLE IF EXISTS silver.team;
DROP TABLE IF EXISTS silver.race;
GO

CREATE TABLE silver.race (
    round_no       INT           NOT NULL PRIMARY KEY,
    race_date      DATE          NULL,        -- blank for the cancelled Imola round
    gp_name        NVARCHAR(100) NOT NULL,
    country        NVARCHAR(30)  NOT NULL,
    city           NVARCHAR(30)  NOT NULL,
    circuit_name   NVARCHAR(60)  NOT NULL,
    laps           INT           NOT NULL,
    track_label    VARCHAR(30)   NULL,        -- the label results use for this round
    has_sprint     SMALLINT      NOT NULL,
    is_cancelled   SMALLINT      NOT NULL
);

-- step 2: city first, then a country with only one round, then the overrides
WITH labels AS (
    SELECT DISTINCT track FROM bronze.race_results
),
calendar AS (
    SELECT c.*, COUNT(*) OVER (PARTITION BY c.country) AS races_in_country
    FROM bronze.calendar AS c
),
matched AS (
    SELECT c.round, l.track
    FROM calendar AS c
    INNER JOIN labels AS l
            ON l.track = c.city
            OR (l.track = c.country AND c.races_in_country = 1)
            OR EXISTS (SELECT 1 FROM ops.track_label_override AS o
                       WHERE o.track_label = l.track AND o.city = c.city)
)
INSERT INTO silver.race
SELECT CAST(c.round AS INT), CONVERT(DATE, c.race_date, 103), c.gp_name, c.country, c.city,
       c.circuit_name, CAST(c.number_of_laps AS INT), m.track,
       CASE WHEN m.track IN (SELECT track FROM bronze.sprint_results) THEN 1 ELSE 0 END,
       CASE WHEN m.track IS NULL THEN 1 ELSE 0 END
FROM bronze.calendar AS c
LEFT JOIN matched AS m ON m.round = c.round;
GO

CREATE TABLE silver.team (
    team_name       VARCHAR(40)   NOT NULL PRIMARY KEY,
    full_team_name  NVARCHAR(80)  NOT NULL,
    power_unit      VARCHAR(30)   NOT NULL
);

-- 'Haas F1 Team' in the teams file is 'Haas Ferrari' in results; the
-- ' F1 Team' suffix is dropped so every constructor matches by its name
INSERT INTO silver.team SELECT REPLACE(team, ' F1 Team', ''), full_team_name, power_unit FROM bronze.teams;

CREATE TABLE silver.driver (
    driver_name     NVARCHAR(40)  NOT NULL PRIMARY KEY,
    car_number      INT           NOT NULL,
    abbreviation    CHAR(3)       NULL,
    country         NVARCHAR(30)  NULL,
    date_of_birth   DATE          NULL
);

INSERT INTO silver.driver
SELECT r.driver, MIN(CAST(r.no AS INT)), MIN(d.abbreviation), MIN(d.country),
       MIN(CONVERT(DATE, d.date_of_birth, 103))
FROM bronze.race_results AS r
LEFT JOIN bronze.drivers AS d ON d.driver = r.driver
GROUP BY r.driver;
GO

/* ---- Results: races and sprints in one table ------------------------------ */
CREATE TABLE silver.result (
    session_type     VARCHAR(10)    NOT NULL,
    round_no         INT            NOT NULL,
    driver_name      NVARCHAR(40)   NOT NULL,
    team_name        VARCHAR(40)    NOT NULL,
    finish_position  INT            NULL,        -- NULL when not classified / disqualified
    position_text    VARCHAR(5)     NOT NULL,
    grid_position    INT            NULL,
    laps_completed   INT            NOT NULL,
    status           VARCHAR(15)    NOT NULL,    -- finished / lapped / DNF / DNS / not classified / disqualified
    gap_seconds      DECIMAL(9, 3)  NULL,
    laps_down        INT            NULL,
    winner_time_s    DECIMAL(9, 3)  NULL,
    published_points DECIMAL(5, 1)  NOT NULL,
    fastest_lap      SMALLINT       NOT NULL,
    PRIMARY KEY (session_type, round_no, driver_name)
);

WITH unioned AS (
    SELECT 'race' AS session_type, track, position, driver, team, starting_grid, laps, time_retired, points, set_fastest_lap
    FROM bronze.race_results
    UNION ALL
    SELECT 'sprint', track, position, driver, team, starting_grid, laps, time_retired, points, 'No'
    FROM bronze.sprint_results
)
INSERT INTO silver.result
SELECT u.session_type, r.round_no, u.driver, t.team_name,
       CASE WHEN u.position NOT IN ('NC', 'DQ') THEN CAST(u.position AS INT) END,
       u.position,
       CASE WHEN u.starting_grid NOT IN ('', '0') THEN CAST(u.starting_grid AS INT) END,
       CAST(u.laps AS INT),
       CASE WHEN u.position = 'DQ'          THEN 'disqualified'
            WHEN u.time_retired = 'DNS'      THEN 'DNS'
            WHEN u.time_retired = 'DNF'      THEN 'DNF'
            WHEN u.position = 'NC'           THEN 'not classified'
            WHEN u.time_retired LIKE '%lap%' THEN 'lapped'
            ELSE 'finished' END,
       -- gap: '+11.987' -> 11.987; the winner's own time -> 0
       CASE WHEN u.time_retired LIKE '+%' AND u.time_retired NOT LIKE '%lap%'
                 THEN CAST(REPLACE(u.time_retired, '+', '') AS DECIMAL(9, 3))
            WHEN u.position = '1' THEN 0 END,
       CASE WHEN u.time_retired LIKE '%lap%'
                 THEN CAST(LEFT(REPLACE(u.time_retired, '+', ''), CHARINDEX(' ', u.time_retired) - 2) AS INT) END,
       -- winner's time: 'h:mm:ss.fff' or 'mm:ss.fff'
       CASE WHEN u.position = '1' AND LEN(u.time_retired) - LEN(REPLACE(u.time_retired, ':', '')) = 2
                 THEN CAST(LEFT(u.time_retired, CHARINDEX(':', u.time_retired) - 1) AS INT) * 3600
                    + CAST(SUBSTRING(u.time_retired, CHARINDEX(':', u.time_retired) + 1, 2) AS INT) * 60
                    + CAST(RIGHT(u.time_retired, 6) AS DECIMAL(6, 3))
            WHEN u.position = '1'
                 THEN CAST(LEFT(u.time_retired, CHARINDEX(':', u.time_retired) - 1) AS INT) * 60
                    + CAST(RIGHT(u.time_retired, 6) AS DECIMAL(6, 3)) END,
       CAST(u.points AS DECIMAL(5, 1)),
       CASE WHEN u.set_fastest_lap = 'Yes' THEN 1 ELSE 0 END
FROM unioned AS u
INNER JOIN silver.race AS r ON r.track_label = u.track
-- a team name that matches no constructor (the Qatar sprint lists
-- 'Aston Martib') takes the driver's team from the same weekend's race
INNER JOIN silver.team AS t
        ON t.team_name = COALESCE(
               (SELECT MIN(t1.team_name) FROM silver.team AS t1 WHERE u.team LIKE CONCAT(t1.team_name, '%')),
               (SELECT MIN(t2.team_name) FROM bronze.race_results AS rr
                INNER JOIN silver.team AS t2 ON rr.team LIKE CONCAT(t2.team_name, '%')
                WHERE rr.track = u.track AND rr.driver = u.driver));
GO

/* ---- Qualifying ---------------------------------------------------------- */
CREATE TABLE silver.qualifying (
    round_no      INT            NOT NULL,
    driver_name   NVARCHAR(40)   NOT NULL,
    team_name     VARCHAR(40)    NOT NULL,
    position      INT            NULL,
    q1_seconds    DECIMAL(7, 3)  NULL,
    q2_seconds    DECIMAL(7, 3)  NULL,
    q3_seconds    DECIMAL(7, 3)  NULL,
    PRIMARY KEY (round_no, driver_name)
);

-- one lap time in the source is written 1:59:634 (colon instead of a
-- decimal point); any time shaped m:ss:fff is repaired to m:ss.fff
WITH q_fixed AS (
    SELECT track, driver, team, position,
           CASE WHEN q1 LIKE '_:__:___' THEN CONCAT(LEFT(q1, 4), '.', RIGHT(q1, 3)) ELSE q1 END AS q1,
           CASE WHEN q2 LIKE '_:__:___' THEN CONCAT(LEFT(q2, 4), '.', RIGHT(q2, 3)) ELSE q2 END AS q2,
           CASE WHEN q3 LIKE '_:__:___' THEN CONCAT(LEFT(q3, 4), '.', RIGHT(q3, 3)) ELSE q3 END AS q3
    FROM bronze.qualifying_results
)
INSERT INTO silver.qualifying
SELECT r.round_no, q.driver, t.team_name,
       CASE WHEN q.position NOT IN ('NC', 'DQ') THEN CAST(q.position AS INT) END,
       CASE WHEN q.q1 LIKE '%:%' THEN CAST(LEFT(q.q1, CHARINDEX(':', q.q1) - 1) AS INT) * 60
                                    + CAST(SUBSTRING(q.q1, CHARINDEX(':', q.q1) + 1, 6) AS DECIMAL(6, 3)) END,
       CASE WHEN q.q2 LIKE '%:%' THEN CAST(LEFT(q.q2, CHARINDEX(':', q.q2) - 1) AS INT) * 60
                                    + CAST(SUBSTRING(q.q2, CHARINDEX(':', q.q2) + 1, 6) AS DECIMAL(6, 3)) END,
       CASE WHEN q.q3 LIKE '%:%' THEN CAST(LEFT(q.q3, CHARINDEX(':', q.q3) - 1) AS INT) * 60
                                    + CAST(SUBSTRING(q.q3, CHARINDEX(':', q.q3) + 1, 6) AS DECIMAL(6, 3)) END
FROM q_fixed AS q
INNER JOIN silver.race AS r ON r.track_label = q.track
INNER JOIN silver.team AS t ON q.team LIKE CONCAT(t.team_name, '%');
GO

INSERT INTO ops.cleaning_log (step_no, table_name, step_name, rows_affected)
SELECT 1, 'race', 'Calendar dates converted from DD/MM/YYYY', COUNT(race_date) FROM silver.race
UNION ALL
SELECT 1, 'race', 'Calendar rounds with a blank date', COUNT(*) - COUNT(race_date) FROM silver.race
UNION ALL
SELECT 2, 'race', 'Results labels matched to a calendar round', COUNT(*) FROM silver.race WHERE track_label IS NOT NULL
UNION ALL
SELECT 2, 'race', 'Labels matched only through the override table', COUNT(*) FROM ops.track_label_override
UNION ALL
SELECT 3, 'race', 'Calendar rounds with no results (cancelled)', SUM(is_cancelled) FROM silver.race
UNION ALL
SELECT 4, 'team', 'Constructor names with a '' F1 Team'' suffix standardised',
       COUNT(*) FROM bronze.teams WHERE team LIKE '% F1 Team'
UNION ALL
SELECT 4, 'result', 'Misspelt team names resolved from the same weekend''s race',
       (SELECT COUNT(*) FROM (SELECT team FROM bronze.race_results UNION ALL SELECT team FROM bronze.sprint_results) AS a
        WHERE NOT EXISTS (SELECT 1 FROM silver.team AS t WHERE a.team LIKE CONCAT(t.team_name, '%')))
UNION ALL
SELECT 4, 'result', 'Team names with the engine supplier matched to the constructor',
       COUNT(*) FROM silver.result AS r INNER JOIN silver.team AS t ON t.team_name = r.team_name
UNION ALL
SELECT 5, 'result', CONCAT('Status parsed from Time/Retired: ', status), COUNT(*) FROM silver.result GROUP BY status
UNION ALL
SELECT 6, 'qualifying', 'Lap time written m:ss:fff repaired to m:ss.fff',
       (SELECT COUNT(*) FROM bronze.qualifying_results
        WHERE q1 LIKE '_:__:___' OR q2 LIKE '_:__:___' OR q3 LIKE '_:__:___')
UNION ALL
SELECT 6, 'qualifying', 'Qualifying lap times converted to seconds',
       SUM(CASE WHEN q1_seconds IS NOT NULL THEN 1 ELSE 0 END + CASE WHEN q2_seconds IS NOT NULL THEN 1 ELSE 0 END
         + CASE WHEN q3_seconds IS NOT NULL THEN 1 ELSE 0 END) FROM silver.qualifying;

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'silver', 'race',       COUNT(*) FROM silver.race UNION ALL
SELECT 'silver', 'result',     COUNT(*) FROM silver.result UNION ALL
SELECT 'silver', 'qualifying', COUNT(*) FROM silver.qualifying;
GO
