/* =============================================================================
   03_cohort_retention.sql
   "Of the customers who first bought in March 2023, what share bought again
   one, two, three... months later?"

   1. cohort       each customer's first order month
   2. activity     every month each customer bought something
   3. months_since DATEDIFF(MONTH, cohort, activity month)
   4. pivot the long list into a grid with COUNT(DISTINCT CASE ...)
============================================================================= */

USE CustomerAnalytics;
GO

CREATE OR ALTER VIEW analytics.v_cohort_activity
AS
WITH cohort AS (
    SELECT customer_id, MIN(order_month) AS cohort_month
    FROM analytics.v_order_value
    GROUP BY customer_id
),
activity AS (
    SELECT DISTINCT customer_id, order_month
    FROM analytics.v_order_value
)
SELECT c.cohort_month,
       a.customer_id,
       a.order_month,
       DATEDIFF(MONTH, c.cohort_month, a.order_month) AS months_since
FROM cohort AS c
INNER JOIN activity AS a ON a.customer_id = c.customer_id;
GO

CREATE OR ALTER VIEW analytics.v_cohort_retention
AS
SELECT cohort_month,
       COUNT(DISTINCT CASE WHEN months_since = 0 THEN customer_id END) AS cohort_size,
       -- months the cohort could have been observed (data ends December 2024)
       DATEDIFF(MONTH, cohort_month, '2024-12-01')                    AS months_observable,
       CAST(100.0 * COUNT(DISTINCT CASE WHEN months_since = 1  THEN customer_id END)
                  / COUNT(DISTINCT CASE WHEN months_since = 0  THEN customer_id END) AS DECIMAL(5, 1)) AS m1,
       CAST(100.0 * COUNT(DISTINCT CASE WHEN months_since = 2  THEN customer_id END)
                  / COUNT(DISTINCT CASE WHEN months_since = 0  THEN customer_id END) AS DECIMAL(5, 1)) AS m2,
       CAST(100.0 * COUNT(DISTINCT CASE WHEN months_since = 3  THEN customer_id END)
                  / COUNT(DISTINCT CASE WHEN months_since = 0  THEN customer_id END) AS DECIMAL(5, 1)) AS m3,
       CAST(100.0 * COUNT(DISTINCT CASE WHEN months_since = 6  THEN customer_id END)
                  / COUNT(DISTINCT CASE WHEN months_since = 0  THEN customer_id END) AS DECIMAL(5, 1)) AS m6,
       CAST(100.0 * COUNT(DISTINCT CASE WHEN months_since = 12 THEN customer_id END)
                  / COUNT(DISTINCT CASE WHEN months_since = 0  THEN customer_id END) AS DECIMAL(5, 1)) AS m12
FROM analytics.v_cohort_activity
GROUP BY cohort_month;
GO

-- Retention grid. Months a cohort has not reached yet are left blank:
-- showing 0% there would make young cohorts look like failures.
SELECT FORMAT(cohort_month, 'yyyy-MM') AS cohort,
       cohort_size,
       CASE WHEN months_observable >= 1  THEN m1  END AS m1,
       CASE WHEN months_observable >= 2  THEN m2  END AS m2,
       CASE WHEN months_observable >= 3  THEN m3  END AS m3,
       CASE WHEN months_observable >= 6  THEN m6  END AS m6,
       CASE WHEN months_observable >= 12 THEN m12 END AS m12
FROM analytics.v_cohort_retention
ORDER BY cohort_month;

-- Retention at month 3 and month 6 by acquisition channel
-- (only cohorts old enough to have reached month 6)
SELECT c.acquisition_channel,
       COUNT(DISTINCT CASE WHEN a.months_since = 0 THEN a.customer_id END) AS customers,
       CAST(100.0 * COUNT(DISTINCT CASE WHEN a.months_since = 3 THEN a.customer_id END)
                  / COUNT(DISTINCT CASE WHEN a.months_since = 0 THEN a.customer_id END) AS DECIMAL(5, 1)) AS m3_retention,
       CAST(100.0 * COUNT(DISTINCT CASE WHEN a.months_since = 6 THEN a.customer_id END)
                  / COUNT(DISTINCT CASE WHEN a.months_since = 0 THEN a.customer_id END) AS DECIMAL(5, 1)) AS m6_retention
FROM analytics.v_cohort_activity AS a
INNER JOIN shop.customer AS c ON c.customer_id = a.customer_id
WHERE a.cohort_month <= '2024-06-01'
GROUP BY c.acquisition_channel
ORDER BY m6_retention DESC;
GO
