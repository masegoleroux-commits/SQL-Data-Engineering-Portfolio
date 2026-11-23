/* =============================================================================
   04_scd_tests.sql
   Two kinds of check:
   * Structural rules that must hold for ANY data: one current row per
     customer, no gaps or overlaps between versions, contiguous versions.
   * Behaviour for the four batches in data/03: expected numbers are worked
     out from the change rules (id % 17 etc.), not copied from the output.
============================================================================= */

USE CustomerHistory;
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS #results;
CREATE TABLE #results (test_id INT IDENTITY(1, 1), test_name VARCHAR(100), expected INT, actual INT);

-- numbers 1..300 for working out expected counts
DROP TABLE IF EXISTS #n;
SELECT TOP (300) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n INTO #n FROM sys.all_objects;

/* ---- Structural --------------------------------------------------------- */
INSERT INTO #results SELECT 'Exactly one current row per customer',
    (SELECT COUNT(DISTINCT customer_id) FROM dbo.dim_customer),
    (SELECT COUNT(*) FROM dbo.dim_customer WHERE is_current = 1);

-- LEAD() reads the next version of the same customer. It must start the
-- day after this one ends: no gap, no overlap.
INSERT INTO #results SELECT 'No gaps or overlaps between versions', 0, COUNT(*)
FROM (
    SELECT valid_to,
           LEAD(valid_from) OVER (PARTITION BY customer_id ORDER BY valid_from) AS next_from
    FROM dbo.dim_customer
) AS v
WHERE v.next_from IS NOT NULL AND v.next_from <> DATEADD(DAY, 1, v.valid_to);

INSERT INTO #results SELECT 'Version numbers run 1..n with no holes', 0, COUNT(*)
FROM (SELECT customer_id FROM dbo.dim_customer GROUP BY customer_id
      HAVING MAX(version_number) <> COUNT(*) OR MIN(version_number) <> 1) AS bad;

INSERT INTO #results SELECT 'Type 1 columns identical on every version', 0, COUNT(*)
FROM (SELECT customer_id FROM dbo.dim_customer GROUP BY customer_id
      HAVING COUNT(DISTINCT COALESCE(email, N'~')) > 1 OR COUNT(DISTINCT full_name) > 1) AS bad;

INSERT INTO #results SELECT 'Current rows match the latest snapshot', 0, COUNT(*)
FROM dbo.src_customer_snapshot AS s
INNER JOIN dbo.dim_customer AS d ON d.customer_id = s.customer_id AND d.is_current = 1
WHERE s.batch_date = (SELECT MAX(batch_date) FROM dbo.load_audit)
  AND (dbo.fn_proper_case(LTRIM(RTRIM(s.city))) <> d.city OR UPPER(s.loyalty_tier) <> d.loyalty_tier);

/* ---- Behaviour ---------------------------------------------------------- */
INSERT INTO #results SELECT 'Batch 1: 300 new customers', 300,
    (SELECT new_customers FROM dbo.load_audit WHERE batch_date = '2024-01-01');

INSERT INTO #results SELECT 'Batch 2: new versions = moved city or changed tier',
    (SELECT COUNT(*) FROM #n WHERE (n % 17 = 0 OR n % 11 = 0) AND n % 50 <> 0),
    (SELECT new_versions FROM dbo.load_audit WHERE batch_date = '2024-02-01');

INSERT INTO #results SELECT 'Batch 2: email corrections are Type 1 only',
    (SELECT COUNT(*) FROM #n WHERE n % 13 = 0 AND n % 50 <> 0),
    (SELECT type1_updates FROM dbo.load_audit WHERE batch_date = '2024-02-01');

INSERT INTO #results SELECT 'Batch 2: customers missing from extract closed as deleted',
    (SELECT COUNT(*) FROM #n WHERE n % 50 = 0),
    (SELECT deletions FROM dbo.load_audit WHERE batch_date = '2024-02-01');

-- Tier upgrades again for id % 11 (PLATINUM cannot go higher), plus customer
-- 50 returning. The ' cape town ' formatting must add nothing.
INSERT INTO #results SELECT 'Batch 3: formatting noise creates no versions',
    (SELECT COUNT(*) FROM dbo.src_customer_snapshot
     WHERE batch_date = '2024-02-01' AND customer_id % 11 = 0 AND loyalty_tier <> N'PLATINUM') + 1,
    (SELECT new_versions FROM dbo.load_audit WHERE batch_date = '2024-03-01');

INSERT INTO #results SELECT 'Batch 4: identical snapshot, zero changes', 0,
    (SELECT new_customers + new_versions + type1_updates + deletions
     FROM dbo.load_audit WHERE batch_date = '2024-04-01');

INSERT INTO #results SELECT 'Customer 50 deleted then re-activated (3 versions)', 3,
    (SELECT COUNT(*) FROM dbo.dim_customer WHERE customer_id = 50);

INSERT INTO #results SELECT 'Currently deleted customers (6 dropped, 1 returned)', 5,
    (SELECT COUNT(*) FROM dbo.dim_customer WHERE is_current = 1 AND is_deleted = 1);

/* ---- Guard rails -------------------------------------------------------- */
-- Loading an old batch again must be refused.
DECLARE @rejected INT = 0;
BEGIN TRY
    EXEC dbo.usp_load_dim_customer @batch_date = '2024-02-01';
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() = 50010 SET @rejected = 1;
END CATCH;
INSERT INTO #results SELECT 'Out-of-order batch is rejected', 1, @rejected;

/* ---- Orders ------------------------------------------------------------- */
INSERT INTO #results SELECT 'Every order linked to a customer version', 0,
    (SELECT COUNT(*) FROM dbo.fact_orders WHERE customer_sk IS NULL);

INSERT INTO #results SELECT 'Linked version was valid on the order date', 0, COUNT(*)
FROM dbo.fact_orders AS f
INNER JOIN dbo.dim_customer AS d ON d.customer_sk = f.customer_sk
WHERE f.order_date NOT BETWEEN d.valid_from AND d.valid_to
   OR d.customer_id <> f.customer_id;

/* ---- Results ------------------------------------------------------------ */
SELECT test_id, test_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM #results
ORDER BY test_id;

IF EXISTS (SELECT 1 FROM #results WHERE expected <> actual OR actual IS NULL)
    THROW 50003, 'SCD tests failed. See the results grid.', 1;
GO
