/* =============================================================================
   09_test_analytics.sql
   Analytical SQL fails quietly: a wrong window frame or a join that
   duplicates rows still returns numbers. These checks test things that
   must be true if the logic is right.
============================================================================= */

USE CustomerAnalytics;
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS #results;
CREATE TABLE #results (test_id INT IDENTITY(1, 1), test_name VARCHAR(120), expected DECIMAL(18, 2), actual DECIMAL(18, 2));

/* ---- Revenue ties out everywhere ---------------------------------------- */
INSERT INTO #results SELECT 'Order view revenue = raw order lines',
    (SELECT SUM(quantity * unit_price) FROM shop.order_item),
    (SELECT SUM(order_value) FROM analytics.v_order_value);

INSERT INTO #results SELECT 'Executive summary grand total = total revenue',
    (SELECT SUM(order_value) FROM analytics.v_order_value),
    (SELECT revenue FROM analytics.v_exec_summary WHERE order_year = 'All years' AND province = N'All provinces');

INSERT INTO #results SELECT 'Province rows add up to each year total', 0, COUNT(*)
FROM (
    SELECT d.order_year
    FROM analytics.v_exec_summary AS d
    INNER JOIN analytics.v_exec_summary AS t ON t.order_year = d.order_year AND t.province = N'All provinces'
    WHERE d.province <> N'All provinces'
    GROUP BY d.order_year, t.revenue
    HAVING SUM(d.revenue) <> t.revenue
) AS bad;

INSERT INTO #results SELECT 'December year-to-date = full-year revenue', 0, COUNT(*)
FROM analytics.v_monthly_revenue AS m
WHERE MONTH(m.order_month) = 12
  AND m.revenue_ytd <> (SELECT SUM(y.revenue) FROM analytics.v_monthly_revenue AS y
                        WHERE YEAR(y.order_month) = YEAR(m.order_month));

/* ---- RFM ---------------------------------------------------------------- */
INSERT INTO #results SELECT 'RFM: every buyer appears exactly once',
    (SELECT COUNT(DISTINCT customer_id) FROM shop.orders),
    (SELECT COUNT(*) FROM analytics.v_customer_rfm);

INSERT INTO #results SELECT 'RFM: NTILE groups differ in size by at most 1', 1,
    (SELECT CASE WHEN MAX(n) - MIN(n) <= 1 THEN 1 ELSE 0 END
     FROM (SELECT COUNT(*) AS n FROM analytics.v_customer_rfm GROUP BY r_score) AS g);

/* ---- Cohorts ------------------------------------------------------------ */
INSERT INTO #results SELECT 'Cohort sizes add up to all buyers',
    (SELECT COUNT(DISTINCT customer_id) FROM shop.orders),
    (SELECT SUM(cohort_size) FROM analytics.v_cohort_retention);

INSERT INTO #results SELECT 'No activity before the cohort month', 0,
    (SELECT COUNT(*) FROM analytics.v_cohort_activity WHERE months_since < 0);

INSERT INTO #results SELECT 'Retention never above 100%', 0,
    (SELECT COUNT(*) FROM analytics.v_cohort_retention
     WHERE m1 > 100 OR m2 > 100 OR m3 > 100 OR m6 > 100 OR m12 > 100);

/* ---- Pareto ------------------------------------------------------------- */
INSERT INTO #results SELECT 'Pareto curve ends at exactly 100%', 100,
    (SELECT TOP (1) cumulative_pct_revenue FROM analytics.v_customer_pareto ORDER BY spend_rank DESC);

INSERT INTO #results SELECT 'Pareto curve never goes down', 0, COUNT(*)
FROM (SELECT cumulative_pct_revenue - LAG(cumulative_pct_revenue) OVER (ORDER BY spend_rank) AS step
      FROM analytics.v_customer_pareto) AS s
WHERE s.step < 0;

/* ---- Purchase sequence -------------------------------------------------- */
INSERT INTO #results SELECT 'Last running spend = lifetime spend', 0, COUNT(*)
FROM (SELECT customer_id, running_spend,
             ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_number DESC) AS rn
      FROM analytics.v_order_sequence) AS l
INNER JOIN analytics.v_customer_rfm AS r ON r.customer_id = l.customer_id
WHERE l.rn = 1 AND l.running_spend <> r.monetary;

INSERT INTO #results SELECT 'First order has no previous-order gap', 0,
    (SELECT COUNT(*) FROM analytics.v_order_sequence WHERE order_number = 1 AND days_since_previous IS NOT NULL);

/* ---- Market basket ------------------------------------------------------ */
-- The four pairs the shop sells together should have the highest lift
INSERT INTO #results SELECT 'Known product pairs are the top 4 by lift', 4, COUNT(*)
FROM (SELECT TOP (4) item_a, item_b FROM analytics.v_product_pairs
      WHERE orders_with_both >= 30 ORDER BY lift DESC) AS t
WHERE (t.item_a = N'Filter Coffee 500g' AND t.item_b = N'Paper Filters x100')
   OR (t.item_a = N'Rooibos Tea 80s'    AND t.item_b = N'Rusks 500g')
   OR (t.item_a = N'Milk Frother'       AND t.item_b = N'Oat Milk 1L')
   OR (t.item_a = N'Espresso Beans 1kg' AND t.item_b = N'Moka Pot');

/* ---- Churn model -------------------------------------------------------- */
-- No leakage: no feature may be computed from orders after the snapshot
INSERT INTO #results SELECT 'Churn features use no orders after the snapshot', 0, COUNT(*)
FROM ml.customer_features
WHERE recency_days < 0 OR tenure_days < 0;

INSERT INTO #results SELECT 'Risk table learned from the training snapshot only',
    (SELECT COUNT(*) FROM ml.customer_features WHERE data_split = 'train'),
    (SELECT SUM(train_customers) FROM ml.churn_risk_table);

INSERT INTO #results SELECT 'Every test customer scored',
    (SELECT COUNT(*) FROM ml.customer_features WHERE data_split = 'test'),
    (SELECT COUNT(*) FROM ml.churn_scores);

INSERT INTO #results SELECT 'Probabilities between 0 and 1', 0,
    (SELECT COUNT(*) FROM ml.churn_scores WHERE churn_probability <= 0 OR churn_probability >= 1);

INSERT INTO #results SELECT 'Model beats the base rate (Brier score)', 1,
    (SELECT CASE WHEN brier_score < brier_baseline THEN 1 ELSE 0 END FROM ml.churn_evaluation);

INSERT INTO #results SELECT 'High-risk list finds churners better than random (lift > 1)', 1,
    (SELECT CASE WHEN lift_vs_random > 1 THEN 1 ELSE 0 END FROM ml.churn_evaluation);

/* ---- Results ------------------------------------------------------------ */
SELECT test_id, test_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS result
FROM #results
ORDER BY test_id;

IF EXISTS (SELECT 1 FROM #results WHERE actual IS NULL OR expected <> actual)
    THROW 50006, 'Analytics tests failed. See the results grid.', 1;
GO
