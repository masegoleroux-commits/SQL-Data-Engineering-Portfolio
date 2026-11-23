/* =============================================================================
   01_quality_checks.sql
============================================================================= */

USE TransferMarket;
GO

DROP TABLE IF EXISTS ops.test_result;
CREATE TABLE ops.test_result (
    test_name  VARCHAR(120)  NOT NULL,
    expected   BIGINT        NULL,
    actual     BIGINT        NULL
);

DECLARE @tol DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'fee_tolerance');

INSERT INTO ops.test_result
SELECT 'bronze -> silver: distinct rows kept',
       (SELECT COUNT(*) FROM (SELECT DISTINCT club_name, player_name, age, position, club_involved_name, fee,
                                     transfer_movement, transfer_period, fee_cleaned, year
                              FROM bronze.premier_league_transfers) AS d),
       (SELECT COUNT(*) FROM silver.transfer_row);

INSERT INTO ops.test_result
SELECT 'every fee text matched a known pattern', 0, COUNT(*)
FROM silver.transfer_row WHERE fee_type = 'unknown' AND fee_text NOT IN ('?', '-');

INSERT INTO ops.test_result
SELECT 'every paid fee was parsed to a number', 0, COUNT(*)
FROM silver.transfer_row WHERE fee_type IN ('permanent', 'loan with fee') AND fee_eur_m IS NULL;

-- the source carries its own cleaned fee; the parser must agree with it
INSERT INTO ops.test_result
SELECT 'parsed fee = source cleaned fee', 0, COUNT(*)
FROM silver.transfer_row
WHERE fee_eur_m IS NOT NULL AND ABS(fee_eur_m - COALESCE(source_fee_eur_m, -1)) > @tol;

INSERT INTO ops.test_result
SELECT 'every source position mapped to a group', 0, COUNT(*)
FROM silver.transfer_row WHERE position_group IS NULL;

INSERT INTO ops.test_result
SELECT 'learned aliases only point to real Premier League clubs', 0, COUNT(*)
FROM silver.club_alias WHERE full_name NOT IN (SELECT club_name FROM gold.dim_club);

INSERT INTO ops.test_result
SELECT 'fact_transfer = club rows minus mirrors',
       (SELECT COUNT(*) FROM gold.fact_club_transfer WHERE is_mirror = 0),
       (SELECT COUNT(*) FROM gold.fact_transfer);

-- every mirror must have exactly one matching buyer row. Fee type and
-- amount are part of the match: a player can join on loan and then sign
-- permanently in the same window (Chris Kirkland, Liverpool to Wigan, 2006)
INSERT INTO ops.test_result
SELECT 'mirrors pair up one to one with a buying club row', 0, COUNT(*)
FROM gold.fact_club_transfer AS m
WHERE m.is_mirror = 1
  AND (SELECT COUNT(*) FROM gold.fact_club_transfer AS i
       INNER JOIN gold.dim_club AS ci ON ci.club_key = i.club_key
       INNER JOIN gold.dim_club AS cm ON cm.club_key = m.club_key
       WHERE i.movement = 'in' AND i.player_name = m.player_name
         AND i.season_start = m.season_start AND i.window_name = m.window_name
         AND i.fee_type = m.fee_type AND COALESCE(i.fee_eur_m, -1) = COALESCE(m.fee_eur_m, -1)
         AND ci.club_name = m.other_club AND i.other_club = cm.club_name) <> 1;

SELECT test_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM ops.test_result;

IF EXISTS (SELECT 1 FROM ops.test_result WHERE actual IS NULL OR expected <> actual)
    THROW 50001, 'Quality checks failed. See the results grid.', 1;
GO
