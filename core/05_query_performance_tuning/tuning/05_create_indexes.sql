/* =============================================================================
   05_create_indexes.sql
   One targeted index per measured problem. Every index costs disk space and
   slows every INSERT and UPDATE, so each one has to earn its place.

   On a live system, add WITH (ONLINE = ON) (Enterprise edition) or build
   indexes in a maintenance window so writers are not blocked.
============================================================================= */

USE QueryTuning;
GO

SET NOCOUNT ON;

-- S1 + S3: one covering index serves two queries.
--   key column order_ts        -> range searches ("June 2024")
--   INCLUDE status, amount     -> stored at the leaf level only; they cannot be
--                                 searched on but can be returned without a
--                                 key lookup into the table.
CREATE NONCLUSTERED INDEX ix_orders_ts_cover
    ON perf.orders (order_ts)
    INCLUDE (status, amount);

-- S2: equality column first, then the sort column in the order the query wants
CREATE NONCLUSTERED INDEX ix_orders_customer_ts
    ON perf.orders (customer_id, order_ts DESC)
    INCLUDE (status, amount);

-- S4: filtered index holding only the pending orders
CREATE NONCLUSTERED INDEX ix_orders_pending
    ON perf.orders (order_ts)
    INCLUDE (customer_id)
    WHERE status = 'PENDING';

-- S5: plain index on email (the fix is mainly the query rewrite)
CREATE NONCLUSTERED INDEX ix_customers_email
    ON perf.customers (email);

-- S6 needs no new index: the clustered primary key already exists.

-- What did the indexes cost in disk space?
SELECT i.name                                         AS index_name,
       OBJECT_NAME(i.object_id)                       AS table_name,
       SUM(ps.used_page_count) * 8 / 1024.0           AS size_mb,
       SUM(ps.row_count)                              AS index_rows
FROM sys.indexes AS i
INNER JOIN sys.dm_db_partition_stats AS ps
    ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE i.object_id IN (OBJECT_ID(N'perf.orders'), OBJECT_ID(N'perf.customers'))
GROUP BY i.name, i.object_id
ORDER BY size_mb DESC;
GO
