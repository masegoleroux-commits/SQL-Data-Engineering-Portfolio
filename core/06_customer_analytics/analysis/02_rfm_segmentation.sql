/* =============================================================================
   02_rfm_segmentation.sql
   Business parameters, the shared order view, and RFM segmentation.

   RFM scores every customer 1-5 on three questions:
     R  Recency    how recently did they buy?   (more recent = better)
     F  Frequency  how often do they buy?       (more = better)
     M  Monetary   how much have they spent?    (more = better)
   NTILE(5) splits customers into five equal groups for each question.
============================================================================= */

USE CustomerAnalytics;
GO

/* ---- Business parameters ------------------------------------------------ */
DROP TABLE IF EXISTS analytics.business_parameter;
CREATE TABLE analytics.business_parameter (
    param_name     VARCHAR(50)     NOT NULL PRIMARY KEY,
    numeric_value  DECIMAL(12, 2)  NULL,
    date_value     DATE            NULL,
    description    NVARCHAR(200)   NOT NULL
);

INSERT INTO analytics.business_parameter VALUES
    ('analysis_date',          NULL, '2025-01-01', N'"Today" for recency. Fixed so results are reproducible'),
    ('churn_days',             180,  NULL,         N'No order for this many days = churned'),
    ('min_pair_orders',        30,   NULL,         N'Minimum orders containing a product pair before it is reported'),
    ('mature_cohort_cutoff',   NULL, '2024-01-01', N'Only customers acquired before this date are used to compare channels'),
    ('churn_train_snapshot',   NULL, '2023-12-31', N'Snapshot date the churn model learns from'),
    ('churn_test_snapshot',    NULL, '2024-06-30', N'Snapshot date the churn model is tested on'),
    ('high_risk_share',        0.20, NULL,         N'Share of customers flagged as high churn risk for a retention campaign');
GO

/* ---- One row per order with its value (used by every analysis) --------- */
CREATE OR ALTER VIEW analytics.v_order_value
AS
SELECT o.order_id,
       o.customer_id,
       o.order_date,
       DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1) AS order_month,
       COUNT(*)                          AS line_count,
       SUM(i.quantity)                   AS units,
       SUM(i.quantity * i.unit_price)    AS order_value
FROM shop.orders AS o
INNER JOIN shop.order_item AS i ON i.order_id = o.order_id
GROUP BY o.order_id, o.customer_id, o.order_date;
GO

/* ---- RFM ---------------------------------------------------------------- */
CREATE OR ALTER VIEW analytics.v_customer_rfm
AS
WITH base AS (
    SELECT customer_id,
           DATEDIFF(DAY, MAX(order_date),
                    (SELECT date_value FROM analytics.business_parameter WHERE param_name = 'analysis_date')) AS recency_days,
           COUNT(*)          AS frequency,
           SUM(order_value)  AS monetary,
           MIN(order_date)   AS first_order_date
    FROM analytics.v_order_value
    GROUP BY customer_id
),
scored AS (
    SELECT b.*,
           -- recency sorted DESC so the most recent buyers land in group 5;
           -- customer_id breaks ties so the result is the same every run
           NTILE(5) OVER (ORDER BY recency_days DESC, customer_id) AS r_score,
           NTILE(5) OVER (ORDER BY frequency, customer_id)         AS f_score,
           NTILE(5) OVER (ORDER BY monetary, customer_id)          AS m_score
    FROM base AS b
)
SELECT s.*,
       CONCAT(r_score, f_score, m_score) AS rfm_cell,
       CASE
           WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
           WHEN r_score >= 3 AND f_score >= 3                  THEN 'Loyal'
           WHEN r_score >= 4 AND f_score <= 2                  THEN 'New / Promising'
           WHEN r_score <= 2 AND f_score >= 3                  THEN 'At risk'
           WHEN r_score  = 3 AND f_score <= 2                  THEN 'Needs attention'
           ELSE 'Hibernating'
       END AS segment
FROM scored AS s;
GO

-- Segment size, value and share of revenue
SELECT segment,
       COUNT(*)                                                               AS customers,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5, 1))         AS pct_customers,
       AVG(recency_days)                                                      AS avg_recency_days,
       CAST(AVG(1.0 * frequency) AS DECIMAL(5, 1))                            AS avg_orders,
       CAST(AVG(monetary) AS DECIMAL(10, 0))                                  AS avg_spend,
       -- window over an aggregate: SUM(SUM(x)) OVER () is the grand total
       CAST(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER () AS DECIMAL(5, 1)) AS pct_revenue
FROM analytics.v_customer_rfm
GROUP BY segment
ORDER BY SUM(monetary) DESC;
GO
