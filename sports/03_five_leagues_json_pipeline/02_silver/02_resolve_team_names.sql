/* =============================================================================
   02_resolve_team_names.sql
   Silver step 2: entity resolution for team names.

   The source spells the same club differently from season to season:
   'Manchester City' and 'Manchester City FC', 'Atlético Madrid' and
   'Club Atlético de Madrid', 'CD Alavés' and 'Deportivo Alavés'. Left alone,
   every all-time query would split those clubs in two.

   Matching is automatic and explainable, and uses two kinds of evidence:

   1. NAME EVIDENCE. Each name is lower-cased, accents are removed and
      club-type words (FC, CF, Club, de ...; see ops.name_stop_token) are
      dropped. The rest is split into words. The score is the share of the
      shorter name's words found in the longer name:
          'Real Betis' vs 'Real Betis Balompié'      -> 2 of 2 = 1.00
          'Real Madrid' vs 'Real Betis'              -> 1 of 2 = 0.50

   2. SCHEDULE EVIDENCE. One club cannot appear under two names in the same
      season. Any pair that shares a season is rejected however similar the
      names are. This is what stops 'FC Barcelona' matching 'Espanyol
      Barcelona' and 'AS Roma' matching 'Lazio Roma'.

   A pair is accepted when the name score reaches name_match_min_score and
   the two names never share a season. The canonical name is the one used
   most recently. ops.team_alias_override covers the two cases word matching
   cannot see (an abbreviation and a nickname) and always wins.

   silver.team_name_candidate  every pair compared, with score and decision
   silver.team_alias           GRAIN: one source name -> one canonical name
============================================================================= */

USE FootballLeagues;
GO

DROP TABLE IF EXISTS silver.team_alias;
DROP TABLE IF EXISTS silver.team_name_candidate;
DROP TABLE IF EXISTS silver.team_name_token;
DROP TABLE IF EXISTS silver.team_name;
GO

/* ---- 1. Distinct names, with the seasons each was used in ---------------- */
CREATE TABLE silver.team_name (
    league_code    VARCHAR(5)     NOT NULL,
    source_name    NVARCHAR(60)   NOT NULL,
    clean_name     NVARCHAR(60)   NOT NULL,
    first_season   SMALLINT       NOT NULL,
    last_season    SMALLINT       NOT NULL,
    PRIMARY KEY (league_code, source_name)
);

-- accents out, punctuation to spaces, lower case
INSERT INTO silver.team_name
SELECT n.league_code, n.source_name,
       LOWER(TRANSLATE(n.source_name,
                       N'ÁÀÂÄÃáàâäãÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÖÕóòôöõÚÙÛÜúùûüÇçÑñ.-&''',
                       N'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn    ')),
       MIN(n.season_start), MAX(n.season_start)
FROM (
    SELECT f.league_code, f.season_start, r.team1 AS source_name
    FROM silver.match_raw AS r INNER JOIN silver.source_file AS f ON f.source_file = r.source_file
    UNION ALL
    SELECT f.league_code, f.season_start, r.team2
    FROM silver.match_raw AS r INNER JOIN silver.source_file AS f ON f.source_file = r.source_file
) AS n
GROUP BY n.league_code, n.source_name;
GO

/* ---- 2. Split into words, dropping club-type words ----------------------- */
CREATE TABLE silver.team_name_token (
    league_code   VARCHAR(5)     NOT NULL,
    source_name   NVARCHAR(60)   NOT NULL,
    token         NVARCHAR(60)   NOT NULL,
    PRIMARY KEY (league_code, source_name, token)
);

INSERT INTO silver.team_name_token
SELECT DISTINCT t.league_code, t.source_name, s.value
FROM silver.team_name AS t
CROSS APPLY STRING_SPLIT(t.clean_name, ' ') AS s
WHERE s.value <> ''
  AND s.value NOT IN (SELECT token FROM ops.name_stop_token);
GO

/* ---- 3. Score every pair of names in the same league --------------------- */
CREATE TABLE silver.team_name_candidate (
    league_code     VARCHAR(5)     NOT NULL,
    name_a          NVARCHAR(60)   NOT NULL,
    name_b          NVARCHAR(60)   NOT NULL,
    shared_words    INT            NOT NULL,
    name_score      DECIMAL(4, 2)  NOT NULL,
    share_a_season  SMALLINT       NOT NULL,
    decision        VARCHAR(30)    NOT NULL,
    PRIMARY KEY (league_code, name_a, name_b)
);

DECLARE @min_score DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'name_match_min_score');

WITH name_season AS (
    SELECT DISTINCT f.league_code, f.season_start, r.team1 AS source_name
    FROM silver.match_raw AS r INNER JOIN silver.source_file AS f ON f.source_file = r.source_file
    UNION
    SELECT DISTINCT f.league_code, f.season_start, r.team2
    FROM silver.match_raw AS r INNER JOIN silver.source_file AS f ON f.source_file = r.source_file
),
word_count AS (
    SELECT league_code, source_name, COUNT(*) AS words
    FROM silver.team_name_token
    GROUP BY league_code, source_name
),
shared AS (
    SELECT a.league_code, a.source_name AS name_a, b.source_name AS name_b, COUNT(*) AS shared_words
    FROM silver.team_name_token AS a
    INNER JOIN silver.team_name_token AS b
            ON b.league_code = a.league_code AND b.token = a.token AND b.source_name > a.source_name
    GROUP BY a.league_code, a.source_name, b.source_name
),
scored AS (
    SELECT s.league_code, s.name_a, s.name_b, s.shared_words,
           CAST(1.0 * s.shared_words
                / CASE WHEN wa.words < wb.words THEN wa.words ELSE wb.words END AS DECIMAL(4, 2)) AS name_score,
           CASE WHEN EXISTS (
                    SELECT 1
                    FROM name_season AS na
                    INNER JOIN name_season AS nb
                            ON nb.league_code = na.league_code AND nb.season_start = na.season_start
                    WHERE na.league_code = s.league_code
                      AND na.source_name = s.name_a
                      AND nb.source_name = s.name_b)
                THEN 1 ELSE 0 END AS share_a_season
    FROM shared AS s
    INNER JOIN word_count AS wa ON wa.league_code = s.league_code AND wa.source_name = s.name_a
    INNER JOIN word_count AS wb ON wb.league_code = s.league_code AND wb.source_name = s.name_b
)
INSERT INTO silver.team_name_candidate
SELECT league_code, name_a, name_b, shared_words, name_score, share_a_season,
       CASE WHEN name_score < @min_score THEN 'rejected: names differ'
            WHEN share_a_season = 1      THEN 'rejected: same season'
            ELSE 'accepted' END
FROM scored;
GO

/* ---- 4. Alias table: every source name -> one canonical name ------------- */
CREATE TABLE silver.team_alias (
    league_code     VARCHAR(5)     NOT NULL,
    source_name     NVARCHAR(60)   NOT NULL,
    canonical_name  NVARCHAR(60)   NOT NULL,
    matched_by      VARCHAR(20)    NOT NULL,   -- itself / automatic / steward
    PRIMARY KEY (league_code, source_name)
);

-- each name's group = itself plus every name it was accepted against;
-- the canonical name is the group member used most recently
WITH links AS (
    SELECT league_code, name_a AS source_name, name_b AS other_name
    FROM silver.team_name_candidate WHERE decision = 'accepted'
    UNION ALL
    SELECT league_code, name_b, name_a
    FROM silver.team_name_candidate WHERE decision = 'accepted'
    UNION ALL
    SELECT league_code, source_name, source_name FROM silver.team_name
),
ranked AS (
    SELECT l.league_code, l.source_name, l.other_name,
           ROW_NUMBER() OVER (PARTITION BY l.league_code, l.source_name
                              ORDER BY t.last_season DESC, LEN(l.other_name) DESC, l.other_name) AS rn
    FROM links AS l
    INNER JOIN silver.team_name AS t ON t.league_code = l.league_code AND t.source_name = l.other_name
)
INSERT INTO silver.team_alias
SELECT r.league_code, r.source_name,
       COALESCE(o.canonical_name, r.other_name),
       CASE WHEN o.canonical_name IS NOT NULL THEN 'steward'
            WHEN r.other_name = r.source_name THEN 'itself'
            ELSE 'automatic' END
FROM ranked AS r
LEFT JOIN ops.team_alias_override AS o
       ON o.league_code = r.league_code AND o.source_name = r.source_name
WHERE r.rn = 1;
GO

INSERT INTO ops.cleaning_log (step_no, table_name, step_name, rows_affected)
SELECT 3, 'team_alias', 'Team names compared (pairs sharing at least one word)', COUNT(*)
FROM silver.team_name_candidate
UNION ALL
SELECT 4, 'team_alias', 'Team name variants merged automatically', COUNT(*)
FROM silver.team_alias WHERE matched_by = 'automatic'
UNION ALL
SELECT 5, 'team_alias', 'Team name variants merged by steward override', COUNT(*)
FROM silver.team_alias WHERE matched_by = 'steward';

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'silver', 'team_alias', COUNT(*) FROM silver.team_alias;
GO
