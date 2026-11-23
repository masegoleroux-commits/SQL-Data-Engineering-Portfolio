/* =============================================================================
   01_analysis.sql
============================================================================= */

USE MarathonResults;
GO

/* ---- 1. Finish times by age group and gender ----------------------------- */
-- the median is the middle runner, found with ROW_NUMBER and COUNT
WITH ordered AS (
    SELECT d.age_group, d.gender, r.finish_seconds,
           ROW_NUMBER() OVER (PARTITION BY d.age_group, d.gender ORDER BY r.finish_seconds) AS rn,
           COUNT(*)     OVER (PARTITION BY d.age_group, d.gender) AS n
    FROM gold.fact_result AS r
    INNER JOIN gold.dim_runner AS d ON d.bib = r.bib
)
SELECT age_group, gender, MAX(n) AS finishers,
       CONCAT(MIN(finish_seconds) / 3600, ':', RIGHT(CONCAT('0', (MIN(finish_seconds) % 3600) / 60), 2), ':',
              RIGHT(CONCAT('0', MIN(finish_seconds) % 60), 2)) AS fastest,
       CONCAT(AVG(CASE WHEN rn = (n + 1) / 2 THEN finish_seconds END) / 3600, ':',
              RIGHT(CONCAT('0', (AVG(CASE WHEN rn = (n + 1) / 2 THEN finish_seconds END) % 3600) / 60), 2)) AS median_h_mm
FROM ordered
GROUP BY age_group, gender
ORDER BY age_group, gender;
GO

/* ---- 2. Pacing: negative splits and hitting the wall --------------------- */
DECLARE @wall DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'wall_slowdown_pct');

WITH pace AS (
    SELECT s.bib,
           SUM(CASE WHEN s.to_checkpoint <= 7 THEN s.segment_seconds END) / 30.0     AS early_sec_per_km,
           SUM(CASE WHEN s.to_checkpoint >  7 THEN s.segment_seconds END) / 12.195   AS late_sec_per_km
    FROM gold.fact_segment AS s
    WHERE NOT EXISTS (SELECT 1 FROM gold.fact_segment AS g
                      WHERE g.bib = s.bib AND g.from_checkpoint < 7 AND g.to_checkpoint > 7)
    GROUP BY s.bib
)
SELECT d.gender,
       COUNT(*)                                                                    AS runners,
       CAST(100.0 * SUM(CASE WHEN r.is_negative_split = 1 THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5, 1)) AS negative_split_pct,
       CAST(100.0 * SUM(CASE WHEN p.late_sec_per_km > p.early_sec_per_km * (1 + @wall / 100) THEN 1 ELSE 0 END)
            / COUNT(*) AS DECIMAL(5, 1))                                           AS hit_the_wall_pct,
       CAST(AVG(100.0 * (p.late_sec_per_km - p.early_sec_per_km) / p.early_sec_per_km) AS DECIMAL(5, 1)) AS avg_slowdown_pct
FROM pace AS p
INNER JOIN gold.fact_result AS r ON r.bib = p.bib
INNER JOIN gold.dim_runner  AS d ON d.bib = p.bib
GROUP BY d.gender;
GO

/* ---- 3. Where the field comes from --------------------------------------- */
DECLARE @min_runners DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'min_country_runners');

SELECT d.country, COUNT(*) AS finishers,
       CAST(AVG(r.finish_seconds) / 60.0 AS DECIMAL(6, 1)) AS avg_finish_minutes
FROM gold.fact_result AS r
INNER JOIN gold.dim_runner AS d ON d.bib = r.bib
GROUP BY d.country
HAVING COUNT(*) >= @min_runners
ORDER BY finishers DESC;
GO

/* ---- 4. Average pace through the race, by finishing group ---------------- */
SELECT c.checkpoint,
       CAST(AVG(CASE WHEN r.finish_seconds <  3 * 3600 THEN s.sec_per_km END) AS DECIMAL(6, 1)) AS sub_3h,
       CAST(AVG(CASE WHEN r.finish_seconds >= 3 * 3600 AND r.finish_seconds < 4 * 3600 THEN s.sec_per_km END) AS DECIMAL(6, 1)) AS h3_to_4,
       CAST(AVG(CASE WHEN r.finish_seconds >= 4 * 3600 THEN s.sec_per_km END) AS DECIMAL(6, 1)) AS over_4h
FROM gold.fact_segment AS s
INNER JOIN gold.fact_result    AS r ON r.bib = s.bib
INNER JOIN gold.dim_checkpoint AS c ON c.checkpoint_no = s.to_checkpoint
WHERE s.from_checkpoint = s.to_checkpoint - 1 OR (s.from_checkpoint IS NULL AND s.to_checkpoint = 1)
GROUP BY c.checkpoint_no, c.checkpoint
ORDER BY c.checkpoint_no;
GO
