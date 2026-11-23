/* =============================================================================
   03_register_scenarios.sql
   Seven common performance problems: the slow query, the tuned query, why
   the first is slow, and what the fix is.
============================================================================= */

USE QueryTuning;
GO

DELETE FROM perf.scenario;

INSERT INTO perf.scenario (scenario_code, title, problem, fix, slow_sql, tuned_sql, expected_index)
VALUES
-- -----------------------------------------------------------------------------
('S1_NON_SARGABLE_DATE',
 N'Daily revenue for June 2024',
 N'YEAR(order_ts) and MONTH(order_ts) hide the column inside functions, so no index can be searched. SQL Server computes both functions for all 2 million rows.',
 N'Ask for a range on the raw column (>= 1 June AND < 1 July) and add an index on order_ts. A predicate an index can search is called SARGable.',
 N'SELECT CAST(order_ts AS DATE) AS order_day, COUNT(*) AS orders, SUM(amount) AS revenue
   FROM perf.orders
   WHERE YEAR(order_ts) = 2024 AND MONTH(order_ts) = 6
   GROUP BY CAST(order_ts AS DATE)',
 N'SELECT CAST(order_ts AS DATE) AS order_day, COUNT(*) AS orders, SUM(amount) AS revenue
   FROM perf.orders
   WHERE order_ts >= ''2024-06-01'' AND order_ts < ''2024-07-01''
   GROUP BY CAST(order_ts AS DATE)',
 'ix_orders_ts_cover'),
-- -----------------------------------------------------------------------------
('S2_CUSTOMER_HISTORY',
 N'Last 10 orders of one customer (the "My orders" screen)',
 N'No index on customer_id, so every request scans 2 million rows to find about 10, then sorts them.',
 N'Composite index (customer_id, order_ts DESC) INCLUDE (status, amount). Equality column first, then the sort column in sort order; INCLUDE makes it covering, so there are no key lookups and no sort.',
 N'SELECT TOP (10) order_id, order_ts, status, amount
   FROM perf.orders WHERE customer_id = 4242 ORDER BY order_ts DESC',
 N'SELECT TOP (10) order_id, order_ts, status, amount
   FROM perf.orders WHERE customer_id = 4242 ORDER BY order_ts DESC',
 'ix_orders_customer_ts'),
-- -----------------------------------------------------------------------------
('S3_COVERING_INDEX',
 N'Value of returned orders in March 2024',
 N'Without an index the whole table is read. With a plain index on order_ts, every match still needs a key lookup to fetch status and amount.',
 N'Covering index: key order_ts, INCLUDE (status, amount). Everything the query needs is in the index, so the base table is never touched.',
 N'SELECT COUNT(*) AS returns, SUM(amount) AS returned_value
   FROM perf.orders
   WHERE status = ''RETURNED'' AND order_ts >= ''2024-03-01'' AND order_ts < ''2024-04-01''',
 N'SELECT COUNT(*) AS returns, SUM(amount) AS returned_value
   FROM perf.orders
   WHERE status = ''RETURNED'' AND order_ts >= ''2024-03-01'' AND order_ts < ''2024-04-01''',
 'ix_orders_ts_cover'),
-- -----------------------------------------------------------------------------
('S4_PENDING_QUEUE',
 N'Oldest 50 pending orders (a work queue)',
 N'Only 0.5% of orders are PENDING, but the whole table is scanned and sorted. A normal index on status would be large and mostly useless.',
 N'Filtered index ON (order_ts) INCLUDE (customer_id) WHERE status = ''PENDING''. It holds only the 10,000 pending rows.',
 N'SELECT TOP (50) order_id, customer_id, order_ts
   FROM perf.orders WHERE status = ''PENDING'' ORDER BY order_ts',
 N'SELECT TOP (50) order_id, customer_id, order_ts
   FROM perf.orders WHERE status = ''PENDING'' ORDER BY order_ts',
 'ix_orders_pending'),
-- -----------------------------------------------------------------------------
('S5_CASE_INSENSITIVE_EMAIL',
 N'Login: find a customer by email, ignoring case',
 N'LOWER(email) = ... wraps the column in a function, so an index on email cannot be searched. It is also unnecessary: the database uses a case-insensitive collation, so = already ignores case.',
 N'Drop LOWER() and compare the column directly, with an index on email.',
 N'SELECT customer_id, full_name FROM perf.customers WHERE LOWER(email) = ''customer123456@example.co.za''',
 N'SELECT customer_id, full_name FROM perf.customers WHERE email = ''customer123456@example.co.za''',
 'ix_customers_email'),
-- -----------------------------------------------------------------------------
('S6_DEEP_PAGINATION',
 N'Page 30,001 of the order list (50 rows per page)',
 N'OFFSET 1,500,000 still reads 1.5 million rows and throws them away. Page 30,001 costs 30,000 times more than page 1.',
 N'Keyset (seek) pagination: remember the last order_id of the previous page and ask for order_id > that value. The primary key jumps straight there. (order_ids are contiguous here, so last id 1,500,000 returns the same page.)',
 N'SELECT order_id, order_ts, amount FROM perf.orders ORDER BY order_id OFFSET 1500000 ROWS FETCH NEXT 50 ROWS ONLY',
 N'SELECT TOP (50) order_id, order_ts, amount FROM perf.orders WHERE order_id > 1500000 ORDER BY order_id',
 'pk_orders'),
-- -----------------------------------------------------------------------------
('S7_PARTITION_ELIMINATION',
 N'Channel revenue for November 2024',
 N'The table holds two years of orders; a one-month report reads all of them.',
 N'Partition the table by month on order_ts. SQL Server sees the date range and reads only the November partition (partition elimination).',
 N'SELECT channel, COUNT(*) AS orders, SUM(amount) AS revenue
   FROM perf.orders
   WHERE order_ts >= ''2024-11-01'' AND order_ts < ''2024-12-01''
   GROUP BY channel',
 N'SELECT channel, COUNT(*) AS orders, SUM(amount) AS revenue
   FROM perf.orders_partitioned
   WHERE order_ts >= ''2024-11-01'' AND order_ts < ''2024-12-01''
   GROUP BY channel',
 NULL);

SELECT scenario_code, title FROM perf.scenario ORDER BY scenario_code;
GO
