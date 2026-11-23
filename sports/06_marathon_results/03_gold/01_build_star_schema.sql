/* =============================================================================
   01_build_star_schema.sql
   dim_runner      one finisher, with age group from ops.age_group
   dim_checkpoint  one timing mat (copied from ops.checkpoint)
   fact_result     GRAIN: one finisher
   fact_segment    GRAIN: one finisher between two consecutive recorded
                   mats. If a mat is missing, the segment runs from the
                   last mat that did record a time, so no time is lost.
============================================================================= */

USE MarathonResults;
GO

DROP TABLE IF EXISTS gold.fact_segment;
DROP TABLE IF EXISTS gold.fact_result;
DROP TABLE IF EXISTS gold.dim_checkpoint;
DROP TABLE IF EXISTS gold.dim_runner;
GO

CREATE TABLE gold.dim_runner (
    bib           VARCHAR(10)    NOT NULL PRIMARY KEY,
    runner_name   NVARCHAR(100)  NOT NULL,
    gender        CHAR(1)        NOT NULL,
    age           SMALLINT       NOT NULL,
    age_group     VARCHAR(10)    NOT NULL,
    country       CHAR(3)        NOT NULL,
    state         VARCHAR(10)    NULL
);

INSERT INTO gold.dim_runner
SELECT r.bib, r.runner_name, r.gender, r.age, g.age_group, r.country, r.state
FROM silver.runner AS r
INNER JOIN ops.age_group AS g ON r.age BETWEEN g.min_age AND g.max_age;

CREATE TABLE gold.dim_checkpoint (
    checkpoint_no  INT            NOT NULL PRIMARY KEY,
    checkpoint     VARCHAR(10)    NOT NULL,
    km             DECIMAL(7, 4)  NOT NULL
);

INSERT INTO gold.dim_checkpoint SELECT checkpoint_no, checkpoint, km FROM ops.checkpoint;

CREATE TABLE gold.fact_result (
    bib               VARCHAR(10)  NOT NULL PRIMARY KEY REFERENCES gold.dim_runner (bib),
    finish_seconds    INT          NOT NULL,
    half_seconds      INT          NULL,
    first_half_secs   INT          NULL,
    second_half_secs  INT          NULL,
    is_negative_split SMALLINT     NULL,      -- second half faster than the first
    overall_place     INT          NOT NULL,
    gender_place      INT          NOT NULL,
    division_place    INT          NOT NULL,
    missing_splits    SMALLINT     NOT NULL
);

INSERT INTO gold.fact_result
SELECT r.bib, f.elapsed_seconds, h.elapsed_seconds,
       h.elapsed_seconds, f.elapsed_seconds - h.elapsed_seconds,
       CASE WHEN h.elapsed_seconds IS NULL THEN NULL
            WHEN f.elapsed_seconds - h.elapsed_seconds < h.elapsed_seconds THEN 1 ELSE 0 END,
       r.overall_place, r.gender_place, r.division_place,
       (SELECT COUNT(*) FROM silver.split AS s WHERE s.bib = r.bib AND s.elapsed_seconds IS NULL)
FROM silver.runner AS r
INNER JOIN silver.split AS f ON f.bib = r.bib AND f.checkpoint_no = 10
LEFT JOIN  silver.split AS h ON h.bib = r.bib AND h.checkpoint_no = 5 AND h.elapsed_seconds IS NOT NULL;
GO

CREATE TABLE gold.fact_segment (
    bib               VARCHAR(10)    NOT NULL REFERENCES gold.dim_runner (bib),
    to_checkpoint     INT            NOT NULL REFERENCES gold.dim_checkpoint (checkpoint_no),
    from_checkpoint   INT            NULL,        -- NULL = the start line
    segment_km        DECIMAL(7, 4)  NOT NULL,
    segment_seconds   INT            NOT NULL,
    sec_per_km        DECIMAL(7, 2)  NOT NULL,
    PRIMARY KEY (bib, to_checkpoint)
);

-- consecutive RECORDED mats: LAG over the non-null times only
WITH recorded AS (
    SELECT s.bib, s.checkpoint_no, s.elapsed_seconds, c.km,
           LAG(s.checkpoint_no)   OVER (PARTITION BY s.bib ORDER BY s.checkpoint_no) AS prev_cp,
           LAG(s.elapsed_seconds) OVER (PARTITION BY s.bib ORDER BY s.checkpoint_no) AS prev_secs,
           LAG(c.km)              OVER (PARTITION BY s.bib ORDER BY s.checkpoint_no) AS prev_km
    FROM silver.split AS s
    INNER JOIN ops.checkpoint AS c ON c.checkpoint_no = s.checkpoint_no
    WHERE s.elapsed_seconds IS NOT NULL
)
INSERT INTO gold.fact_segment
SELECT bib, checkpoint_no, prev_cp,
       km - COALESCE(prev_km, 0),
       elapsed_seconds - COALESCE(prev_secs, 0),
       (elapsed_seconds - COALESCE(prev_secs, 0)) / (km - COALESCE(prev_km, 0))
FROM recorded;
GO

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'gold', 'dim_runner',   COUNT(*) FROM gold.dim_runner UNION ALL
SELECT 'gold', 'fact_result',  COUNT(*) FROM gold.fact_result UNION ALL
SELECT 'gold', 'fact_segment', COUNT(*) FROM gold.fact_segment;
GO
