/* =============================================================================
   05_point_in_time_queries.sql
   The questions a Type 2 dimension can answer and a Type 1 cannot.
============================================================================= */

USE CustomerHistory;
GO

-- 1. Full history of one customer (187 moved city AND changed tier)
SELECT customer_sk, version_number, city, province, loyalty_tier,
       valid_from, valid_to, is_current, is_deleted
FROM dbo.dim_customer
WHERE customer_id = 187
ORDER BY version_number;

-- 2. "As at" view: what did the customer base look like on 15 February 2024?
SELECT loyalty_tier, COUNT(*) AS customers
FROM dbo.dim_customer
WHERE '2024-02-15' BETWEEN valid_from AND valid_to
  AND is_deleted = 0
GROUP BY loyalty_tier
ORDER BY loyalty_tier;

-- 3. Revenue by tier: history as it happened vs. restated with today's tier.
--    The difference is what a Type 1 dimension would get wrong without
--    anyone noticing.
WITH as_it_was AS (
    SELECT d.loyalty_tier, SUM(f.order_amount) AS revenue
    FROM dbo.fact_orders AS f
    INNER JOIN dbo.dim_customer AS d ON d.customer_sk = f.customer_sk
    GROUP BY d.loyalty_tier
),
restated AS (
    SELECT d.loyalty_tier, SUM(f.order_amount) AS revenue
    FROM dbo.fact_orders AS f
    INNER JOIN dbo.dim_customer AS d ON d.customer_id = f.customer_id AND d.is_current = 1
    GROUP BY d.loyalty_tier
)
SELECT COALESCE(w.loyalty_tier, r.loyalty_tier)              AS loyalty_tier,
       w.revenue                                            AS revenue_as_it_was,
       r.revenue                                            AS revenue_with_todays_tier,
       COALESCE(r.revenue, 0) - COALESCE(w.revenue, 0)      AS overstatement,
       CAST(100.0 * (COALESCE(r.revenue, 0) - COALESCE(w.revenue, 0)) / NULLIF(w.revenue, 0) AS DECIMAL(5, 1)) AS overstatement_pct
FROM as_it_was AS w
FULL OUTER JOIN restated AS r ON r.loyalty_tier = w.loyalty_tier
ORDER BY loyalty_tier;

-- 4. Tier movement between January and April
SELECT jan.loyalty_tier AS tier_jan_2024,
       apr.loyalty_tier AS tier_apr_2024,
       COUNT(*)         AS customers
FROM dbo.dim_customer AS jan
INNER JOIN dbo.dim_customer AS apr
    ON  apr.customer_id = jan.customer_id
    AND '2024-04-01' BETWEEN apr.valid_from AND apr.valid_to
WHERE '2024-01-01' BETWEEN jan.valid_from AND jan.valid_to
GROUP BY jan.loyalty_tier, apr.loyalty_tier
ORDER BY tier_jan_2024, tier_apr_2024;

-- 5. Load history
SELECT * FROM dbo.load_audit ORDER BY batch_date;

-- 6. The column rules the load follows
SELECT column_name, scd_type, reason FROM dbo.scd_column_policy ORDER BY scd_type, column_name;
GO
