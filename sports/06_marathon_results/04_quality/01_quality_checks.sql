/* =============================================================================
   01_quality_checks.sql
============================================================================= */

USE MarathonResults;
GO

DROP TABLE IF EXISTS ops.test_result;
CREATE TABLE ops.test_result (
    test_name  VARCHAR(120)  NOT NULL,
    expected   BIGINT        NULL,
    actual     BIGINT        NULL
);

INSERT INTO ops.test_result
SELECT 'bronze -> silver: every finisher', (SELECT COUNT(*) FROM bronze.boston_marathon_2016), (SELECT COUNT(*) FROM silver.runner);

INSERT INTO ops.test_result
SELECT 'silver: 10 split rows per finisher', (SELECT 10 * COUNT(*) FROM silver.runner), (SELECT COUNT(*) FROM silver.split);

INSERT INTO ops.test_result
SELECT 'every runner falls into one age group', (SELECT COUNT(*) FROM silver.runner), (SELECT COUNT(*) FROM gold.dim_runner);

INSERT INTO ops.test_result
SELECT 'every finisher has a finish time', 0, COUNT(*) FROM silver.split WHERE checkpoint_no = 10 AND elapsed_seconds IS NULL;

INSERT INTO ops.test_result
SELECT 'times always increase from mat to mat', 0, COUNT(*) FROM gold.fact_segment WHERE segment_seconds <= 0;

-- the segments of each runner must add back up to the finish time
INSERT INTO ops.test_result
SELECT 'segments add up to the finish time', 0, COUNT(*)
FROM gold.fact_result AS r
WHERE r.finish_seconds <> (SELECT SUM(s.segment_seconds) FROM gold.fact_segment AS s WHERE s.bib = r.bib);

INSERT INTO ops.test_result
SELECT 'segment distances add up to 42.195 km', 0, COUNT(*)
FROM (SELECT bib FROM gold.fact_segment GROUP BY bib HAVING ABS(SUM(segment_km) - 42.195) > 0.001) AS x;

-- Places are decided on times to the tenth of a second, but the file gives
-- whole seconds, so runners who finished in the same second share a time
-- and have different places. The check is therefore on ORDER: walking
-- down the places, the finish time must never go down.
INSERT INTO ops.test_result
SELECT 'published overall places are in finish-time order', 0, COUNT(*)
FROM (SELECT finish_seconds, LAG(finish_seconds) OVER (ORDER BY overall_place, bib) AS prev_seconds
      FROM gold.fact_result) AS x
WHERE x.finish_seconds < x.prev_seconds;

INSERT INTO ops.test_result
SELECT 'published gender places are in finish-time order', 0, COUNT(*)
FROM (SELECT r.finish_seconds,
             LAG(r.finish_seconds) OVER (PARTITION BY d.gender ORDER BY r.gender_place, r.bib) AS prev_seconds
      FROM gold.fact_result AS r INNER JOIN gold.dim_runner AS d ON d.bib = r.bib) AS x
WHERE x.finish_seconds < x.prev_seconds;

SELECT test_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM ops.test_result;

IF EXISTS (SELECT 1 FROM ops.test_result WHERE actual IS NULL OR expected <> actual)
    THROW 50001, 'Quality checks failed. See the results grid.', 1;
GO
