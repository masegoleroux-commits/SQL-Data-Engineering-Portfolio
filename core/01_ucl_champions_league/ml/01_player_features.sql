/* =============================================================================
   01_player_features.sql
   Builds ml.player_features: one row per outfield player, with per-90 rates
   and standardised (z-score) versions of each rate. This is the input to the
   similarity search in 02_similar_players.sql, and it is the same shape a
   Python or Azure ML model would expect: one row per entity, numeric
   columns, no NULLs.

   Feature choices
   ---------------
   * Rates are per 90 minutes, so a substitute and a starter are comparable.
   * Players need at least min_minutes (business_parameter) to be included.
     Rates based on a handful of minutes are noise.
   * Goalkeepers are excluded. Their profile (few tackles, many long passes)
     would dominate the scaling for everyone else.
   * Assists: attacking.csv only lists players with at least one assist, so a
     player missing from that file has 0 assists. COALESCE to 0 is correct.
   * Dribbles, offsides and corners are NOT used. They also come from
     attacking.csv, so they are unknown (not zero) for players without an
     assist. Filling them with 0 would teach the model something false.
   * Tackle success % is undefined when a player made no tackles. Those rows
     get the position average, so they are neither rewarded nor punished.
   * z-scores are calculated within each position: a defender's tackle rate
     is compared with other defenders, not with forwards.
============================================================================= */

USE UCL;
GO

IF SCHEMA_ID(N'ml') IS NULL
    EXEC (N'CREATE SCHEMA ml AUTHORIZATION dbo;');
GO

SET NOCOUNT ON;

DECLARE @min_minutes INT = (SELECT param_value FROM dbo.business_parameter WHERE param_name = 'min_minutes');

DROP TABLE IF EXISTS ml.player_features;

WITH base AS (
    SELECT
        p.player_key,
        p.player_name,
        p.club_name,
        p.position,
        dc.minutes_played,
        90.0 * ds.passes_attempted            / dc.minutes_played AS passes_p90,
        100.0 * ds.passes_completed           / NULLIF(ds.passes_attempted, 0) AS pass_completion_pct,
        90.0 * ds.crosses_attempted           / dc.minutes_played AS crosses_p90,
        90.0 * dd.balls_recovered             / dc.minutes_played AS recoveries_p90,
        90.0 * dd.tackles                     / dc.minutes_played AS tackles_p90,
        100.0 * dd.tackles_won                / NULLIF(dd.tackles, 0) AS tackle_success_raw,
        90.0 * dd.clearances_attempted        / dc.minutes_played AS clearances_p90,
        90.0 * dc.fouls_committed             / dc.minutes_played AS fouls_p90,
        90.0 * dc.fouls_suffered              / dc.minutes_played AS fouled_p90,
        90.0 * COALESCE(a.assists, 0)         / dc.minutes_played AS assists_p90
    FROM dbo.dim_player             AS p
    INNER JOIN dbo.fact_discipline   AS dc ON dc.player_key = p.player_key
    INNER JOIN dbo.fact_distribution AS ds ON ds.player_key = p.player_key
    INNER JOIN dbo.fact_defending    AS dd ON dd.player_key = p.player_key
    LEFT  JOIN dbo.fact_attacking    AS a  ON a.player_key  = p.player_key
    WHERE p.position <> N'Goalkeeper'
      AND dc.minutes_played >= @min_minutes
),
imputed AS (
    SELECT b.*,
           COALESCE(b.tackle_success_raw,
                    AVG(b.tackle_success_raw) OVER (PARTITION BY b.position)) AS tackle_success_pct,
           CASE WHEN b.tackle_success_raw IS NULL THEN 1 ELSE 0 END          AS tackle_success_imputed
    FROM base AS b
)
SELECT
    player_key, player_name, club_name, position, minutes_played,
    CAST(passes_p90          AS DECIMAL(9, 3)) AS passes_p90,
    CAST(pass_completion_pct AS DECIMAL(9, 3)) AS pass_completion_pct,
    CAST(crosses_p90         AS DECIMAL(9, 3)) AS crosses_p90,
    CAST(recoveries_p90      AS DECIMAL(9, 3)) AS recoveries_p90,
    CAST(tackles_p90         AS DECIMAL(9, 3)) AS tackles_p90,
    CAST(tackle_success_pct  AS DECIMAL(9, 3)) AS tackle_success_pct,
    tackle_success_imputed,
    CAST(clearances_p90      AS DECIMAL(9, 3)) AS clearances_p90,
    CAST(fouls_p90           AS DECIMAL(9, 3)) AS fouls_p90,
    CAST(fouled_p90          AS DECIMAL(9, 3)) AS fouled_p90,
    CAST(assists_p90         AS DECIMAL(9, 3)) AS assists_p90,
    -- z-score = (value - position mean) / position standard deviation
    -- (written out per column because the WINDOW clause needs SQL Server 2022)
    CAST((passes_p90          - AVG(passes_p90)          OVER (PARTITION BY position)) / NULLIF(STDEV(passes_p90)          OVER (PARTITION BY position), 0) AS DECIMAL(9, 4)) AS z_passes,
    CAST((pass_completion_pct - AVG(pass_completion_pct) OVER (PARTITION BY position)) / NULLIF(STDEV(pass_completion_pct) OVER (PARTITION BY position), 0) AS DECIMAL(9, 4)) AS z_pass_completion,
    CAST((crosses_p90         - AVG(crosses_p90)         OVER (PARTITION BY position)) / NULLIF(STDEV(crosses_p90)         OVER (PARTITION BY position), 0) AS DECIMAL(9, 4)) AS z_crosses,
    CAST((recoveries_p90      - AVG(recoveries_p90)      OVER (PARTITION BY position)) / NULLIF(STDEV(recoveries_p90)      OVER (PARTITION BY position), 0) AS DECIMAL(9, 4)) AS z_recoveries,
    CAST((tackles_p90         - AVG(tackles_p90)         OVER (PARTITION BY position)) / NULLIF(STDEV(tackles_p90)         OVER (PARTITION BY position), 0) AS DECIMAL(9, 4)) AS z_tackles,
    CAST((tackle_success_pct  - AVG(tackle_success_pct)  OVER (PARTITION BY position)) / NULLIF(STDEV(tackle_success_pct)  OVER (PARTITION BY position), 0) AS DECIMAL(9, 4)) AS z_tackle_success,
    CAST((clearances_p90      - AVG(clearances_p90)      OVER (PARTITION BY position)) / NULLIF(STDEV(clearances_p90)      OVER (PARTITION BY position), 0) AS DECIMAL(9, 4)) AS z_clearances,
    CAST((fouls_p90           - AVG(fouls_p90)           OVER (PARTITION BY position)) / NULLIF(STDEV(fouls_p90)           OVER (PARTITION BY position), 0) AS DECIMAL(9, 4)) AS z_fouls,
    CAST((fouled_p90          - AVG(fouled_p90)          OVER (PARTITION BY position)) / NULLIF(STDEV(fouled_p90)          OVER (PARTITION BY position), 0) AS DECIMAL(9, 4)) AS z_fouled,
    CAST((assists_p90         - AVG(assists_p90)         OVER (PARTITION BY position)) / NULLIF(STDEV(assists_p90)         OVER (PARTITION BY position), 0) AS DECIMAL(9, 4)) AS z_assists
INTO ml.player_features
FROM imputed;
GO
