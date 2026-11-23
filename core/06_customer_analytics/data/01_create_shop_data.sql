/* =============================================================================
   01_create_shop_data.sql
   CustomerAnalytics database: two years of orders for an online coffee and
   kitchen shop (synthetic data, identical on every run).

   Behaviour built into the data so the analysis has patterns to find:
     * every customer has an active lifetime, after which they stop buying
     * referral customers tend to stay longer, social-ads customers shorter
     * December has extra gift-season orders
     * some products are usually bought together

   Pseudo-random numbers come from dbo.fn_rand, a hash of the inputs, so
   the "random" data is the same on every machine and every run.
============================================================================= */

IF DB_ID(N'CustomerAnalytics') IS NULL
    CREATE DATABASE CustomerAnalytics;
GO

USE CustomerAnalytics;
GO

IF SCHEMA_ID(N'shop')      IS NULL EXEC (N'CREATE SCHEMA shop AUTHORIZATION dbo;');
IF SCHEMA_ID(N'analytics') IS NULL EXEC (N'CREATE SCHEMA analytics AUTHORIZATION dbo;');
IF SCHEMA_ID(N'ml')        IS NULL EXEC (N'CREATE SCHEMA ml AUTHORIZATION dbo;');
GO

-- Deterministic number in [0, 1) from three integers
CREATE OR ALTER FUNCTION dbo.fn_rand (@a BIGINT, @b BIGINT, @stream INT)
RETURNS FLOAT
WITH SCHEMABINDING
AS
BEGIN
    RETURN CAST(CAST(HASHBYTES('MD5', CONCAT(@a, ':', @b, ':', @stream)) AS BINARY(4)) AS BIGINT) / 4294967296.0;
END;
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS shop.order_item;
DROP TABLE IF EXISTS shop.orders;
DROP TABLE IF EXISTS shop.customer;
DROP TABLE IF EXISTS shop.product_affinity;
DROP TABLE IF EXISTS shop.product;

CREATE TABLE shop.product (
    product_id    INT            NOT NULL PRIMARY KEY,
    product_name  NVARCHAR(60)   NOT NULL,
    category      NVARCHAR(30)   NOT NULL,
    unit_price    DECIMAL(8, 2)  NOT NULL
);

CREATE TABLE shop.customer (
    customer_id          INT           NOT NULL PRIMARY KEY,
    signup_date          DATE          NOT NULL,
    acquisition_channel  NVARCHAR(30)  NOT NULL,
    province             NVARCHAR(30)  NOT NULL
);

CREATE TABLE shop.orders (
    order_id     INT   NOT NULL PRIMARY KEY,
    customer_id  INT   NOT NULL REFERENCES shop.customer (customer_id),
    order_date   DATE  NOT NULL
);
CREATE INDEX ix_orders_customer ON shop.orders (customer_id, order_date);

CREATE TABLE shop.order_item (
    order_id     INT           NOT NULL REFERENCES shop.orders (order_id),
    product_id   INT           NOT NULL REFERENCES shop.product (product_id),
    quantity     INT           NOT NULL CHECK (quantity > 0),
    unit_price   DECIMAL(8, 2) NOT NULL,
    PRIMARY KEY (order_id, product_id)
);

INSERT INTO shop.product VALUES
 ( 1, N'Espresso Beans 1kg', N'Coffee', 329),   ( 2, N'Burr Grinder', N'Equipment', 1499),
 ( 3, N'Filter Coffee 500g', N'Coffee', 179),   ( 4, N'Paper Filters x100', N'Accessories', 59),
 ( 5, N'Rooibos Tea 80s', N'Tea', 89),          ( 6, N'Ceramic Teapot', N'Kitchen', 399),
 ( 7, N'French Press', N'Equipment', 549),      ( 8, N'Decaf Beans 500g', N'Coffee', 199),
 ( 9, N'Milk Frother', N'Equipment', 799),      (10, N'Oat Milk 1L', N'Pantry', 42),
 (11, N'Rusks 500g', N'Pantry', 69),            (12, N'Honey 500g', N'Pantry', 119),
 (13, N'Travel Mug', N'Accessories', 249),      (14, N'Descaler', N'Accessories', 129),
 (15, N'Moka Pot', N'Equipment', 459),          (16, N'Hot Chocolate 500g', N'Pantry', 99),
 (17, N'Gift Card R500', N'Gift', 500),         (18, N'Biscotti', N'Pantry', 85),
 (19, N'Cold Brew Kit', N'Equipment', 689),     (20, N'Chai Blend 250g', N'Tea', 109);

-- Products that tend to be bought together
CREATE TABLE shop.product_affinity (product_id INT PRIMARY KEY, partner_id INT NOT NULL);
INSERT INTO shop.product_affinity VALUES (3, 4), (5, 11), (9, 10), (15, 1);

-- Numbers 1..4000
DROP TABLE IF EXISTS #n;
SELECT TOP (4000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
INTO #n FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

/* ---- Customers ---------------------------------------------------------- */
INSERT INTO shop.customer
SELECT n,
       DATEADD(DAY, CAST(dbo.fn_rand(n, 0, 1) * 730 AS INT), '2023-01-01'),
       CASE WHEN r < 0.35 THEN N'Organic search'
            WHEN r < 0.60 THEN N'Social ads'
            WHEN r < 0.80 THEN N'Referral'
            WHEN r < 0.95 THEN N'Email'
            ELSE N'Marketplace' END,
       CHOOSE(CAST(dbo.fn_rand(n, 0, 3) * 6 AS INT) + 1,
              N'Gauteng', N'Gauteng', N'Western Cape', N'KwaZulu-Natal', N'Eastern Cape', N'Free State')
FROM #n
CROSS APPLY (SELECT dbo.fn_rand(n, 0, 2) AS r) AS x;

/* ---- Active lifetime per customer --------------------------------------- */
-- Exponential lifetime: -ln(U) x mean. Referral customers stay twice as
-- long, social-ads customers half as long.
DROP TABLE IF EXISTS #life;
SELECT c.customer_id,
       c.signup_date,
       CASE WHEN DATEADD(DAY, l.days, c.signup_date) > '2024-12-31' THEN CAST('2024-12-31' AS DATE)
            ELSE DATEADD(DAY, l.days, c.signup_date) END                 AS last_active,
       1 + CAST(dbo.fn_rand(c.customer_id, 0, 5) * 3 AS INT)             AS orders_per_quarter
INTO #life
FROM shop.customer AS c
CROSS APPLY (SELECT CAST(-LOG(1 - dbo.fn_rand(c.customer_id, 0, 4)) * 200
                     * CASE c.acquisition_channel WHEN N'Referral' THEN 2.0 WHEN N'Social ads' THEN 0.5 ELSE 1.0 END
                     AS INT) AS days) AS l;

/* ---- Orders ------------------------------------------------------------- */
DROP TABLE IF EXISTS #o;
CREATE TABLE #o (customer_id INT, order_date DATE);

-- first order on the signup day
INSERT INTO #o SELECT customer_id, signup_date FROM #life;

-- repeat orders spread across the active lifetime
INSERT INTO #o
SELECT l.customer_id,
       DATEADD(DAY, 1 + CAST(dbo.fn_rand(l.customer_id, k.n, 6) * (DATEDIFF(DAY, l.signup_date, l.last_active) - 1) AS INT), l.signup_date)
FROM #life AS l
INNER JOIN #n AS k
    ON k.n <= CAST(DATEDIFF(DAY, l.signup_date, l.last_active) / 90.0 * l.orders_per_quarter AS INT)
WHERE DATEDIFF(DAY, l.signup_date, l.last_active) > 1;

-- December gift-season orders for customers active on 1 December
INSERT INTO #o
SELECT l.customer_id, DATEFROMPARTS(y.y, 12, 5 + CAST(dbo.fn_rand(l.customer_id, y.y, 8) * 15 AS INT))
FROM #life AS l
CROSS JOIN (VALUES (2023), (2024)) AS y (y)
WHERE DATEFROMPARTS(y.y, 12, 1) BETWEEN l.signup_date AND l.last_active
  AND dbo.fn_rand(l.customer_id, y.y, 7) < 0.5;

INSERT INTO shop.orders (order_id, customer_id, order_date)
SELECT ROW_NUMBER() OVER (ORDER BY order_date, customer_id), customer_id, order_date
FROM #o;

/* ---- Order lines -------------------------------------------------------- */
-- line 1: any product; line 2 (60% of orders): the usual partner 70% of the
-- time if there is one; line 3 (30% of orders): any product.
DROP TABLE IF EXISTS #first;
SELECT order_id, 1 + CAST(dbo.fn_rand(order_id, 0, 10) * 20 AS INT) AS first_product
INTO #first
FROM shop.orders;

WITH lines AS (
    SELECT order_id, first_product AS product_id FROM #first
    UNION ALL
    SELECT f.order_id,
           CASE WHEN a.partner_id IS NOT NULL AND dbo.fn_rand(f.order_id, 0, 12) < 0.7 THEN a.partner_id
                ELSE 1 + CAST(dbo.fn_rand(f.order_id, 0, 13) * 20 AS INT) END
    FROM #first AS f
    LEFT JOIN shop.product_affinity AS a ON a.product_id = f.first_product
    WHERE dbo.fn_rand(f.order_id, 0, 11) < 0.6
    UNION ALL
    SELECT order_id, 1 + CAST(dbo.fn_rand(order_id, 0, 15) * 20 AS INT)
    FROM #first
    WHERE dbo.fn_rand(order_id, 0, 14) < 0.3
)
INSERT INTO shop.order_item (order_id, product_id, quantity, unit_price)
SELECT l.order_id, l.product_id,
       1 + CAST(dbo.fn_rand(l.order_id, l.product_id, 16) * 3 AS INT),
       p.unit_price
FROM (SELECT DISTINCT order_id, product_id FROM lines) AS l      -- same product twice = one line
INNER JOIN shop.product AS p ON p.product_id = l.product_id;

SELECT (SELECT COUNT(*) FROM shop.customer)   AS customers,
       (SELECT COUNT(*) FROM shop.orders)     AS orders,
       (SELECT COUNT(*) FROM shop.order_item) AS order_lines,
       (SELECT MIN(order_date) FROM shop.orders) AS first_order,
       (SELECT MAX(order_date) FROM shop.orders) AS last_order;
GO
