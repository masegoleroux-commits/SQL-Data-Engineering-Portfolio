/* =============================================================================
   01_build_silver.sql
   silver.runner   GRAIN: one finisher (bib number)
   silver.split    GRAIN: one finisher at one timing checkpoint

   Times arrive as text in H:MM:SS. They are converted to whole seconds,
   which can be added, subtracted and averaged. The conversion is done once,
   on the long-format split table, so the parsing expression is written
   once rather than ten times:

       hours   = text before the first colon
       minutes = the two characters after it
       seconds = the last two characters

   Cleaning steps, each counted in ops.cleaning_log:
     1. '-' (no time recorded at a mat) becomes NULL.
     2. Times converted from H:MM:SS text to seconds.
     3. Bib numbers kept as text: elite women's bibs start with F (F1, F2).
     4. Names are NOT a key: several different runners share a name.
     5. The source has a column with a blank header; it is loaded but not
        used (it is empty for 99.7% of rows).
     6. Shared places (two runners given the same overall place) are
        counted and kept as published.
============================================================================= */

USE MarathonResults;
GO

DROP TABLE IF EXISTS silver.split;
DROP TABLE IF EXISTS silver.runner;
GO

CREATE TABLE silver.runner (
    bib             VARCHAR(10)    NOT NULL PRIMARY KEY,
    runner_name     NVARCHAR(100)  NOT NULL,
    age             SMALLINT       NOT NULL,
    gender          CHAR(1)        NOT NULL,
    city            NVARCHAR(60)   NULL,
    state           VARCHAR(10)    NULL,
    country         CHAR(3)        NOT NULL,
    citizenship     CHAR(3)        NULL,
    overall_place   INT            NOT NULL,
    gender_place    INT            NOT NULL,
    division_place  INT            NOT NULL,
    is_elite_bib    SMALLINT       NOT NULL
);

INSERT INTO silver.runner
SELECT bib, name, CAST(age AS SMALLINT), m_f, city, NULLIF(state, ''), country, NULLIF(citizen, ''),
       CAST(overall AS INT), CAST(gender AS INT), CAST(division AS INT),
       CASE WHEN bib LIKE 'F%' THEN 1 ELSE 0 END
FROM bronze.boston_marathon_2016;
GO

CREATE TABLE silver.split (
    bib              VARCHAR(10)  NOT NULL,
    checkpoint_no    INT          NOT NULL,
    elapsed_text     VARCHAR(10)  NULL,
    elapsed_seconds  INT          NULL,
    PRIMARY KEY (bib, checkpoint_no)
);

WITH long_form AS (
    SELECT b.bib, v.checkpoint_no, NULLIF(v.elapsed_text, '-') AS elapsed_text
    FROM bronze.boston_marathon_2016 AS b
    CROSS APPLY (VALUES (1, b.c_5k), (2, b.c_10k), (3, b.c_15k), (4, b.c_20k), (5, b.half),
                        (6, b.c_25k), (7, b.c_30k), (8, b.c_35k), (9, b.c_40k),
                        (10, b.official_time)) AS v (checkpoint_no, elapsed_text)
)
INSERT INTO silver.split
SELECT bib, checkpoint_no, elapsed_text,
       CAST(LEFT(elapsed_text, CHARINDEX(':', elapsed_text) - 1) AS INT) * 3600
     + CAST(SUBSTRING(elapsed_text, CHARINDEX(':', elapsed_text) + 1, 2) AS INT) * 60
     + CAST(RIGHT(elapsed_text, 2) AS INT)
FROM long_form;
GO

INSERT INTO ops.cleaning_log (step_no, table_name, step_name, rows_affected)
SELECT 1, 'split', 'Missing split (''-'') set to NULL',
       (SELECT COUNT(*) FROM silver.split WHERE elapsed_text IS NULL)
UNION ALL
SELECT 2, 'split', 'Times converted from H:MM:SS text to seconds',
       (SELECT COUNT(*) FROM silver.split WHERE elapsed_seconds IS NOT NULL)
UNION ALL
SELECT 3, 'runner', 'Elite bibs with a letter prefix kept as text', SUM(is_elite_bib) FROM silver.runner
UNION ALL
SELECT 4, 'runner', 'Runners who share a name with another runner (bib is the key)',
       (SELECT COUNT(*) FROM silver.runner AS r
        WHERE EXISTS (SELECT 1 FROM silver.runner AS o WHERE o.runner_name = r.runner_name AND o.bib <> r.bib))
UNION ALL
SELECT 5, 'boston_marathon_2016', 'Values in the column with a blank header (not used)',
       (SELECT COUNT(*) FROM bronze.boston_marathon_2016 WHERE unnamed_column IS NOT NULL AND unnamed_column <> '')
UNION ALL
SELECT 6, 'runner', 'Runners sharing an overall place (a dead heat, kept as published)',
       (SELECT COUNT(*) FROM silver.runner AS r
        WHERE EXISTS (SELECT 1 FROM silver.runner AS o WHERE o.overall_place = r.overall_place AND o.bib <> r.bib));

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'silver', 'runner', COUNT(*) FROM silver.runner UNION ALL
SELECT 'silver', 'split',  COUNT(*) FROM silver.split;
GO
