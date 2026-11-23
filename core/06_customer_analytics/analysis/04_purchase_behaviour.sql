/* =============================================================================
   04_purchase_behaviour.sql
   Time-series window functions:
     LAG()                                   previous value (gap, month-on-month)
     SUM() OVER (ROWS UNBOUNDED PRECEDING)   running total
     AVG() OVER (ROWS BETWEEN 2 PRECEDING
                 AND CURRENT ROW)            3-month moving average
     PERCENTILE_CONT(0.5)                    median, more honest than the mean
                                             for skewed data like gaps between orders
============================================================================= */

USE CustomerAnalytics;
GO

-- Every order with the previous order date and running spend for that customer
CREATE OR ALTER VIEW analytics.v_order_sequence
AS
SELECT order_id,
       customer_id,
       order_date,
       order_value,
       ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id)            AS order_number,
       DATEDIFF(DAY, LAG(order_date) OVER (PARTITION BY customer_id ORDER BY order_date, order_id), order_date)
                                                                                         AS days_since_previous,
       SUM(order_value) OVER (PARTITION BY customer_id ORDER BY order_date, order_id
                              ROWS UNBOUNDED PRECEDING)                                   AS running_spend
FROM analytics.v_order_value;
GO

-- Monthly revenue with growth and smoothing
CREATE OR ALTER VIEW analytics.v_monthly_revenue
AS
WITH m AS (
    SELECT order_month,
           COUNT(DISTINCT customer_id) AS active_customers,
           COUNT(*)                    AS orders,
           SUM(order_value)            AS revenue
    FROM analytics.v_order_value
    GROUP BY order_month
)
SELECT order_month,
       active_customers,
       orders,
       revenue,
       CAST(100.0 * (revenue - LAG(revenue) OVER (ORDER BY order_month))
                  / LAG(revenue) OVER (ORDER BY order_month) AS DECIMAL(6, 1))            AS mom_growth_pct,
       -- same month last year = 12 rows back (safe here: no month is missing)
       CAST(100.0 * (revenue - LAG(revenue, 12) OVER (ORDER BY order_month))
                  / LAG(revenue, 12) OVER (ORDER BY order_month) AS DECIMAL(6, 1))        AS yoy_growth_pct,
       CAST(AVG(revenue) OVER (ORDER BY order_month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS DECIMAL(12, 0))
                                                                                          AS revenue_3m_avg,
       SUM(revenue) OVER (PARTITION BY YEAR(order_month) ORDER BY order_month
                          ROWS UNBOUNDED PRECEDING)                                       AS revenue_ytd
FROM m;
GO

-- 1. Monthly revenue in 2024
SELECT FORMAT(order_month, 'yyyy-MM') AS month, orders, revenue,
       mom_growth_pct, yoy_growth_pct, revenue_3m_avg, revenue_ytd
FROM analytics.v_monthly_revenue
WHERE order_month >= '2024-01-01'
ORDER BY order_month;

-- 2. How long until customers come back? Median vs mean gap
SELECT DISTINCT
       step,
       COUNT(*) OVER (PARTITION BY step)                                                 AS orders,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY days_since_previous) OVER (PARTITION BY step) AS median_days,
       CAST(AVG(1.0 * days_since_previous) OVER (PARTITION BY step) AS DECIMAL(6, 1))    AS mean_days
FROM (
    SELECT CASE WHEN order_number = 2 THEN '1st -> 2nd order'
                WHEN order_number = 3 THEN '2nd -> 3rd order'
                ELSE '3rd+ repeat orders' END AS step,
           days_since_previous
    FROM analytics.v_order_sequence
    WHERE order_number >= 2
) AS s
ORDER BY step;

-- 3. On which order did customers pass R5,000 lifetime spend?
WITH first_cross AS (
    SELECT customer_id, MIN(order_number) AS crossed_on_order
    FROM analytics.v_order_sequence
    WHERE running_spend >= 5000
    GROUP BY customer_id
)
SELECT TOP (8) crossed_on_order, COUNT(*) AS customers
FROM first_cross
GROUP BY crossed_on_order
ORDER BY crossed_on_order;
GO
