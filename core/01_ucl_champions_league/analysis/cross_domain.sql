/* =============================================================================
   cross_domain.sql
   Questions that need more than one subject area. These run against the
   reporting views, which join the facts through the conformed dimensions.
============================================================================= */

USE UCL;
GO

-- Thresholds come from dbo.business_parameter (ddl/07_business_parameters.sql).
DECLARE @min_dribbles INT = (SELECT param_value FROM dbo.business_parameter WHERE param_name = 'min_dribbles');

-- 1. Do the best dribblers draw the most fouls?
SELECT TOP (15)
    player_name, club_name, dribbles, fouls_suffered,
    CAST(1.0 * fouls_suffered / NULLIF(dribbles, 0) AS DECIMAL(4, 2)) AS fouls_drawn_per_dribble
FROM dbo.vw_player_season
WHERE dribbles >= @min_dribbles
ORDER BY dribbles DESC;


-- 2. Ball-winners who also keep possession: tackle success and pass completion
SELECT TOP (15)
    player_name, club_name, position, tackles, tackle_success_pct, passes_attempted, pass_completion_pct
FROM dbo.vw_player_season
WHERE tackles >= 15
  AND passes_attempted >= 200
ORDER BY tackle_success_pct + pass_completion_pct DESC;


-- 3. Club scorecard
SELECT club_name, assists, balls_recovered, tackle_success_pct,
       pass_completion_pct, fouls_committed, yellow_cards, red_cards
FROM dbo.vw_club_season
ORDER BY pass_completion_pct DESC;


-- 4. Coverage: how many players appear in each combination of source files
SELECT
    CASE WHEN assists          IS NOT NULL THEN 'A' ELSE '-' END +
    CASE WHEN tackles          IS NOT NULL THEN 'D' ELSE '-' END +
    CASE WHEN passes_attempted IS NOT NULL THEN 'P' ELSE '-' END +
    CASE WHEN fouls_committed  IS NOT NULL THEN 'F' ELSE '-' END AS files_present,   -- Attacking, Defending, Passing, Fouls
    COUNT(*) AS players
FROM dbo.vw_player_season
GROUP BY
    CASE WHEN assists          IS NOT NULL THEN 'A' ELSE '-' END +
    CASE WHEN tackles          IS NOT NULL THEN 'D' ELSE '-' END +
    CASE WHEN passes_attempted IS NOT NULL THEN 'P' ELSE '-' END +
    CASE WHEN fouls_committed  IS NOT NULL THEN 'F' ELSE '-' END
ORDER BY players DESC;
GO
