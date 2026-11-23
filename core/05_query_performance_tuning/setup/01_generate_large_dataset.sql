/* =============================================================================
   01_generate_large_dataset.sql
   Creates the QueryTuning database: 200,000 customers and 2,000,000 orders
   (roughly 300 MB). Takes 20-60 seconds depending on the machine.

   Only primary keys exist at this point. The baseline benchmark measures
   this untuned state first.

   The data is synthetic. "Random" values come from a multiplicative hash of
   the row number, so every run produces exactly the same rows.
============================================================================= */

IF DB_ID(N'QueryTuning') IS NULL
    CREATE DATABASE QueryTuning;
GO

ALTER DATABASE QueryTuning SET RECOVERY SIMPLE;   -- bulk inserts log less
GO

USE QueryTuning;
GO

IF SCHEMA_ID(N'perf') IS NULL EXEC (N'CREATE SCHEMA perf AUTHORIZATION dbo;');
GO

SET NOCOUNT ON;

DROP TABLE IF EXISTS perf.orders_partitioned;
IF EXISTS (SELECT 1 FROM sys.partition_schemes WHERE name = N'ps_orders_month') DROP PARTITION SCHEME ps_orders_month;
IF EXISTS (SELECT 1 FROM sys.partition_functions WHERE name = N'pf_orders_month') DROP PARTITION FUNCTION pf_orders_month;
DROP TABLE IF EXISTS perf.orders;
DROP TABLE IF EXISTS perf.customers;
GO

CREATE TABLE perf.customers (
    customer_id   INT           NOT NULL,
    email         VARCHAR(100)  NOT NULL,     -- stored in mixed case on purpose
    full_name     VARCHAR(100)  NOT NULL,
    region        VARCHAR(30)   NOT NULL,
    created_at    DATETIME2(0)  NOT NULL,
    CONSTRAINT pk_customers PRIMARY KEY CLUSTERED (customer_id)
);

CREATE TABLE perf.orders (
    order_id      BIGINT         NOT NULL,
    customer_id   INT            NOT NULL,
    order_ts      DATETIME2(0)   NOT NULL,
    status        VARCHAR(10)    NOT NULL,
    channel       VARCHAR(12)    NOT NULL,
    amount        DECIMAL(10, 2) NOT NULL,
    notes         CHAR(60)       NOT NULL,   -- padding: makes rows a realistic width
    CONSTRAINT pk_orders PRIMARY KEY CLUSTERED (order_id),
    CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES perf.customers (customer_id)
);
GO

-- Numbers 1 .. 2,000,000 from a cross join of small sets (no loops)
WITH d AS (SELECT n FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9)) AS v (n)),
     nums AS (
        SELECT d1.n + 10 * d2.n + 100 * d3.n + 1000 * d4.n + 10000 * d5.n + 100000 * d6.n + 1000000 * d7.n + 1 AS n
        FROM d AS d1 CROSS JOIN d AS d2 CROSS JOIN d AS d3 CROSS JOIN d AS d4
        CROSS JOIN d AS d5 CROSS JOIN d AS d6 CROSS JOIN d AS d7
     )
SELECT n INTO #n FROM nums WHERE n <= 2000000;

CREATE UNIQUE CLUSTERED INDEX cx_n ON #n (n);

INSERT INTO perf.customers WITH (TABLOCK)
SELECT n,
       CASE WHEN n % 2 = 0 THEN CONCAT('Customer', n, '@Example.co.za')
                           ELSE CONCAT('customer', n, '@example.co.za') END,
       CONCAT('Customer ', n),
       CHOOSE(n % 5 + 1, 'Gauteng', 'Western Cape', 'KwaZulu-Natal', 'Eastern Cape', 'Free State'),
       DATEADD(DAY, n % 1400, '2020-01-01')
FROM #n
WHERE n <= 200000;

-- h1..h4 are four independent pseudo-random numbers in [0, 1) per row.
-- Status is skewed like real life: 90% delivered, 0.5% pending.
INSERT INTO perf.orders WITH (TABLOCK)
SELECT n,
       1 + CAST(h1 * 200000 AS INT),
       DATEADD(SECOND, CAST(h2 * 730 * 86400 AS INT), '2023-01-01'),
       CASE WHEN h3 < 0.900 THEN 'DELIVERED'
            WHEN h3 < 0.960 THEN 'RETURNED'
            WHEN h3 < 0.995 THEN 'CANCELLED'
            ELSE 'PENDING' END,
       CHOOSE(CAST(h4 * 4 AS INT) + 1, 'WEB', 'APP', 'STORE', 'CALL_CENTRE'),
       CAST(20 + h1 * 4980 AS DECIMAL(10, 2)),
       REPLICATE('x', 60)
FROM #n
CROSS APPLY (SELECT
    ((n * 2654435761) % 4294967296) / 4294967296.0                AS h1,
    (((n + 7)  * 2246822519) % 4294967296) / 4294967296.0        AS h2,
    (((n + 13) * 3266489917) % 4294967296) / 4294967296.0        AS h3,
    (((n + 29) * 668265263)  % 4294967296) / 4294967296.0        AS h4
) AS h;

DROP TABLE #n;

-- Fresh statistics so the optimiser makes informed choices
UPDATE STATISTICS perf.customers WITH FULLSCAN;
UPDATE STATISTICS perf.orders    WITH FULLSCAN;

SELECT 'customers' AS table_name, COUNT_BIG(*) AS row_count FROM perf.customers
UNION ALL
SELECT 'orders', COUNT_BIG(*) FROM perf.orders;

EXEC sys.sp_spaceused N'perf.orders';
GO
