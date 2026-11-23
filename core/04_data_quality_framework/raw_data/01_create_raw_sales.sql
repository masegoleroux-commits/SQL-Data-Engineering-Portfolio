/* =============================================================================
   01_create_raw_sales.sql
   A raw landing zone with no constraints, like files dropped by a source
   system, containing a known list of defects. Because every defect is known,
   the tests can check that the framework finds all of them and nothing else.

   The data is synthetic, generated with arithmetic on row numbers so it is
   identical on every run.

   Known defects                                          Count
   -----------------------------------------------------  -----
   customers   : duplicate customer_id rows                   4
   customers   : NULL email                                  12
   customers   : badly formatted email                        8
   customers   : province not in the official list            5
   orders      : customer_id with no matching customer        7
   orders      : order_date in the future                     3
   orders      : status not in the accepted list              2
   orders      : header total <> sum of line items            6
   order_items : quantity <= 0                                4
   order_items : unit_price outside 1 - 50 000                3
   products    : NULL category                                2
                                                    Total    56
============================================================================= */

IF DB_ID(N'DataQuality') IS NULL
    CREATE DATABASE DataQuality;
GO

USE DataQuality;
GO

IF SCHEMA_ID(N'raw_sales') IS NULL EXEC (N'CREATE SCHEMA raw_sales AUTHORIZATION dbo;');
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS raw_sales.order_items;
DROP TABLE IF EXISTS raw_sales.orders;
DROP TABLE IF EXISTS raw_sales.products;
DROP TABLE IF EXISTS raw_sales.customers;

CREATE TABLE raw_sales.customers (
    customer_id  INT, full_name NVARCHAR(100), email NVARCHAR(150), province NVARCHAR(50), created_at DATETIME2(0)
);
CREATE TABLE raw_sales.products (
    product_id INT, product_name NVARCHAR(100), category NVARCHAR(50), list_price DECIMAL(10, 2)
);
CREATE TABLE raw_sales.orders (
    order_id INT, customer_id INT, order_date DATE, status NVARCHAR(20), order_total DECIMAL(12, 2), loaded_at DATETIME2(0)
);
CREATE TABLE raw_sales.order_items (
    order_id INT, line_no INT, product_id INT, quantity INT, unit_price DECIMAL(10, 2)
);

-- Numbers 1..3000
DROP TABLE IF EXISTS #n;
SELECT TOP (3000) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
INTO #n
FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b;

/* ---- Clean base data ---------------------------------------------------- */
INSERT INTO raw_sales.customers
SELECT n, CONCAT(N'Customer ', n), CONCAT(N'customer', n, N'@shop.co.za'),
       CHOOSE(n % 9 + 1, N'Gauteng', N'Western Cape', N'KwaZulu-Natal', N'Eastern Cape', N'Free State',
                         N'Limpopo', N'Mpumalanga', N'North West', N'Northern Cape'),
       DATEADD(HOUR, n, '2024-01-01')
FROM #n WHERE n <= 500;

INSERT INTO raw_sales.products
SELECT n, CONCAT(N'Product ', n),
       CHOOSE(n % 4 + 1, N'Electronics', N'Home', N'Sports', N'Books'),
       50 + (n * 37) % 2000
FROM #n WHERE n <= 80;

-- 1 to 3 lines per order
INSERT INTO raw_sales.order_items
SELECT o.n, l.line_no,
       1 + (o.n * 3 + l.line_no) % 80,
       1 + (o.n + l.line_no) % 4,
       50 + ((1 + (o.n * 3 + l.line_no) % 80) * 37) % 2000
FROM #n AS o
CROSS JOIN (VALUES (1), (2), (3)) AS l (line_no)
WHERE l.line_no <= 1 + o.n % 3;

INSERT INTO raw_sales.orders
SELECT o.n,
       1 + (o.n * 7) % 500,
       DATEADD(DAY, o.n % 360, '2024-01-01'),
       CHOOSE(o.n % 5 + 1, N'COMPLETE', N'COMPLETE', N'COMPLETE', N'SHIPPED', N'RETURNED'),
       (SELECT SUM(i.quantity * i.unit_price) FROM raw_sales.order_items AS i WHERE i.order_id = o.n),
       DATEADD(HOUR, -2, SYSDATETIME())
FROM #n AS o;

/* ---- Known defects ------------------------------------------------------ */
-- 4 duplicate customers (a retried extract loaded them twice)
INSERT INTO raw_sales.customers
SELECT * FROM raw_sales.customers WHERE customer_id IN (10, 20, 30, 40);

-- 12 missing emails
UPDATE raw_sales.customers SET email = NULL
WHERE customer_id BETWEEN 101 AND 112;

-- 8 badly formatted emails
UPDATE c SET c.email = v.bad
FROM raw_sales.customers AS c
INNER JOIN (VALUES (201, N'customer201shop.co.za'), (202, N'customer202@'), (203, N'@shop.co.za'),
                   (204, N'customer 204@shop.co.za'), (205, N'customer205@shop'), (206, N'customer206@@shop.co.za'),
                   (207, N'customer207@shop..co.za'), (208, N'n/a')) AS v (id, bad)
    ON c.customer_id = v.id;

-- 5 non-standard provinces
UPDATE c SET c.province = v.p
FROM raw_sales.customers AS c
INNER JOIN (VALUES (301, N'GP'), (302, N'gauteng'), (303, N'W. Cape'), (304, N'KZN'), (305, N'Unknown')) AS v (id, p)
    ON c.customer_id = v.id;

-- 7 orders for customers that do not exist
UPDATE raw_sales.orders SET customer_id = 9000 + order_id
WHERE order_id IN (11, 22, 33, 44, 55, 66, 77);

-- 3 orders dated in the future
UPDATE raw_sales.orders SET order_date = DATEADD(DAY, 30, CAST(SYSDATETIME() AS DATE))
WHERE order_id IN (100, 200, 300);

-- 2 invalid statuses
UPDATE o SET o.status = v.s
FROM raw_sales.orders AS o
INNER JOIN (VALUES (400, N'complete '), (401, N'PENDNG')) AS v (id, s) ON o.order_id = v.id;

-- 6 header totals that do not match their lines
UPDATE raw_sales.orders SET order_total = order_total + 10
WHERE order_id BETWEEN 500 AND 505;

-- 4 zero or negative quantities
UPDATE i SET i.quantity = v.q
FROM raw_sales.order_items AS i
INNER JOIN (VALUES (600, 0), (601, -1), (602, -2), (603, 0)) AS v (id, q)
    ON i.order_id = v.id AND i.line_no = 1;

-- 3 prices out of range
UPDATE i SET i.unit_price = v.p
FROM raw_sales.order_items AS i
INNER JOIN (VALUES (700, 0.00), (701, 99999.00), (702, -15.00)) AS v (id, p)
    ON i.order_id = v.id AND i.line_no = 1;

-- Keep headers 600-702 consistent with their (now wrong) lines, so the
-- reconciliation rule reports only orders 500-505.
UPDATE o SET o.order_total = s.total
FROM raw_sales.orders AS o
INNER JOIN (SELECT order_id, SUM(quantity * unit_price) AS total
            FROM raw_sales.order_items WHERE order_id BETWEEN 600 AND 702 GROUP BY order_id) AS s
    ON o.order_id = s.order_id;

-- 2 products without a category
UPDATE raw_sales.products SET category = NULL WHERE product_id IN (13, 57);

SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM raw_sales.customers
UNION ALL SELECT 'products',    COUNT(*) FROM raw_sales.products
UNION ALL SELECT 'orders',      COUNT(*) FROM raw_sales.orders
UNION ALL SELECT 'order_items', COUNT(*) FROM raw_sales.order_items;
GO
