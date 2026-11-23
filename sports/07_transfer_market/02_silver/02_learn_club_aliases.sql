/* =============================================================================
   02_learn_club_aliases.sql
   Learns which short club names ('Spurs', 'Man Utd', 'Sheff Wed') mean which
   full club names ('Tottenham Hotspur', 'Manchester United', ...), from the
   data itself.

   The evidence: when two Premier League clubs trade a player, the move is
   recorded twice. Club A's record says "in, from Spurs"; Club B's record
   says "out, to Leicester". Both rows share the player, season, window and
   fee text. Every such pair is one vote that A's short name for B is B's
   full name, and the other way round.

   A short name is linked to the full name with the most votes when:
     - it has at least alias_min_evidence votes, and
     - the winner holds at least alias_min_share of all votes for that name
   Coincidences (a player who passed through a third club in the same
   window) produce one or two stray votes and are filtered out by these two
   rules. Values that are not clubs ('Without Club') are never linked.

   silver.club_alias_vote  every vote, kept for explanation
   silver.club_alias       GRAIN: one short name -> one full club name
============================================================================= */

USE TransferMarket;
GO

DROP TABLE IF EXISTS silver.club_alias;
DROP TABLE IF EXISTS silver.club_alias_vote;
GO

CREATE TABLE silver.club_alias_vote (
    short_name   NVARCHAR(60)  NOT NULL,
    full_name    NVARCHAR(60)  NOT NULL,
    votes        INT           NOT NULL,
    PRIMARY KEY (short_name, full_name)
);

WITH pairs AS (
    SELECT a.club_involved AS a_says, b.club_name AS b_is,
           b.club_involved AS b_says, a.club_name AS a_is
    FROM silver.transfer_row AS a
    INNER JOIN silver.transfer_row AS b
            ON b.player_name  = a.player_name
           AND b.season_start = a.season_start
           AND b.window_name  = a.window_name
           AND COALESCE(b.fee_text, '') = COALESCE(a.fee_text, '')
           AND b.club_name   <> a.club_name
    WHERE a.movement = 'in' AND b.movement = 'out'
),
votes AS (
    SELECT a_says AS short_name, b_is AS full_name FROM pairs
    UNION ALL
    SELECT b_says, a_is FROM pairs
)
INSERT INTO silver.club_alias_vote
SELECT short_name, full_name, COUNT(*)
FROM votes
WHERE short_name NOT IN (SELECT value_text FROM ops.non_club_value)
GROUP BY short_name, full_name;
GO

CREATE TABLE silver.club_alias (
    short_name    NVARCHAR(60)   NOT NULL PRIMARY KEY,
    full_name     NVARCHAR(60)   NOT NULL,
    votes         INT            NOT NULL,
    vote_share    DECIMAL(5, 3)  NOT NULL
);

DECLARE @min_votes DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'alias_min_evidence');
DECLARE @min_share DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'alias_min_share');

INSERT INTO silver.club_alias
SELECT short_name, full_name, votes, share
FROM (
    SELECT short_name, full_name, votes,
           1.0 * votes / SUM(votes) OVER (PARTITION BY short_name) AS share,
           ROW_NUMBER() OVER (PARTITION BY short_name ORDER BY votes DESC, full_name) AS rn
    FROM silver.club_alias_vote
) AS x
WHERE rn = 1 AND votes >= @min_votes AND share >= @min_share;
GO

INSERT INTO ops.cleaning_log (step_no, table_name, step_name, rows_affected)
SELECT 7, 'club_alias', 'Short club names linked to a full name from mirrored transfers', COUNT(*) FROM silver.club_alias
UNION ALL
SELECT 8, 'club_alias', 'Short names with votes that were NOT linked (too few or split votes)',
       COUNT(DISTINCT short_name) FROM silver.club_alias_vote
       WHERE short_name NOT IN (SELECT short_name FROM silver.club_alias);

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'silver', 'club_alias', COUNT(*) FROM silver.club_alias;
GO
