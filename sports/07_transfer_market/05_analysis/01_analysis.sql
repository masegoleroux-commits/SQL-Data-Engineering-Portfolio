/* =============================================================================
   01_analysis.sql
============================================================================= */

USE TransferMarket;
GO

/* ---- 1. Net spend by club, all seasons ----------------------------------- */
-- club-side table: every club's own purchases and sales count
SELECT c.club_name,
       COUNT(DISTINCT f.season_start)                                       AS seasons,
       CAST(SUM(CASE WHEN f.movement = 'in'  THEN COALESCE(f.fee_eur_m, 0) ELSE 0 END) AS DECIMAL(9, 1)) AS spent,
       CAST(SUM(CASE WHEN f.movement = 'out' THEN COALESCE(f.fee_eur_m, 0) ELSE 0 END) AS DECIMAL(9, 1)) AS received,
       CAST(SUM(f.spend_eur_m) AS DECIMAL(9, 1))                             AS net_spend,
       CAST(SUM(f.spend_eur_m) / COUNT(DISTINCT f.season_start) AS DECIMAL(7, 1)) AS net_spend_per_season
FROM gold.fact_club_transfer AS f
INNER JOIN gold.dim_club AS c ON c.club_key = f.club_key
GROUP BY c.club_name
ORDER BY net_spend DESC;
GO

/* ---- 2. Fee inflation index ---------------------------------------------- */
-- average known permanent fee per season, base_year = 100.
-- move-level table, so a PL-to-PL fee is counted once
DECLARE @base DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'base_year');

WITH by_year AS (
    SELECT season_start, COUNT(*) AS paid_moves, AVG(fee_eur_m) AS avg_fee, MAX(fee_eur_m) AS top_fee
    FROM gold.fact_transfer
    WHERE fee_type = 'permanent' AND fee_eur_m > 0
    GROUP BY season_start
)
SELECT y.season_start, y.paid_moves,
       CAST(y.avg_fee AS DECIMAL(7, 2)) AS avg_fee_eur_m,
       CAST(y.top_fee AS DECIMAL(7, 1)) AS top_fee_eur_m,
       CAST(100 * y.avg_fee / b.avg_fee AS DECIMAL(7, 0)) AS fee_index
FROM by_year AS y
CROSS JOIN (SELECT avg_fee FROM by_year WHERE season_start = @base) AS b
ORDER BY y.season_start;
GO

/* ---- 3. Major signings --------------------------------------------------- */
DECLARE @big DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'big_fee_millions');

SELECT season_start, window_name, player_name, from_club, to_club,
       CAST(fee_eur_m AS DECIMAL(7, 1)) AS fee_eur_m
FROM gold.fact_transfer
WHERE fee_type = 'permanent' AND fee_eur_m >= @big
ORDER BY fee_eur_m DESC;
GO

/* ---- 4. How moves are done: loans, free transfers and fees over time ----- */
SELECT (season_start / 5) * 5 AS five_years_from,
       COUNT(*) AS moves,
       CAST(100.0 * SUM(CASE WHEN fee_type IN ('loan', 'loan with fee') THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 1)) AS loan_pct,
       CAST(100.0 * SUM(CASE WHEN fee_type = 'free'      THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 1)) AS free_pct,
       CAST(100.0 * SUM(CASE WHEN fee_type = 'permanent' THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 1)) AS paid_pct,
       CAST(100.0 * SUM(CASE WHEN fee_type = 'unknown'   THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 1)) AS fee_unknown_pct
FROM gold.fact_transfer
WHERE fee_type <> 'loan return'
GROUP BY (season_start / 5) * 5
ORDER BY five_years_from;
GO

/* ---- 5. Which positions cost most ---------------------------------------- */
SELECT f.position_group,
       COUNT(*) AS paid_moves,
       CAST(AVG(f.fee_eur_m) AS DECIMAL(6, 2)) AS avg_fee_eur_m,
       CAST(AVG(1.0 * f.age) AS DECIMAL(4, 1)) AS avg_age
FROM gold.fact_club_transfer AS f
WHERE f.movement = 'in' AND f.fee_type = 'permanent' AND f.fee_eur_m > 0 AND f.season_start >= 2015
GROUP BY f.position_group
ORDER BY avg_fee_eur_m DESC;
GO
