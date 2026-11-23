/* =============================================================================
   01_possession_inference.sql
   Infers who has the ball at every moment from raw positions alone, then
   compares the result with the hand-coded event log.

   For each sample where the ball is visible:
     1. Find the player nearest the ball (a set-based "nearest neighbour":
        distance to all players, ROW_NUMBER over distance).
     2. If that player is within control_distance_m, his team is in
        possession. If nobody is that close, the ball is loose.
     3. Possession carries forward through loose samples until the other
        team touches the ball: a pass in flight still belongs to the
        passing team. The carry-forward uses a running MAX over the
        samples where someone was in control (gaps and islands).

   The event log gives a second opinion: each event's team. Comparing the
   two shows how far tracking alone can go without manual coding.
============================================================================= */

USE MatchTracking;
GO

DROP TABLE IF EXISTS ml.possession_metric;
DROP TABLE IF EXISTS ml.inferred_possession;
GO

CREATE TABLE ml.inferred_possession (
    frame            INT            NOT NULL PRIMARY KEY,
    period           SMALLINT       NOT NULL,
    nearest_player   VARCHAR(10)    NULL,
    nearest_team     VARCHAR(4)     NULL,
    nearest_dist_m   DECIMAL(6, 2)  NULL,
    in_control_team  VARCHAR(4)     NULL,     -- team within control distance, else NULL
    possession_team  VARCHAR(4)     NULL      -- carried forward through loose samples
);

DECLARE @control DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'control_distance_m');

WITH distances AS (
    SELECT b.frame, b.period, p.player_code, ps.team,
           SQRT(SQUARE(p.x_m - b.ball_x_m) + SQUARE(p.y_m - b.ball_y_m)) AS dist_m,
           ROW_NUMBER() OVER (PARTITION BY b.frame
                              ORDER BY SQUARE(p.x_m - b.ball_x_m) + SQUARE(p.y_m - b.ball_y_m), p.player_code) AS rn
    FROM silver.ball_frame AS b
    INNER JOIN silver.player_position AS p  ON p.frame = b.frame
    INNER JOIN silver.player_slot     AS ps ON ps.player_code = p.player_code
    WHERE b.ball_x_m IS NOT NULL
),
nearest AS (
    SELECT frame, period, player_code, team, dist_m,
           CASE WHEN dist_m <= @control THEN team END AS in_control_team
    FROM distances
    WHERE rn = 1
),
marked AS (
    -- the last frame (so far) at which someone was in control
    SELECT n.*,
           MAX(CASE WHEN in_control_team IS NOT NULL THEN frame END)
               OVER (PARTITION BY period ORDER BY frame ROWS UNBOUNDED PRECEDING) AS last_control_frame
    FROM nearest AS n
)
INSERT INTO ml.inferred_possession
SELECT m.frame, m.period, m.player_code, m.team, m.dist_m, m.in_control_team,
       c.in_control_team
FROM marked AS m
LEFT JOIN nearest AS c ON c.frame = m.last_control_frame;
GO

/* ---- Compare with the event log ----------------------------------------- */
CREATE TABLE ml.possession_metric (
    metric_name   VARCHAR(80)    NOT NULL PRIMARY KEY,
    metric_value  DECIMAL(10, 2) NOT NULL
);

INSERT INTO ml.possession_metric
SELECT 'samples with the ball visible', COUNT(*) FROM ml.inferred_possession
UNION ALL
SELECT 'share of samples with a player in control (%)',
       100.0 * SUM(CASE WHEN in_control_team IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*) FROM ml.inferred_possession
UNION ALL
SELECT 'home possession from tracking (%)',
       100.0 * SUM(CASE WHEN possession_team = 'Home' THEN 1 ELSE 0 END)
       / SUM(CASE WHEN possession_team IS NOT NULL THEN 1 ELSE 0 END)
FROM ml.inferred_possession
UNION ALL
SELECT 'home share of events in the event log (%)',
       100.0 * SUM(CASE WHEN team = 'Home' THEN 1 ELSE 0 END) / COUNT(*) FROM silver.match_event
UNION ALL
SELECT 'passes where tracking agrees with the passing team (%)',
       100.0 * SUM(CASE WHEN ip.possession_team = e.team THEN 1 ELSE 0 END) / COUNT(*)
FROM silver.match_event AS e
INNER JOIN ml.inferred_possession AS ip ON ip.frame = e.sample_frame
WHERE e.event_type = 'PASS' AND ip.possession_team IS NOT NULL;

SELECT metric_name, metric_value FROM ml.possession_metric;
GO
