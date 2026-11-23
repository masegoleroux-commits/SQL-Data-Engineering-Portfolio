/* =============================================================================
   01_build_silver.sql
   silver.player_slot      GRAIN: one team, one column slot -> one player
   silver.ball_frame       GRAIN: one sample (period + frame)
   silver.player_position  GRAIN: one player at one sample, in metres
   silver.match_event      GRAIN: one event

   Cleaning steps, each counted in ops.cleaning_log:
     1. Player slots read from header row 3 (Player11, Player1 ...).
     2. Wide to long: 14 pairs of x / y columns per team become rows.
     3. 'NaN' (player not on the pitch, or ball out of view) is removed.
     4. Coordinates converted from 0-1 to metres (105 x 68 pitch).
     5. Event frames snapped to the nearest stored sample.
============================================================================= */

USE MatchTracking;
GO

DROP TABLE IF EXISTS silver.match_event;
DROP TABLE IF EXISTS silver.player_position;
DROP TABLE IF EXISTS silver.ball_frame;
DROP TABLE IF EXISTS silver.player_slot;
GO

/* ---- 1. Which player is in which slot ------------------------------------ */
CREATE TABLE silver.player_slot (
    team         VARCHAR(4)   NOT NULL,
    slot_no      INT          NOT NULL,
    player_code  VARCHAR(10)  NOT NULL UNIQUE,
    PRIMARY KEY (team, slot_no)
);

INSERT INTO silver.player_slot
SELECT h.team, v.slot_no, v.player_code
FROM (SELECT 'Home' AS team, * FROM bronze.tracking_home_header WHERE period = 'Period'
      UNION ALL
      SELECT 'Away', * FROM bronze.tracking_away_header WHERE period = 'Period') AS h
CROSS APPLY (VALUES (1, h.slot01_x), (2, h.slot02_x), (3, h.slot03_x), (4, h.slot04_x), (5, h.slot05_x),
                    (6, h.slot06_x), (7, h.slot07_x), (8, h.slot08_x), (9, h.slot09_x), (10, h.slot10_x),
                    (11, h.slot11_x), (12, h.slot12_x), (13, h.slot13_x), (14, h.slot14_x)) AS v (slot_no, player_code);
GO

/* ---- 2. Ball position per sample ----------------------------------------- */
CREATE TABLE silver.ball_frame (
    period     SMALLINT       NOT NULL,
    frame      INT            NOT NULL,
    time_s     DECIMAL(8, 2)  NOT NULL,
    ball_x_m   DECIMAL(7, 2)  NULL,
    ball_y_m   DECIMAL(7, 2)  NULL,
    PRIMARY KEY (frame)
);

DECLARE @len DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'pitch_length_m');
DECLARE @wid DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'pitch_width_m');

INSERT INTO silver.ball_frame
SELECT CAST(period AS SMALLINT), CAST(frame AS INT), CAST(time_s AS DECIMAL(8, 2)),
       CASE WHEN ball_x <> 'NaN' THEN CAST(ball_x AS DECIMAL(9, 5)) * @len END,
       CASE WHEN ball_y <> 'NaN' THEN CAST(ball_y AS DECIMAL(9, 5)) * @wid END
FROM bronze.tracking_home;
GO

/* ---- 3. Player positions, long format, in metres ------------------------- */
CREATE TABLE silver.player_position (
    player_code  VARCHAR(10)    NOT NULL,
    frame        INT            NOT NULL,
    period       SMALLINT       NOT NULL,
    x_m          DECIMAL(7, 2)  NOT NULL,
    y_m          DECIMAL(7, 2)  NOT NULL,
    PRIMARY KEY (player_code, frame)
);

DECLARE @len DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'pitch_length_m');
DECLARE @wid DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'pitch_width_m');

WITH long_form AS (
    SELECT t.team, t.period, t.frame, v.slot_no, v.x_text, v.y_text
    FROM (SELECT 'Home' AS team, * FROM bronze.tracking_home
          UNION ALL
          SELECT 'Away', * FROM bronze.tracking_away) AS t
    CROSS APPLY (VALUES (1, t.slot01_x, t.slot01_y), (2, t.slot02_x, t.slot02_y), (3, t.slot03_x, t.slot03_y),
                        (4, t.slot04_x, t.slot04_y), (5, t.slot05_x, t.slot05_y), (6, t.slot06_x, t.slot06_y),
                        (7, t.slot07_x, t.slot07_y), (8, t.slot08_x, t.slot08_y), (9, t.slot09_x, t.slot09_y),
                        (10, t.slot10_x, t.slot10_y), (11, t.slot11_x, t.slot11_y), (12, t.slot12_x, t.slot12_y),
                        (13, t.slot13_x, t.slot13_y), (14, t.slot14_x, t.slot14_y)) AS v (slot_no, x_text, y_text)
)
INSERT INTO silver.player_position
SELECT s.player_code, CAST(l.frame AS INT), CAST(l.period AS SMALLINT),
       CAST(l.x_text AS DECIMAL(9, 5)) * @len,
       CAST(l.y_text AS DECIMAL(9, 5)) * @wid
FROM long_form AS l
INNER JOIN silver.player_slot AS s ON s.team = l.team AND s.slot_no = l.slot_no
WHERE l.x_text <> 'NaN' AND l.y_text <> 'NaN';
GO

/* ---- 4. Events ----------------------------------------------------------- */
CREATE TABLE silver.match_event (
    event_id      INT            NOT NULL PRIMARY KEY,
    team          VARCHAR(4)     NOT NULL,
    event_type    VARCHAR(20)    NOT NULL,
    subtype       VARCHAR(60)    NULL,
    period        SMALLINT       NOT NULL,
    start_frame   INT            NOT NULL,
    sample_frame  INT            NOT NULL,     -- nearest stored sample
    end_frame     INT            NULL,
    from_player   VARCHAR(10)    NULL,
    to_player     VARCHAR(10)    NULL,
    start_x_m     DECIMAL(7, 2)  NULL,
    start_y_m     DECIMAL(7, 2)  NULL,
    end_x_m       DECIMAL(7, 2)  NULL,
    end_y_m       DECIMAL(7, 2)  NULL
);

DECLARE @len  DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'pitch_length_m');
DECLARE @wid  DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'pitch_width_m');
DECLARE @step DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'frame_step');

INSERT INTO silver.match_event
SELECT ROW_NUMBER() OVER (ORDER BY CAST(start_frame AS INT), CAST(start_time_s AS DECIMAL(8, 2)), type, team),
       team, type, NULLIF(subtype, ''), CAST(period AS SMALLINT),
       CAST(start_frame AS INT),
       CASE WHEN ROUND(CAST(start_frame AS INT) / @step, 0) * @step < @step THEN @step
            ELSE ROUND(CAST(start_frame AS INT) / @step, 0) * @step END,
       NULLIF(CAST(end_frame AS INT), 0),
       NULLIF(from_player, ''), NULLIF(to_player, ''),
       CASE WHEN start_x <> 'NaN' THEN CAST(start_x AS DECIMAL(9, 5)) * @len END,
       CASE WHEN start_y <> 'NaN' THEN CAST(start_y AS DECIMAL(9, 5)) * @wid END,
       CASE WHEN end_x   <> 'NaN' THEN CAST(end_x   AS DECIMAL(9, 5)) * @len END,
       CASE WHEN end_y   <> 'NaN' THEN CAST(end_y   AS DECIMAL(9, 5)) * @wid END
FROM bronze.match_events;
GO

INSERT INTO ops.cleaning_log (step_no, table_name, step_name, rows_affected)
SELECT 1, 'player_slot', 'Player slots read from header row 3', COUNT(*) FROM silver.player_slot
UNION ALL
SELECT 2, 'player_position', 'Wide x/y pairs unpivoted to rows (before removing NaN)',
       28 * ((SELECT COUNT(*) FROM bronze.tracking_home) + (SELECT COUNT(*) FROM bronze.tracking_away)) / 2
UNION ALL
SELECT 3, 'player_position', 'NaN positions removed (player not on the pitch)',
       28 * ((SELECT COUNT(*) FROM bronze.tracking_home) + (SELECT COUNT(*) FROM bronze.tracking_away)) / 2
       - (SELECT COUNT(*) FROM silver.player_position)
UNION ALL
SELECT 3, 'ball_frame', 'Samples with no ball position (NaN)', COUNT(*) FROM silver.ball_frame WHERE ball_x_m IS NULL
UNION ALL
SELECT 4, 'player_position', 'Coordinates converted from 0-1 to metres', COUNT(*) FROM silver.player_position
UNION ALL
SELECT 5, 'match_event', 'Event frames snapped to the nearest stored sample',
       COUNT(*) FROM silver.match_event WHERE sample_frame <> start_frame;

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'silver', 'player_position', COUNT(*) FROM silver.player_position UNION ALL
SELECT 'silver', 'match_event',     COUNT(*) FROM silver.match_event;
GO
