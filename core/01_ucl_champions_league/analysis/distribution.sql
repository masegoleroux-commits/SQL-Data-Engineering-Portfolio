/* =============================================================================
   distribution.sql
   Passing and crossing, UCL 2021/22. Source table: fact_distribution.

   Completion rates are calculated from the pass counts. The source
   pass_accuracy column does not reconcile to those counts for about half the
   rows, so it is not used for ranking (see docs/data_quality.md).
============================================================================= */

USE UCL;
GO

-- Thresholds come from dbo.business_parameter (ddl/07_business_parameters.sql).
DECLARE @min_passes INT = (SELECT param_value FROM dbo.business_parameter WHERE param_name = 'min_passes'),
        @min_crosses INT = (SELECT param_value FROM dbo.business_parameter WHERE param_name = 'min_crosses'),
        @outperform_margin_pts DECIMAL(5, 2) = (SELECT param_value FROM dbo.business_parameter WHERE param_name = 'outperform_margin_pts');

-- 1. Best pass completion (minimum @min_passes passes attempted)
SELECT TOP (15)
    p.player_name, p.club_name, p.position, f.passes_attempted, f.passes_completed,
    CAST(100.0 * f.passes_completed / f.passes_attempted AS DECIMAL(5, 1)) AS pass_completion_pct
FROM dbo.fact_distribution AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE f.passes_attempted >= @min_passes
ORDER BY pass_completion_pct DESC;


-- 2. Squad size in the dataset by position
SELECT p.position, COUNT(*) AS players
FROM dbo.fact_distribution AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
GROUP BY p.position
ORDER BY players DESC;


-- 3. Most crosses completed
SELECT TOP (10)
    p.player_name, p.club_name, f.crosses_attempted, f.crosses_completed
FROM dbo.fact_distribution AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
ORDER BY f.crosses_completed DESC, f.crosses_attempted ASC;


-- 4. Pass completion by position (weighted by volume, not an average of averages)
SELECT p.position,
       SUM(f.passes_attempted) AS passes_attempted,
       CAST(100.0 * SUM(f.passes_completed) / SUM(f.passes_attempted) AS DECIMAL(5, 1)) AS pass_completion_pct
FROM dbo.fact_distribution AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
GROUP BY p.position
ORDER BY pass_completion_pct DESC;


-- 5. Most free kicks taken
SELECT TOP (10)
    p.player_name, p.club_name, f.free_kicks_taken
FROM dbo.fact_distribution AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
ORDER BY f.free_kicks_taken DESC;


-- 6. Best crossers (minimum @min_crosses crosses attempted)
SELECT TOP (10)
    p.player_name, p.club_name, f.crosses_attempted, f.crosses_completed,
    CAST(100.0 * f.crosses_completed / f.crosses_attempted AS DECIMAL(5, 1)) AS cross_completion_pct
FROM dbo.fact_distribution AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
WHERE f.crosses_attempted >= @min_crosses
ORDER BY cross_completion_pct DESC;


-- 7. Most accurate passer in each position (minimum @min_passes passes)
WITH ranked AS (
    SELECT p.position, p.player_name, p.club_name, f.passes_attempted,
           CAST(100.0 * f.passes_completed / f.passes_attempted AS DECIMAL(5, 1)) AS pass_completion_pct,
           ROW_NUMBER() OVER (PARTITION BY p.position
                              ORDER BY 1.0 * f.passes_completed / f.passes_attempted DESC) AS rn
    FROM dbo.fact_distribution AS f
    INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
    WHERE f.passes_attempted >= @min_passes
)
SELECT position, player_name, club_name, passes_attempted, pass_completion_pct
FROM ranked
WHERE rn = 1;


-- 8. Overall ball delivery: passes and crosses combined
SELECT TOP (15)
    p.player_name, p.club_name,
    f.passes_attempted + f.crosses_attempted AS deliveries_attempted,
    f.passes_completed + f.crosses_completed AS deliveries_completed,
    CAST(100.0 * (f.passes_completed + f.crosses_completed)
               / NULLIF(f.passes_attempted + f.crosses_attempted, 0) AS DECIMAL(5, 1)) AS delivery_completion_pct,
    RANK() OVER (ORDER BY f.passes_completed + f.crosses_completed DESC) AS volume_rank
FROM dbo.fact_distribution AS f
INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
ORDER BY volume_rank;


-- 9. Club passing volume and completion
SELECT c.club_name,
       SUM(f.passes_attempted) AS passes_attempted,
       CAST(100.0 * SUM(f.passes_completed) / SUM(f.passes_attempted) AS DECIMAL(5, 1)) AS pass_completion_pct
FROM dbo.fact_distribution AS f
INNER JOIN dbo.dim_club AS c ON c.club_key = f.club_key
GROUP BY c.club_name
ORDER BY passes_attempted DESC;


-- 10. Players beating their position's completion rate by @outperform_margin_pts+ points (min @min_passes passes)
WITH position_avg AS (
    SELECT p.position,
           100.0 * SUM(f.passes_completed) / SUM(f.passes_attempted) AS position_pct
    FROM dbo.fact_distribution AS f
    INNER JOIN dbo.dim_player AS p ON p.player_key = f.player_key
    GROUP BY p.position
)
SELECT p.player_name, p.club_name, p.position,
       CAST(100.0 * f.passes_completed / f.passes_attempted AS DECIMAL(5, 1)) AS player_pct,
       CAST(a.position_pct AS DECIMAL(5, 1))                                 AS position_pct
FROM dbo.fact_distribution AS f
INNER JOIN dbo.dim_player  AS p ON p.player_key = f.player_key
INNER JOIN position_avg    AS a ON a.position   = p.position
WHERE f.passes_attempted >= @min_passes
  AND 100.0 * f.passes_completed / f.passes_attempted >= a.position_pct + @outperform_margin_pts
ORDER BY player_pct DESC;
GO
