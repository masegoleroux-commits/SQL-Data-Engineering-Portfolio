/* =============================================================================
   01_quality_checks.sql
============================================================================= */

USE OlympicMedals;
GO

DROP TABLE IF EXISTS ops.test_result;
CREATE TABLE ops.test_result (
    test_name  VARCHAR(120)  NOT NULL,
    expected   BIGINT        NULL,
    actual     BIGINT        NULL
);

INSERT INTO ops.test_result
SELECT 'bronze -> silver: every row', (SELECT COUNT(*) FROM bronze.athlete_events_1992_2016), (SELECT COUNT(*) FROM silver.entry);

INSERT INTO ops.test_result
SELECT 'every NOC in the results has a region', 0, COUNT(DISTINCT noc)
FROM silver.entry WHERE noc NOT IN (SELECT noc FROM silver.noc);

INSERT INTO ops.test_result
SELECT 'silver -> gold: every entry', (SELECT COUNT(*) FROM silver.entry), (SELECT COUNT(*) FROM gold.fact_entry);

INSERT INTO ops.test_result
SELECT 'medal athletes add back up to the medal rows',
       (SELECT COUNT(*) FROM gold.fact_entry WHERE medal IS NOT NULL),
       (SELECT SUM(athletes) FROM gold.fact_medal);

-- the medal table must match what was published, country by country
INSERT INTO ops.test_result
SELECT 'medal table matches published totals for reference countries', 0, COUNT(*)
FROM ops.reference_medal_count AS r
LEFT JOIN gold.v_medal_table AS v ON v.games = r.games AND v.noc = r.noc
WHERE COALESCE(v.gold, -1) <> r.gold OR COALESCE(v.silver, -1) <> r.silver OR COALESCE(v.bronze, -1) <> r.bronze;

INSERT INTO ops.test_result
SELECT 'no event awards more than one gold to the same country', 0, COUNT(*)
FROM (SELECT event_key, noc FROM gold.fact_medal WHERE medal = 'Gold' GROUP BY event_key, noc HAVING COUNT(*) > 1) AS x;

INSERT INTO ops.test_result
SELECT 'an athlete is never in one event twice at one Games', 0, COUNT(*)
FROM (SELECT athlete_id, event_key FROM gold.fact_entry GROUP BY athlete_id, event_key HAVING COUNT(*) > 1) AS x;

SELECT test_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM ops.test_result;

IF EXISTS (SELECT 1 FROM ops.test_result WHERE actual IS NULL OR expected <> actual)
    THROW 50001, 'Quality checks failed. See the results grid.', 1;
GO
