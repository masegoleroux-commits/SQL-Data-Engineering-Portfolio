/* =============================================================================
   05_pareto_and_value.sql
   Who drives revenue, and which acquisition channel brings valuable customers.
============================================================================= */

USE CustomerAnalytics;
GO

CREATE OR ALTER VIEW analytics.v_customer_pareto
AS
SELECT customer_id,
       monetary,
       ROW_NUMBER() OVER (ORDER BY monetary DESC, customer_id) AS spend_rank,
       CAST(100.0 * ROW_NUMBER() OVER (ORDER BY monetary DESC, customer_id) / COUNT(*) OVER () AS DECIMAL(6, 2))
                                                               AS pct_of_customers,
       CAST(100.0 * SUM(monetary) OVER (ORDER BY monetary DESC, customer_id ROWS UNBOUNDED PRECEDING)
                  / SUM(monetary) OVER () AS DECIMAL(6, 2))   AS cumulative_pct_revenue
FROM analytics.v_customer_rfm;
GO

-- Churn rule in one place: no order within churn_days of the analysis date
CREATE OR ALTER VIEW analytics.v_customer_status
AS
SELECT r.customer_id,
       c.acquisition_channel,
       c.province,
       r.frequency,
       r.monetary,
       r.recency_days,
       r.first_order_date,
       CASE WHEN r.recency_days > (SELECT numeric_value FROM analytics.business_parameter WHERE param_name = 'churn_days')
            THEN 1 ELSE 0 END AS is_churned
FROM analytics.v_customer_rfm AS r
INNER JOIN shop.customer AS c ON c.customer_id = r.customer_id;
GO

-- 1. Pareto: what share of customers brings in 50 / 80 / 95% of revenue?
SELECT CONCAT(t.target_pct, '%') AS revenue_share,
       CONCAT((SELECT MIN(pct_of_customers) FROM analytics.v_customer_pareto
               WHERE cumulative_pct_revenue >= t.target_pct), '%') AS customers_needed
FROM (VALUES (50), (80), (95)) AS t (target_pct);

-- 2. Customer value by acquisition channel. Only customers acquired before
--    mature_cohort_cutoff, so every customer has had at least a year.
DECLARE @cutoff DATE = (SELECT date_value FROM analytics.business_parameter WHERE param_name = 'mature_cohort_cutoff');

SELECT acquisition_channel,
       COUNT(*)                                                 AS customers,
       CAST(AVG(monetary) AS DECIMAL(10, 0))                    AS avg_lifetime_value,
       -- total revenue / total orders, never an average of averages
       CAST(SUM(monetary) / SUM(frequency) AS DECIMAL(10, 0))   AS avg_order_value,
       CAST(AVG(1.0 * frequency) AS DECIMAL(5, 2))              AS avg_orders,
       CAST(100.0 * AVG(1.0 * is_churned) AS DECIMAL(5, 1))     AS churn_rate_pct
FROM analytics.v_customer_status
WHERE first_order_date < @cutoff
GROUP BY acquisition_channel
ORDER BY avg_lifetime_value DESC;
GO
