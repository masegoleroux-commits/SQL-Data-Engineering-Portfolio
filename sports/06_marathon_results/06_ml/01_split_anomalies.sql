/* =============================================================================
   01_split_anomalies.sql
   Pacing anomaly detection: which runners ran a stage of the race in a way
   almost nobody else did? Race organisers run checks like this to find
   timing errors, course cutting and runners in distress.

   A first attempt compared each segment with the runner's own average and
   flagged anything over 3 standard deviations away. It found nothing, and
   it never could: with only 10 segments per runner, no single value can
   sit more than about 2.85 standard deviations from that runner's mean.
   The baseline has to be bigger than one runner.

   So each segment is turned into a RELATIVE pace:

       relative pace = segment sec/km / runner's whole-race sec/km

   1.00 means the stage was run at the runner's average pace. Then, for each
   stage, the relative paces of all 26,630 runners give a field average and
   spread. A segment is flagged when its relative pace is more than
   anomaly_z standard deviations from the field for that stage:

       slower than the field  -> slowing sharply, walking, or a stop
       faster than the field  -> only possible if the rest of the race was
                                 much slower (a fade), or a timing error

   A separate guard flags any segment faster than
   fastest_plausible_km_seconds, which would point to a missed mat.

   Only segments between consecutive mats are scored, so every stage is
   compared like for like.
============================================================================= */

USE MarathonResults;
GO

DROP TABLE IF EXISTS ml.runner_pacing_profile;
DROP TABLE IF EXISTS ml.split_anomaly;
GO

CREATE TABLE ml.split_anomaly (
    bib              VARCHAR(10)    NOT NULL,
    to_checkpoint    INT            NOT NULL,
    sec_per_km       DECIMAL(7, 2)  NOT NULL,
    relative_pace    DECIMAL(6, 3)  NOT NULL,
    z_score          DECIMAL(6, 2)  NOT NULL,
    reason           VARCHAR(40)    NOT NULL,
    PRIMARY KEY (bib, to_checkpoint)
);

DECLARE @fastest DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'fastest_plausible_km_seconds');
DECLARE @z       DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'anomaly_z');

WITH relative AS (
    SELECT s.bib, s.to_checkpoint, s.sec_per_km,
           s.sec_per_km / (r.finish_seconds / 42.195) AS relative_pace
    FROM gold.fact_segment AS s
    INNER JOIN gold.fact_result AS r ON r.bib = s.bib
    WHERE s.from_checkpoint = s.to_checkpoint - 1
       OR (s.from_checkpoint IS NULL AND s.to_checkpoint = 1)
),
scored AS (
    SELECT rp.*,
           (relative_pace - AVG(relative_pace) OVER (PARTITION BY to_checkpoint))
             / STDEV(relative_pace) OVER (PARTITION BY to_checkpoint) AS z_score
    FROM relative AS rp
)
INSERT INTO ml.split_anomaly
SELECT bib, to_checkpoint, sec_per_km, relative_pace, z_score,
       CASE WHEN sec_per_km < @fastest THEN 'implausibly fast'
            WHEN z_score > 0 THEN 'far slower than the field'
            ELSE 'far faster than the field' END
FROM scored
WHERE sec_per_km < @fastest OR ABS(z_score) > @z;
GO

/* ---- One profile per flagged runner ------------------------------------- */
CREATE TABLE ml.runner_pacing_profile (
    bib            VARCHAR(10)   NOT NULL PRIMARY KEY,
    slow_flags     INT           NOT NULL,
    fast_flags     INT           NOT NULL,
    first_flag_at  INT           NOT NULL,
    profile        VARCHAR(60)   NOT NULL
);

INSERT INTO ml.runner_pacing_profile
SELECT bib,
       SUM(CASE WHEN reason = 'far slower than the field' THEN 1 ELSE 0 END),
       SUM(CASE WHEN reason <> 'far slower than the field' THEN 1 ELSE 0 END),
       MIN(to_checkpoint),
       CASE WHEN SUM(CASE WHEN reason = 'implausibly fast' THEN 1 ELSE 0 END) > 0
                 THEN 'check timing: implausible segment'
            WHEN SUM(CASE WHEN reason = 'far slower than the field' THEN 1 ELSE 0 END) = 0
                 THEN 'fast start, heavy fade'
            WHEN SUM(CASE WHEN reason = 'far faster than the field' THEN 1 ELSE 0 END) = 0
                 THEN 'sudden slowdown or stop'
            ELSE 'fast start, then slowdown or stop' END
FROM ml.split_anomaly
GROUP BY bib;
GO

SELECT profile, COUNT(*) AS runners
FROM ml.runner_pacing_profile
GROUP BY profile
ORDER BY runners DESC;

-- where in the race slowdowns start
SELECT c.checkpoint AS first_flagged_at, COUNT(*) AS runners
FROM ml.runner_pacing_profile AS p
INNER JOIN gold.dim_checkpoint AS c ON c.checkpoint_no = p.first_flag_at
WHERE p.slow_flags > 0
GROUP BY c.checkpoint_no, c.checkpoint
ORDER BY c.checkpoint_no;
GO
