/* =============================================================================
   06_partition_orders.sql
   Monthly range partitioning (available in every edition, including Express,
   since SQL Server 2016 SP1).

   Partitioning helps when queries almost always filter on the partition key
   and old periods are archived or removed. Switching out or truncating a
   month is instant; deleting 80,000 rows is slow and logs every row.
   On small tables it adds complexity for little gain, so measure first.

   Building blocks
     partition function  where the boundaries are (1st of every month)
     partition scheme    which filegroup each partition lives on (all PRIMARY here)
     table               created ON the scheme, partitioned by order_ts
============================================================================= */

USE QueryTuning;
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS perf.orders_partitioned;
IF EXISTS (SELECT 1 FROM sys.partition_schemes   WHERE name = N'ps_orders_month') DROP PARTITION SCHEME ps_orders_month;
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'pf_orders_month') DROP PARTITION FUNCTION pf_orders_month;
GO

-- Build the 24 monthly boundaries with dynamic SQL instead of typing them
DECLARE @boundaries NVARCHAR(MAX), @sql NVARCHAR(MAX);

WITH months AS (
    SELECT TOP (24) DATEADD(MONTH, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1, CAST('2023-01-01' AS DATE)) AS month_start
    FROM sys.all_objects
)
SELECT @boundaries = STRING_AGG(QUOTENAME(CONVERT(CHAR(10), month_start, 23), ''''), ', ')
                     WITHIN GROUP (ORDER BY month_start)
FROM months;

-- RANGE RIGHT: each boundary date belongs to the partition on its right,
-- so 2024-11-01 00:00:00 is the first moment of the November partition.
SET @sql = N'CREATE PARTITION FUNCTION pf_orders_month (DATETIME2(0)) AS RANGE RIGHT FOR VALUES (' + @boundaries + N');';
EXEC sys.sp_executesql @sql;
GO

CREATE PARTITION SCHEME ps_orders_month
    AS PARTITION pf_orders_month ALL TO ([PRIMARY]);
GO

-- The partitioning column must be part of the clustered key
CREATE TABLE perf.orders_partitioned (
    order_id      BIGINT         NOT NULL,
    customer_id   INT            NOT NULL,
    order_ts      DATETIME2(0)   NOT NULL,
    status        VARCHAR(10)    NOT NULL,
    channel       VARCHAR(12)    NOT NULL,
    amount        DECIMAL(10, 2) NOT NULL,
    notes         CHAR(60)       NOT NULL,
    CONSTRAINT pk_orders_partitioned PRIMARY KEY CLUSTERED (order_ts, order_id)
) ON ps_orders_month (order_ts);
GO

INSERT INTO perf.orders_partitioned WITH (TABLOCK)
SELECT order_id, customer_id, order_ts, status, channel, amount, notes
FROM perf.orders;

UPDATE STATISTICS perf.orders_partitioned WITH FULLSCAN;

-- Rows per partition, with the date each partition starts at
SELECT p.partition_number,
       CAST(rv.value AS DATETIME2(0)) AS starts_at,
       p.rows
FROM sys.partitions AS p
INNER JOIN sys.indexes AS i
    ON i.object_id = p.object_id AND i.index_id = p.index_id
INNER JOIN sys.partition_schemes AS ps
    ON ps.data_space_id = i.data_space_id
LEFT JOIN sys.partition_range_values AS rv
    ON rv.function_id = ps.function_id
   AND rv.boundary_id = p.partition_number - 1      -- RANGE RIGHT: lower boundary
WHERE p.object_id = OBJECT_ID(N'perf.orders_partitioned')
  AND p.index_id = 1
ORDER BY p.partition_number;
GO
