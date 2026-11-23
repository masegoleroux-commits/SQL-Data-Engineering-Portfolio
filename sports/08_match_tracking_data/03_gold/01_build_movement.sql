/* =============================================================================
   01_build_movement.sql
   fact_player_sample  GRAIN: one player at one sample, with distance and
                       speed since the previous sample
   fact_sprint         GRAIN: one sprint (an unbroken run of samples above
                       sprint speed, at least min_sprint_samples long)
   dim_player          one player, with time on the pitch and totals

   Speed is only calculated between consecutive samples (frame gap = 5).
   After a substitution or a gap in tracking, the first sample has no speed
   instead of a huge one. Speeds above max_human_speed are tracking
   glitches: they are flagged and left out of distance and sprints.
============================================================================= */

USE MatchTracking;
GO

DROP TABLE IF EXISTS gold.fact_sprint;
DROP TABLE IF EXISTS gold.fact_player_sample;
DROP TABLE IF EXISTS gold.dim_player;
GO

CREATE TABLE gold.fact_player_sample (
    player_code   VARCHAR(10)    NOT NULL,
    frame         INT            NOT NULL,
    period        SMALLINT       NOT NULL,
    x_m           DECIMAL(7, 2)  NOT NULL,
    y_m           DECIMAL(7, 2)  NOT NULL,
    step_m        DECIMAL(7, 3)  NULL,      -- distance since the previous sample
    speed_ms      DECIMAL(6, 2)  NULL,
    is_glitch     SMALLINT       NOT NULL,
    PRIMARY KEY (player_code, frame)
);

DECLARE @step  DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'frame_step');
DECLARE @dt    DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'seconds_per_sample');
DECLARE @max   DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'max_human_speed');

WITH moves AS (
    SELECT p.*,
           LAG(frame) OVER (PARTITION BY player_code ORDER BY frame) AS prev_frame,
           LAG(x_m)   OVER (PARTITION BY player_code ORDER BY frame) AS prev_x,
           LAG(y_m)   OVER (PARTITION BY player_code ORDER BY frame) AS prev_y
    FROM silver.player_position AS p
),
stepped AS (
    SELECT player_code, frame, period, x_m, y_m,
           CASE WHEN frame - prev_frame = @step
                THEN SQRT(SQUARE(x_m - prev_x) + SQUARE(y_m - prev_y)) END AS step_m
    FROM moves
)
INSERT INTO gold.fact_player_sample
SELECT player_code, frame, period, x_m, y_m, step_m, step_m / @dt,
       CASE WHEN step_m / @dt > @max THEN 1 ELSE 0 END
FROM stepped;
GO

/* ---- Sprints: gaps and islands over samples above sprint speed ----------- */
CREATE TABLE gold.fact_sprint (
    player_code   VARCHAR(10)    NOT NULL,
    start_frame   INT            NOT NULL,
    end_frame     INT            NOT NULL,
    period        SMALLINT       NOT NULL,
    samples       INT            NOT NULL,
    duration_s    DECIMAL(6, 1)  NOT NULL,
    distance_m    DECIMAL(7, 1)  NOT NULL,
    top_speed_ms  DECIMAL(6, 2)  NOT NULL,
    PRIMARY KEY (player_code, start_frame)
);

DECLARE @sprint DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'sprint_speed_ms');
DECLARE @min_n  DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'min_sprint_samples');
DECLARE @step   DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'frame_step');
DECLARE @dt     DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'seconds_per_sample');

-- frame / step - row number is constant along an unbroken run of fast
-- samples, so it labels each island
WITH fast AS (
    SELECT player_code, frame, period, step_m, speed_ms,
           frame / @step - ROW_NUMBER() OVER (PARTITION BY player_code ORDER BY frame) AS island
    FROM gold.fact_player_sample
    WHERE speed_ms >= @sprint AND is_glitch = 0
)
INSERT INTO gold.fact_sprint
SELECT player_code, MIN(frame), MAX(frame), MIN(period), COUNT(*), COUNT(*) * @dt,
       SUM(step_m), MAX(speed_ms)
FROM fast
GROUP BY player_code, island
HAVING COUNT(*) >= @min_n;
GO

CREATE TABLE gold.dim_player (
    player_code        VARCHAR(10)    NOT NULL PRIMARY KEY,
    team               VARCHAR(4)     NOT NULL,
    minutes_tracked    DECIMAL(5, 1)  NOT NULL,
    distance_km        DECIMAL(5, 2)  NOT NULL,
    high_speed_km      DECIMAL(5, 2)  NOT NULL,
    sprints            INT            NOT NULL,
    top_speed_kmh      DECIMAL(5, 1)  NULL,
    glitch_samples     INT            NOT NULL
);

DECLARE @hs DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'high_speed_ms');
DECLARE @dt DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'seconds_per_sample');

INSERT INTO gold.dim_player
SELECT s.player_code, ps.team,
       COUNT(*) * @dt / 60,
       COALESCE(SUM(CASE WHEN s.is_glitch = 0 THEN s.step_m END), 0) / 1000,
       COALESCE(SUM(CASE WHEN s.is_glitch = 0 AND s.speed_ms >= @hs THEN s.step_m END), 0) / 1000,
       (SELECT COUNT(*) FROM gold.fact_sprint AS sp WHERE sp.player_code = s.player_code),
       MAX(CASE WHEN s.is_glitch = 0 THEN s.speed_ms END) * 3.6,
       SUM(s.is_glitch)
FROM gold.fact_player_sample AS s
INNER JOIN silver.player_slot AS ps ON ps.player_code = s.player_code
GROUP BY s.player_code, ps.team;
GO

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'gold', 'fact_player_sample', COUNT(*) FROM gold.fact_player_sample UNION ALL
SELECT 'gold', 'fact_sprint',        COUNT(*) FROM gold.fact_sprint UNION ALL
SELECT 'gold', 'dim_player',         COUNT(*) FROM gold.dim_player;
GO
