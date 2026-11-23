/* =============================================================================
   07_executive_summary.sql
   One query, several levels of subtotal: GROUPING SETS.

   GROUPING SETS ((year, province), (year), (province), ()) gives the same
   rows as four GROUP BY queries joined with UNION ALL, but reads the data
   once. GROUPING(col) = 1 marks a row where that column was rolled up.
============================================================================= */

USE CustomerAnalytics;
GO

CREATE OR ALTER VIEW analytics.v_exec_summary
AS
SELECT CASE WHEN GROUPING(YEAR(ov.order_date)) = 1 THEN 'All years'
            ELSE CAST(YEAR(ov.order_date) AS VARCHAR(9)) END            AS order_year,
       CASE WHEN GROUPING(c.province) = 1 THEN N'All provinces'
            ELSE c.province END                                        AS province,
       GROUPING_ID(YEAR(ov.order_date), c.province)                     AS grouping_level,
       COUNT(DISTINCT ov.customer_id)                                   AS customers,
       COUNT(*)                                                        AS orders,
       SUM(ov.order_value)                                             AS revenue,
       CAST(SUM(ov.order_value) / COUNT(*) AS DECIMAL(10, 2))           AS avg_order_value
FROM analytics.v_order_value AS ov
INNER JOIN shop.customer AS c ON c.customer_id = ov.customer_id
GROUP BY GROUPING SETS (
    (YEAR(ov.order_date), c.province),
    (YEAR(ov.order_date)),
    (c.province),
    ()
);
GO

SELECT order_year, province, customers, orders, revenue, avg_order_value
FROM analytics.v_exec_summary
ORDER BY order_year, grouping_level, revenue DESC;
GO
