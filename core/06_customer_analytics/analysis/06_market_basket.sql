/* =============================================================================
   06_market_basket.sql
   "Customers who bought X also bought Y" with association-rule measures.

   For a pair A, B:
     support     orders with both / all orders                 how common
     confidence  orders with both / orders with A              chance of B given A
     lift        confidence / share of orders with B           > 1 together more
                                                               than chance would give
   The self-join (a.product_id < b.product_id) lists each pair once.
============================================================================= */

USE CustomerAnalytics;
GO

CREATE OR ALTER VIEW analytics.v_product_pairs
AS
WITH n AS (
    SELECT CAST(COUNT(DISTINCT order_id) AS DECIMAL(12, 2)) AS total_orders FROM shop.order_item
),
item_orders AS (
    SELECT product_id, COUNT(DISTINCT order_id) AS orders_with_item
    FROM shop.order_item
    GROUP BY product_id
),
pairs AS (
    SELECT a.product_id AS product_a,
           b.product_id AS product_b,
           COUNT(*)     AS orders_with_both
    FROM shop.order_item AS a
    INNER JOIN shop.order_item AS b
        ON  b.order_id   = a.order_id
        AND b.product_id > a.product_id
    GROUP BY a.product_id, b.product_id
)
SELECT pa.product_name AS item_a,
       pb.product_name AS item_b,
       p.orders_with_both,
       CAST(100.0 * p.orders_with_both / n.total_orders AS DECIMAL(5, 2))                     AS support_pct,
       CAST(100.0 * p.orders_with_both / ia.orders_with_item AS DECIMAL(5, 1))                AS conf_a_to_b_pct,
       CAST(100.0 * p.orders_with_both / ib.orders_with_item AS DECIMAL(5, 1))                AS conf_b_to_a_pct,
       CAST(p.orders_with_both * n.total_orders / (1.0 * ia.orders_with_item * ib.orders_with_item) AS DECIMAL(6, 2)) AS lift
FROM pairs AS p
CROSS JOIN n
INNER JOIN item_orders AS ia ON ia.product_id = p.product_a
INNER JOIN item_orders AS ib ON ib.product_id = p.product_b
INNER JOIN shop.product AS pa ON pa.product_id = p.product_a
INNER JOIN shop.product AS pb ON pb.product_id = p.product_b;
GO

DECLARE @min_pair_orders INT = (SELECT numeric_value FROM analytics.business_parameter WHERE param_name = 'min_pair_orders');

-- Strongest pairs by lift (ignoring pairs too rare to trust)
SELECT TOP (8) item_a, item_b, orders_with_both, support_pct, conf_a_to_b_pct, conf_b_to_a_pct, lift
FROM analytics.v_product_pairs
WHERE orders_with_both >= @min_pair_orders
ORDER BY lift DESC;
GO
