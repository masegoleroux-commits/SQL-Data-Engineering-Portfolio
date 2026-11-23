/* =============================================================================
   01_similar_players.sql
   "Which past players had a season most like this one?" A nearest-neighbour
   search, the method behind player-comparison tools.

   Each qualified season becomes a point in six dimensions, using the
   season z-scores of: box offense, box defense, on/off offense, on/off
   defense, predator total and pace impact. Z-scores put every metric on
   the same scale, so no single metric dominates the distance.

   For every player in comparison_season, the distance to every other
   player's season is calculated (Euclidean: square root of the summed
   squared differences) and the closest similar_players are kept. The
   player's own seasons are excluded, so the match is always someone else.

   similarity = 1 / (1 + distance), so 1.00 would be an identical season.
============================================================================= */

USE NbaPlayerImpact;
GO

DROP TABLE IF EXISTS ml.similar_player;
DROP TABLE IF EXISTS ml.player_vector;
GO

CREATE TABLE ml.player_vector (
    player_id   VARCHAR(10)   NOT NULL,
    season      SMALLINT      NOT NULL,
    z_box_off   DECIMAL(8, 3) NOT NULL,
    z_box_def   DECIMAL(8, 3) NOT NULL,
    z_onoff_off DECIMAL(8, 3) NOT NULL,
    z_onoff_def DECIMAL(8, 3) NOT NULL,
    z_predator  DECIMAL(8, 3) NOT NULL,
    z_pace      DECIMAL(8, 3) NOT NULL,
    PRIMARY KEY (player_id, season)
);

-- long back to wide: one row per player season, one column per metric
INSERT INTO ml.player_vector
SELECT player_id, season,
       MAX(CASE WHEN metric = 'box_offense'    THEN z_score END),
       MAX(CASE WHEN metric = 'box_defense'    THEN z_score END),
       MAX(CASE WHEN metric = 'onoff_offense'  THEN z_score END),
       MAX(CASE WHEN metric = 'onoff_defense'  THEN z_score END),
       MAX(CASE WHEN metric = 'predator_total' THEN z_score END),
       MAX(CASE WHEN metric = 'pace_impact'    THEN z_score END)
FROM gold.fact_player_metric
GROUP BY player_id, season;
GO

CREATE TABLE ml.similar_player (
    player_id        VARCHAR(10)    NOT NULL,
    season           SMALLINT       NOT NULL,
    match_rank       INT            NOT NULL,
    similar_id       VARCHAR(10)    NOT NULL,
    similar_season   SMALLINT       NOT NULL,
    distance         DECIMAL(8, 3)  NOT NULL,
    similarity       DECIMAL(5, 3)  NOT NULL,
    PRIMARY KEY (player_id, season, match_rank)
);

DECLARE @season DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'comparison_season');
DECLARE @top    DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'similar_players');

WITH pairs AS (
    SELECT a.player_id, a.season, b.player_id AS similar_id, b.season AS similar_season,
           SQRT(  SQUARE(a.z_box_off   - b.z_box_off)
                + SQUARE(a.z_box_def   - b.z_box_def)
                + SQUARE(a.z_onoff_off - b.z_onoff_off)
                + SQUARE(a.z_onoff_def - b.z_onoff_def)
                + SQUARE(a.z_predator  - b.z_predator)
                + SQUARE(a.z_pace      - b.z_pace)) AS distance
    FROM ml.player_vector AS a
    INNER JOIN ml.player_vector AS b ON b.player_id <> a.player_id
    WHERE a.season = @season
),
ranked AS (
    SELECT p.*, ROW_NUMBER() OVER (PARTITION BY player_id, season ORDER BY distance, similar_id, similar_season) AS rn
    FROM pairs AS p
)
INSERT INTO ml.similar_player
SELECT player_id, season, rn, similar_id, similar_season, distance, 1.0 / (1.0 + distance)
FROM ranked
WHERE rn <= @top;
GO

-- the five best players of the comparison season and their closest matches
SELECT d.player_name, s.season, s.match_rank, ds.player_name AS similar_to, s.similar_season,
       s.similarity
FROM ml.similar_player AS s
INNER JOIN gold.dim_player AS d  ON d.player_id  = s.player_id  AND d.is_current = 1
INNER JOIN gold.dim_player AS ds ON ds.player_id = s.similar_id AND s.similar_season BETWEEN ds.valid_from AND ds.valid_to
WHERE s.player_id IN (SELECT TOP (5) player_id FROM gold.fact_player_season
                      WHERE season = s.season ORDER BY war_total DESC)
ORDER BY d.player_name, s.match_rank;
GO
