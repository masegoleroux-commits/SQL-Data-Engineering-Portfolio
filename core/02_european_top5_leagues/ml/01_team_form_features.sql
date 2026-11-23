/* =============================================================================
   01_team_form_features.sql
   Stage 5a: rolling "form" features for every team before every match.

   The most important rule in building model features: only use information
   that was available BEFORE kick-off. A feature that includes the match
   being predicted (data leakage) makes a model look brilliant in testing
   and useless in real life.

   So each row looks back over the team's previous @form_window matches and
   never includes the current one. The window size is a business parameter.
   A window frame like ROWS BETWEEN 5 PRECEDING cannot take a variable in
   T-SQL, so the look-back is done with a self-join on a match sequence
   number instead.
============================================================================= */

USE EuroLeagues;
GO

SET NOCOUNT ON;

DECLARE @form_window INT = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'form_window');

DROP TABLE IF EXISTS ml.team_match_features;

WITH seq AS (
    SELECT tm.*,
           ROW_NUMBER() OVER (PARTITION BY tm.team_key ORDER BY tm.date_key, tm.match_key) AS match_seq,
           LAG(tm.date_key) OVER (PARTITION BY tm.team_key ORDER BY tm.date_key, tm.match_key) AS prev_date_key
    FROM dw.fact_team_match AS tm
)
SELECT
    cur.match_key,
    cur.team_key,
    cur.is_home,
    cur.season_key,
    cur.match_seq,
    COUNT(prev.match_key)                                         AS form_matches,       -- < window at the start
    CAST(AVG(1.0 * prev.points)        AS DECIMAL(5, 3))          AS form_points_avg,
    CAST(AVG(1.0 * prev.goals_for)     AS DECIMAL(5, 3))          AS form_goals_for_avg,
    CAST(AVG(1.0 * prev.goals_against) AS DECIMAL(5, 3))          AS form_goals_against_avg,
    -- shots on target only from matches where statistics exist
    CAST(AVG(CASE WHEN prev.stats_complete = 1 THEN 1.0 * prev.shots_on_target_for END) AS DECIMAL(5, 3))
                                                                  AS form_sot_for_avg,
    DATEDIFF(DAY,
             CONVERT(DATE, CONVERT(CHAR(8), cur.prev_date_key)),
             CONVERT(DATE, CONVERT(CHAR(8), cur.date_key)))       AS rest_days
INTO ml.team_match_features
FROM seq AS cur
LEFT JOIN seq AS prev
    ON  prev.team_key  = cur.team_key
    AND prev.match_seq BETWEEN cur.match_seq - @form_window AND cur.match_seq - 1
GROUP BY cur.match_key, cur.team_key, cur.is_home, cur.season_key, cur.match_seq,
         cur.prev_date_key, cur.date_key;

ALTER TABLE ml.team_match_features
    ADD CONSTRAINT pk_team_match_features PRIMARY KEY (match_key, team_key);
GO

SELECT TOP (10) f.*
FROM ml.team_match_features AS f
INNER JOIN dw.dim_team AS t ON t.team_key = f.team_key
WHERE t.team_name = N'Bayer Leverkusen'
ORDER BY f.match_seq;
GO
