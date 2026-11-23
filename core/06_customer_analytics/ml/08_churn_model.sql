/* =============================================================================
   08_churn_model.sql
   Predicts which customers are about to stop buying, so a retention team
   can contact them first.

   Setup (dates come from analytics.business_parameter)
     snapshot date   pretend "today" is this date
     features        built ONLY from orders on or before the snapshot
     label           churned = no order in the churn_days after the snapshot

   Two snapshots
     train  2023-12-31  learn churn rates per customer profile
     test   2024-06-30  score customers with what was learned, then compare
                        with what really happened

   The model is a churn-risk table: customers are grouped by recency band
   and frequency band (the two strongest churn signals), and the churn rate
   of each group in the training snapshot becomes the predicted probability.
   It is simple, explainable to a marketing manager, and gives a baseline
   any more complex model (e.g. in Python) has to beat.
============================================================================= */

USE CustomerAnalytics;
GO

SET NOCOUNT ON;

DECLARE @train_snapshot DATE = (SELECT date_value FROM analytics.business_parameter WHERE param_name = 'churn_train_snapshot'),
        @test_snapshot  DATE = (SELECT date_value FROM analytics.business_parameter WHERE param_name = 'churn_test_snapshot'),
        @churn_days     INT  = (SELECT numeric_value FROM analytics.business_parameter WHERE param_name = 'churn_days');

/* ---- 1. Feature table: one row per customer per snapshot ----------------- */
DROP TABLE IF EXISTS ml.customer_features;

WITH snapshots AS (
    SELECT 'train' AS data_split, @train_snapshot AS snapshot_date
    UNION ALL
    SELECT 'test', @test_snapshot
),
history AS (
    -- only orders up to the snapshot: nothing from the future leaks in
    SELECT s.data_split, s.snapshot_date, ov.customer_id, ov.order_date, ov.order_value
    FROM snapshots AS s
    INNER JOIN analytics.v_order_value AS ov ON ov.order_date <= s.snapshot_date
)
SELECT
    h.data_split,
    h.snapshot_date,
    h.customer_id,
    c.acquisition_channel,
    DATEDIFF(DAY, MAX(h.order_date), h.snapshot_date)                         AS recency_days,
    COUNT(*)                                                                  AS frequency,
    SUM(h.order_value)                                                        AS monetary,
    DATEDIFF(DAY, MIN(h.order_date), h.snapshot_date)                         AS tenure_days,
    SUM(CASE WHEN h.order_date > DATEADD(DAY, -90, h.snapshot_date) THEN 1 ELSE 0 END)  AS orders_last_90d,
    SUM(CASE WHEN h.order_date >  DATEADD(DAY, -180, h.snapshot_date)
              AND h.order_date <= DATEADD(DAY, -90,  h.snapshot_date) THEN 1 ELSE 0 END) AS orders_prev_90d,
    -- label: did the customer order again within churn_days after the snapshot?
    CASE WHEN EXISTS (SELECT 1 FROM shop.orders AS o
                      WHERE o.customer_id = h.customer_id
                        AND o.order_date >  h.snapshot_date
                        AND o.order_date <= DATEADD(DAY, @churn_days, h.snapshot_date))
         THEN 0 ELSE 1 END                                                    AS churned
INTO ml.customer_features
FROM history AS h
INNER JOIN shop.customer AS c ON c.customer_id = h.customer_id
GROUP BY h.data_split, h.snapshot_date, h.customer_id, c.acquisition_channel;

-- SELECT INTO cannot declare keys, so make the key columns NOT NULL and add the key
ALTER TABLE ml.customer_features ALTER COLUMN data_split VARCHAR(5) NOT NULL;
ALTER TABLE ml.customer_features ALTER COLUMN customer_id INT NOT NULL;
ALTER TABLE ml.customer_features ADD CONSTRAINT pk_customer_features PRIMARY KEY (data_split, customer_id);

-- Bands used by the model
ALTER TABLE ml.customer_features ADD
    recency_band   AS (CASE WHEN recency_days <= 30  THEN '1: 0-30 days'
                            WHEN recency_days <= 90  THEN '2: 31-90 days'
                            WHEN recency_days <= 180 THEN '3: 91-180 days'
                            ELSE '4: 180+ days' END),
    frequency_band AS (CASE WHEN frequency = 1  THEN '1: one order'
                            WHEN frequency <= 3 THEN '2: 2-3 orders'
                            WHEN frequency <= 7 THEN '3: 4-7 orders'
                            ELSE '4: 8+ orders' END);
GO

/* ---- 2. Train: churn rate per recency x frequency band ------------------- */
DROP TABLE IF EXISTS ml.churn_risk_table;

SELECT recency_band,
       frequency_band,
       COUNT(*)      AS train_customers,
       SUM(churned)  AS train_churned,
       -- +1 / +2 smoothing keeps small groups away from 0% or 100%
       (SUM(churned) + 1.0) / (COUNT(*) + 2.0) AS churn_probability
INTO ml.churn_risk_table
FROM ml.customer_features
WHERE data_split = 'train'
GROUP BY recency_band, frequency_band;

/* ---- 3. Score the test snapshot ------------------------------------------ */
DECLARE @high_risk_share DECIMAL(4, 2) = (SELECT numeric_value FROM analytics.business_parameter WHERE param_name = 'high_risk_share'),
        @base_rate FLOAT = (SELECT AVG(1.0 * churned) FROM ml.customer_features WHERE data_split = 'train');

DROP TABLE IF EXISTS ml.churn_scores;

SELECT f.customer_id,
       f.snapshot_date,
       f.recency_band,
       f.frequency_band,
       -- a profile never seen in training falls back to the overall churn rate
       COALESCE(r.churn_probability, @base_rate)                         AS churn_probability,
       PERCENT_RANK() OVER (ORDER BY COALESCE(r.churn_probability, @base_rate) DESC, f.customer_id) AS risk_percentile,
       f.churned                                                        AS actually_churned
INTO ml.churn_scores
FROM ml.customer_features AS f
LEFT JOIN ml.churn_risk_table AS r
    ON r.recency_band = f.recency_band AND r.frequency_band = f.frequency_band
WHERE f.data_split = 'test';

/* ---- 4. Evaluate --------------------------------------------------------- */
-- If the retention team can only call the top 20%, how many of the
-- customers who really churned are in that list (recall), how many of the
-- list really churned (precision), and how much better is that than
-- picking customers at random (lift)?
DROP TABLE IF EXISTS ml.churn_evaluation;

SELECT
    COUNT(*)                                                                         AS test_customers,
    CAST(100.0 * AVG(1.0 * actually_churned) AS DECIMAL(5, 1))                       AS actual_churn_rate_pct,
    SUM(CASE WHEN risk_percentile < @high_risk_share THEN 1 ELSE 0 END)              AS flagged_high_risk,
    CAST(100.0 * SUM(CASE WHEN risk_percentile < @high_risk_share THEN actually_churned ELSE 0 END)
               / NULLIF(SUM(CASE WHEN risk_percentile < @high_risk_share THEN 1 ELSE 0 END), 0)
         AS DECIMAL(5, 1))                                                           AS precision_pct,
    CAST(100.0 * SUM(CASE WHEN risk_percentile < @high_risk_share THEN actually_churned ELSE 0 END)
               / NULLIF(SUM(actually_churned), 0) AS DECIMAL(5, 1))                  AS recall_pct,
    CAST((1.0 * SUM(CASE WHEN risk_percentile < @high_risk_share THEN actually_churned ELSE 0 END)
               / NULLIF(SUM(CASE WHEN risk_percentile < @high_risk_share THEN 1 ELSE 0 END), 0))
         / NULLIF(AVG(1.0 * actually_churned), 0) AS DECIMAL(5, 2))                  AS lift_vs_random,
    -- Brier score: mean squared error of the probabilities (lower is better)
    CAST(AVG(SQUARE(churn_probability - actually_churned)) AS DECIMAL(6, 4))         AS brier_score,
    CAST(AVG(SQUARE(@base_rate - actually_churned)) AS DECIMAL(6, 4))                AS brier_baseline
INTO ml.churn_evaluation
FROM ml.churn_scores;
GO

SELECT recency_band, frequency_band, train_customers, train_churned,
       CAST(100 * churn_probability AS DECIMAL(5, 1)) AS churn_probability_pct
FROM ml.churn_risk_table
ORDER BY recency_band, frequency_band;

SELECT * FROM ml.churn_evaluation;

-- The call list: highest-risk customers that still have value worth saving
SELECT TOP (20) s.customer_id, c.acquisition_channel, f.recency_days, f.frequency,
       CAST(f.monetary AS DECIMAL(10, 0)) AS lifetime_spend,
       CAST(100 * s.churn_probability AS DECIMAL(5, 1)) AS churn_probability_pct
FROM ml.churn_scores AS s
INNER JOIN ml.customer_features AS f ON f.customer_id = s.customer_id AND f.data_split = 'test'
INNER JOIN shop.customer AS c ON c.customer_id = s.customer_id
WHERE f.frequency >= 3
ORDER BY s.churn_probability DESC, f.monetary DESC;
GO
