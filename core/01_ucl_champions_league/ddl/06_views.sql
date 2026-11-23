/* =============================================================================
   06_views.sql
   Reporting views over the star schema. Ratios live here, not in the facts.

   vw_player_season  one row per dim_player row, every subject area joined in.
                     LEFT JOINs because coverage differs by file: a player can
                     have defending stats but no attacking row (no assists).
                     Each fact is 1:1 with dim_player, so no row multiplication.

   vw_club_season    one row per club. Each fact is aggregated to club level
                     BEFORE joining, which avoids the fan-out you get from
                     joining four player-level facts and then grouping.
============================================================================= */

USE UCL;
GO

CREATE OR ALTER VIEW dbo.vw_player_season
AS
SELECT
    p.player_key,
    p.player_name,
    p.club_name,
    p.position,
    COALESCE(dc.matches_played, dd.matches_played, ds.matches_played, a.matches_played) AS matches_played,
    dc.minutes_played,

    -- attacking
    a.assists,
    a.dribbles,
    a.offsides,
    a.corners_taken,

    -- defending
    dd.balls_recovered,
    dd.tackles,
    dd.tackles_won,
    dd.clearances_attempted,
    CAST(100.0 * dd.tackles_won / NULLIF(dd.tackles, 0) AS DECIMAL(5, 1))              AS tackle_success_pct,

    -- distribution
    ds.passes_attempted,
    ds.passes_completed,
    CAST(100.0 * ds.passes_completed / NULLIF(ds.passes_attempted, 0) AS DECIMAL(5, 1)) AS pass_completion_pct,
    ds.crosses_attempted,
    ds.crosses_completed,
    CAST(100.0 * ds.crosses_completed / NULLIF(ds.crosses_attempted, 0) AS DECIMAL(5, 1)) AS cross_completion_pct,
    ds.free_kicks_taken,

    -- discipline
    dc.fouls_committed,
    dc.fouls_suffered,
    dc.yellow_cards,
    dc.red_cards,
    CAST(90.0 * dc.fouls_committed / NULLIF(dc.minutes_played, 0) AS DECIMAL(5, 2))     AS fouls_committed_per_90
FROM dbo.dim_player             AS p
LEFT JOIN dbo.fact_attacking    AS a  ON a.player_key  = p.player_key
LEFT JOIN dbo.fact_defending    AS dd ON dd.player_key = p.player_key
LEFT JOIN dbo.fact_distribution AS ds ON ds.player_key = p.player_key
LEFT JOIN dbo.fact_discipline   AS dc ON dc.player_key = p.player_key;
GO

CREATE OR ALTER VIEW dbo.vw_club_season
AS
WITH att AS (
    SELECT club_key, SUM(assists) AS assists, SUM(dribbles) AS dribbles
    FROM dbo.fact_attacking
    GROUP BY club_key
),
def AS (
    SELECT club_key, SUM(balls_recovered) AS balls_recovered, SUM(tackles) AS tackles,
           SUM(tackles_won) AS tackles_won, SUM(clearances_attempted) AS clearances_attempted
    FROM dbo.fact_defending
    GROUP BY club_key
),
dist AS (
    SELECT club_key, SUM(passes_attempted) AS passes_attempted, SUM(passes_completed) AS passes_completed
    FROM dbo.fact_distribution
    GROUP BY club_key
),
disc AS (
    SELECT club_key, SUM(fouls_committed) AS fouls_committed, SUM(yellow_cards) AS yellow_cards,
           SUM(red_cards) AS red_cards
    FROM dbo.fact_discipline
    GROUP BY club_key
)
SELECT
    c.club_key,
    c.club_name,
    att.assists,
    att.dribbles,
    def.balls_recovered,
    def.tackles,
    def.tackles_won,
    CAST(100.0 * def.tackles_won / NULLIF(def.tackles, 0) AS DECIMAL(5, 1))                AS tackle_success_pct,
    def.clearances_attempted,
    dist.passes_attempted,
    dist.passes_completed,
    CAST(100.0 * dist.passes_completed / NULLIF(dist.passes_attempted, 0) AS DECIMAL(5, 1)) AS pass_completion_pct,
    disc.fouls_committed,
    disc.yellow_cards,
    disc.red_cards
FROM dbo.dim_club AS c
LEFT JOIN att  ON att.club_key  = c.club_key
LEFT JOIN def  ON def.club_key  = c.club_key
LEFT JOIN dist ON dist.club_key = c.club_key
LEFT JOIN disc ON disc.club_key = c.club_key;
GO
