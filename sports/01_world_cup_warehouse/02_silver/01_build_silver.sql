/* =============================================================================
   01_build_silver.sql
   Silver layer: typed, cleaned and standardised copies of the bronze tables.

   Cleaning applied (each step is counted in ops.cleaning_log):
     1. Stage names: the source mixes 'quarter-final' / 'quarter-finals' and
        'semi-final' / 'semi-finals'. One name per stage.
     2. Birth dates: 'not available' becomes NULL instead of a fake date.
     3. Gender: derived from the tournament name (Men's / Women's).
     4. Results: the source result includes penalty shootouts. Two codes are
        kept: final_result (who went through) and regulation_result (the
        score after 90 or 120 minutes).
     5. Score text: the source writes scores with an en dash ('3–3'), but
        one match uses a plain hyphen. The separator is standardised, then
        the text is checked against the numeric columns; any disagreement
        is quarantined, along with that match's goals and cards.
============================================================================= */

USE WorldCup;
GO

/* ---- Tournaments ------------------------------------------------------- */
DROP TABLE IF EXISTS silver.tournament;
CREATE TABLE silver.tournament (
    tournament_id    VARCHAR(10)   NOT NULL PRIMARY KEY,
    tournament_name  VARCHAR(60)   NOT NULL,
    tournament_year  SMALLINT      NOT NULL,
    gender           VARCHAR(5)    NOT NULL,
    start_date       DATE          NOT NULL,
    end_date         DATE          NOT NULL,
    host_country     VARCHAR(60)   NOT NULL,
    winner           VARCHAR(60)   NOT NULL,
    host_won         SMALLINT      NOT NULL,
    count_teams      SMALLINT      NOT NULL
);

INSERT INTO silver.tournament
SELECT tournament_id,
       tournament_name,
       CAST(year AS SMALLINT),
       CASE WHEN tournament_name LIKE '%Women%' THEN 'Women' ELSE 'Men' END,
       CAST(start_date AS DATE),
       CAST(end_date AS DATE),
       host_country,
       winner,
       CAST(host_won AS SMALLINT),
       CAST(count_teams AS SMALLINT)
FROM bronze.tournaments;

/* ---- Teams ------------------------------------------------------------- */
DROP TABLE IF EXISTS silver.team;
CREATE TABLE silver.team (
    team_id             VARCHAR(10)   NOT NULL PRIMARY KEY,
    team_name           VARCHAR(60)   NOT NULL,
    team_code           VARCHAR(5)    NOT NULL,
    confederation_code  VARCHAR(10)   NOT NULL,
    region_name         VARCHAR(40)   NOT NULL
);

INSERT INTO silver.team
SELECT team_id, LTRIM(RTRIM(team_name)), team_code, confederation_code, region_name
FROM bronze.teams;

/* ---- Matches ----------------------------------------------------------- */
DROP TABLE IF EXISTS silver.match;
CREATE TABLE silver.match (
    match_id           VARCHAR(12)   NOT NULL PRIMARY KEY,
    tournament_id      VARCHAR(10)   NOT NULL,
    stage_name         VARCHAR(30)   NOT NULL,
    group_name         VARCHAR(30)   NOT NULL,
    is_knockout        SMALLINT      NOT NULL,
    match_date         DATE          NOT NULL,
    stadium_name       VARCHAR(100)  NOT NULL,
    city_name          VARCHAR(60)   NOT NULL,
    country_name       VARCHAR(60)   NOT NULL,
    home_team_id       VARCHAR(10)   NOT NULL,
    away_team_id       VARCHAR(10)   NOT NULL,
    home_score         SMALLINT      NOT NULL,
    away_score         SMALLINT      NOT NULL,
    extra_time         SMALLINT      NOT NULL,
    penalty_shootout   SMALLINT      NOT NULL,
    home_penalties     SMALLINT      NOT NULL,
    away_penalties     SMALLINT      NOT NULL,
    final_result       CHAR(1)       NOT NULL,   -- H / A / D, includes shootouts
    regulation_result  CHAR(1)       NOT NULL,   -- H / A / D, score only
    is_replayed        SMALLINT      NOT NULL
);

INSERT INTO silver.match
SELECT m.match_id,
       m.tournament_id,
       CASE m.stage_name WHEN 'quarter-final' THEN 'quarter-finals'
                         WHEN 'semi-final'    THEN 'semi-finals'
                         ELSE m.stage_name END,
       m.group_name,
       CAST(m.knockout_stage AS SMALLINT),
       CAST(m.match_date AS DATE),
       m.stadium_name, m.city_name, m.country_name,
       m.home_team_id, m.away_team_id,
       CAST(m.home_team_score AS SMALLINT),
       CAST(m.away_team_score AS SMALLINT),
       CAST(m.extra_time AS SMALLINT),
       CAST(m.penalty_shootout AS SMALLINT),
       CAST(m.home_team_score_penalties AS SMALLINT),
       CAST(m.away_team_score_penalties AS SMALLINT),
       CASE m.result WHEN 'home team win' THEN 'H' WHEN 'away team win' THEN 'A' ELSE 'D' END,
       CASE WHEN CAST(m.home_team_score AS INT) > CAST(m.away_team_score AS INT) THEN 'H'
            WHEN CAST(m.home_team_score AS INT) < CAST(m.away_team_score AS INT) THEN 'A'
            ELSE 'D' END,
       CAST(m.replayed AS SMALLINT)
FROM bronze.matches AS m
-- the separator is an en dash (character 8211); a hyphen is accepted too
WHERE REPLACE(m.score, '-', NCHAR(8211)) = CONCAT(m.home_team_score, NCHAR(8211), m.away_team_score);

-- anything whose score text still disagrees with its numbers is quarantined
INSERT INTO ops.quarantine (source_table, record_key, rule_code, detail)
SELECT 'matches', m.match_id, 'SCORE_TEXT_MISMATCH',
       CONCAT('score text ', m.score, ' vs ', m.home_team_score, '-', m.away_team_score)
FROM bronze.matches AS m
WHERE REPLACE(m.score, '-', NCHAR(8211)) <> CONCAT(m.home_team_score, NCHAR(8211), m.away_team_score);

/* ---- Players ----------------------------------------------------------- */
DROP TABLE IF EXISTS silver.player;
CREATE TABLE silver.player (
    player_id        VARCHAR(10)   NOT NULL PRIMARY KEY,
    family_name      VARCHAR(100)  NOT NULL,
    given_name       VARCHAR(100)  NOT NULL,
    birth_date       DATE          NULL,
    is_female        SMALLINT      NOT NULL,
    primary_position VARCHAR(12)   NOT NULL,
    tournaments      SMALLINT      NOT NULL
);

INSERT INTO silver.player
SELECT player_id,
       family_name,
       given_name,
       CASE WHEN birth_date = 'not available' THEN NULL ELSE CAST(birth_date AS DATE) END,
       CAST(female AS SMALLINT),
       CASE WHEN goal_keeper = '1' THEN 'Goalkeeper'
            WHEN defender    = '1' THEN 'Defender'
            WHEN midfielder  = '1' THEN 'Midfielder'
            WHEN forward     = '1' THEN 'Forward'
            ELSE 'Unknown' END,
       CAST(count_tournaments AS SMALLINT)
FROM bronze.players;

/* ---- Goals, bookings, appearances, penalty kicks ------------------------- */
DROP TABLE IF EXISTS silver.goal;
CREATE TABLE silver.goal (
    goal_id            VARCHAR(12)  NOT NULL PRIMARY KEY,
    match_id           VARCHAR(12)  NOT NULL,
    team_id            VARCHAR(10)  NOT NULL,     -- team credited with the goal
    player_id          VARCHAR(10)  NOT NULL,
    player_team_id     VARCHAR(10)  NOT NULL,     -- differs from team_id for own goals
    minute_regulation  SMALLINT     NOT NULL,
    minute_stoppage    SMALLINT     NOT NULL,
    match_period       VARCHAR(60)  NOT NULL,
    is_own_goal        SMALLINT     NOT NULL,
    is_penalty         SMALLINT     NOT NULL
);

INSERT INTO silver.goal
SELECT goal_id, match_id, team_id, player_id, player_team_id,
       CAST(minute_regulation AS SMALLINT), CAST(minute_stoppage AS SMALLINT), match_period,
       CAST(own_goal AS SMALLINT), CAST(penalty AS SMALLINT)
FROM bronze.goals
WHERE match_id IN (SELECT match_id FROM silver.match);

INSERT INTO ops.quarantine (source_table, record_key, rule_code, detail)
SELECT 'goals', goal_id, 'PARENT_MATCH_QUARANTINED', match_id
FROM bronze.goals
WHERE match_id NOT IN (SELECT match_id FROM silver.match);

DROP TABLE IF EXISTS silver.booking;
CREATE TABLE silver.booking (
    booking_id         VARCHAR(12)  NOT NULL PRIMARY KEY,
    match_id           VARCHAR(12)  NOT NULL,
    team_id            VARCHAR(10)  NOT NULL,
    player_id          VARCHAR(10)  NOT NULL,
    minute_regulation  SMALLINT     NOT NULL,
    is_yellow          SMALLINT     NOT NULL,
    is_red             SMALLINT     NOT NULL,
    is_second_yellow   SMALLINT     NOT NULL,
    is_sending_off     SMALLINT     NOT NULL
);

INSERT INTO silver.booking
SELECT booking_id, match_id, team_id, player_id, CAST(minute_regulation AS SMALLINT),
       CAST(yellow_card AS SMALLINT), CAST(red_card AS SMALLINT),
       CAST(second_yellow_card AS SMALLINT), CAST(sending_off AS SMALLINT)
FROM bronze.bookings
WHERE match_id IN (SELECT match_id FROM silver.match);

INSERT INTO ops.quarantine (source_table, record_key, rule_code, detail)
SELECT 'bookings', booking_id, 'PARENT_MATCH_QUARANTINED', match_id
FROM bronze.bookings
WHERE match_id NOT IN (SELECT match_id FROM silver.match);

DROP TABLE IF EXISTS silver.appearance;
CREATE TABLE silver.appearance (
    match_id       VARCHAR(12)  NOT NULL,
    team_id        VARCHAR(10)  NOT NULL,
    player_id      VARCHAR(10)  NOT NULL,
    position_code  VARCHAR(5)   NOT NULL,
    is_starter     SMALLINT     NOT NULL,
    PRIMARY KEY (match_id, player_id)
);

INSERT INTO silver.appearance
SELECT match_id, team_id, player_id, position_code, CAST(starter AS SMALLINT)
FROM bronze.player_appearances;

DROP TABLE IF EXISTS silver.penalty_kick;
CREATE TABLE silver.penalty_kick (
    penalty_kick_id  VARCHAR(12)  NOT NULL PRIMARY KEY,
    match_id         VARCHAR(12)  NOT NULL,
    team_id          VARCHAR(10)  NOT NULL,
    player_id        VARCHAR(10)  NOT NULL,
    is_converted     SMALLINT     NOT NULL
);

INSERT INTO silver.penalty_kick
SELECT penalty_kick_id, match_id, team_id, player_id, CAST(converted AS SMALLINT)
FROM bronze.penalty_kicks;
GO

/* ---- Cleaning log ------------------------------------------------------ */
INSERT INTO ops.cleaning_log (step_no, table_name, step_name, rows_affected)
SELECT 1, 'matches', 'Stage names standardised (quarter-final -> quarter-finals, semi-final -> semi-finals)',
       COUNT(*) FROM bronze.matches WHERE stage_name IN ('quarter-final', 'semi-final')
UNION ALL
SELECT 2, 'players', 'Birth date ''not available'' replaced with NULL',
       COUNT(*) FROM bronze.players WHERE birth_date = 'not available'
UNION ALL
SELECT 3, 'tournaments', 'Gender derived from tournament name (women''s tournaments)',
       COUNT(*) FROM silver.tournament WHERE gender = 'Women'
UNION ALL
SELECT 4, 'matches', 'Shootout winners: final result differs from regulation result',
       COUNT(*) FROM silver.match WHERE final_result <> regulation_result
UNION ALL
SELECT 5, 'matches', 'Score separator standardised (hyphen replaced with en dash)',
       COUNT(*) FROM bronze.matches WHERE score LIKE '%-%'
UNION ALL
SELECT 6, 'matches', 'Score text disagrees with numeric score (quarantined)',
       COUNT(*) FROM ops.quarantine WHERE rule_code = 'SCORE_TEXT_MISMATCH';

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'silver', 'tournament',   COUNT(*) FROM silver.tournament UNION ALL
SELECT 'silver', 'team',         COUNT(*) FROM silver.team UNION ALL
SELECT 'silver', 'match',        COUNT(*) FROM silver.match UNION ALL
SELECT 'silver', 'player',       COUNT(*) FROM silver.player UNION ALL
SELECT 'silver', 'goal',         COUNT(*) FROM silver.goal UNION ALL
SELECT 'silver', 'booking',      COUNT(*) FROM silver.booking UNION ALL
SELECT 'silver', 'appearance',   COUNT(*) FROM silver.appearance UNION ALL
SELECT 'silver', 'penalty_kick', COUNT(*) FROM silver.penalty_kick;

SELECT step_no, table_name, step_name, rows_affected
FROM ops.cleaning_log
ORDER BY step_no;
GO
