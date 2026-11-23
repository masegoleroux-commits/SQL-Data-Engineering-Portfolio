/* =============================================================================
   03_generate_monthly_snapshots.sql
   Four monthly CRM extracts with a known set of changes, so the tests can
   check exact numbers. The data is synthetic and generated with simple
   arithmetic on the customer id, so it is identical on every run.

   Batch        What changes                                     Expected effect
   ----------   ----------------------------------------------   ----------------------
   2024-01-01   300 customers                                    300 new rows (version 1)
   2024-02-01   id % 17 = 0  moved city                          new Type 2 versions
                id % 11 = 0  loyalty tier upgraded               new Type 2 versions
                id % 13 = 0  email corrected                     Type 1 overwrite only
                id % 50 = 0  missing from the extract (6)        closing "deleted" version
                ids 301-325  new customers                       new rows
   2024-03-01   id % 11 = 0  tier upgraded again                 new Type 2 versions
                id 50        comes back                          re-activated
                id % 7 = 0   city sent as ' cape town ' etc.     NO change (cleaned before hashing)
                ids 326-335  new customers                       new rows
   2024-04-01   identical to March                               zero changes
============================================================================= */

USE CustomerHistory;
GO

SET NOCOUNT ON;

TRUNCATE TABLE dbo.src_customer_snapshot;

DROP TABLE IF EXISTS #city;
CREATE TABLE #city (city_no INT PRIMARY KEY, city NVARCHAR(80), province NVARCHAR(50));
INSERT INTO #city VALUES
    (0, N'Johannesburg', N'Gauteng'),      (1, N'Pretoria', N'Gauteng'),
    (2, N'Cape Town', N'Western Cape'),    (3, N'Durban', N'Kwazulu-Natal'),
    (4, N'Gqeberha', N'Eastern Cape'),     (5, N'Bloemfontein', N'Free State'),
    (6, N'Polokwane', N'Limpopo'),         (7, N'Mbombela', N'Mpumalanga');

-- Numbers 1..400 to generate rows from
DROP TABLE IF EXISTS #n;
SELECT TOP (400) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
INTO #n
FROM sys.all_objects;

/* ---- Batch 1: 2024-01-01 ------------------------------------------------ */
INSERT INTO dbo.src_customer_snapshot
SELECT '2024-01-01',
       n.n,
       CONCAT(CHOOSE(n.n % 8 + 1, N'Thabo', N'Lerato', N'Sipho', N'Naledi', N'Johan', N'Aisha', N'Pieter', N'Zanele'),
              N' ',
              CHOOSE(n.n % 7 + 1, N'Nkosi', N'Dlamini', N'Botha', N'Naidoo', N'Mokoena', N'Smith', N'Khumalo')),
       CONCAT(N'cust', n.n, N'@mail.co.za'),
       DATEADD(DAY, n.n * 37 % 12000, '1970-01-01'),
       c.city, c.province,
       CHOOSE(n.n % 3 + 1, N'BRONZE', N'SILVER', N'GOLD')
FROM #n AS n
INNER JOIN #city AS c ON c.city_no = n.n % 8
WHERE n.n <= 300;

/* ---- Batch 2: 2024-02-01 ------------------------------------------------ */
INSERT INTO dbo.src_customer_snapshot
SELECT '2024-02-01',
       s.customer_id,
       s.full_name,
       CASE WHEN s.customer_id % 13 = 0 THEN CONCAT(N'c.', s.customer_id, N'@newmail.co.za') ELSE s.email END,
       s.date_of_birth,
       CASE WHEN s.customer_id % 17 = 0 THEN nc.city     ELSE s.city     END,
       CASE WHEN s.customer_id % 17 = 0 THEN nc.province ELSE s.province END,
       CASE WHEN s.customer_id % 11 = 0
            THEN CASE s.loyalty_tier WHEN N'BRONZE' THEN N'SILVER' WHEN N'SILVER' THEN N'GOLD' ELSE N'PLATINUM' END
            ELSE s.loyalty_tier END
FROM dbo.src_customer_snapshot AS s
INNER JOIN #city AS nc ON nc.city_no = (s.customer_id + 3) % 8      -- a different city
WHERE s.batch_date = '2024-01-01'
  AND s.customer_id % 50 <> 0;                                      -- six customers dropped

INSERT INTO dbo.src_customer_snapshot
SELECT '2024-02-01', n.n, CONCAT(N'New Customer ', n.n), CONCAT(N'cust', n.n, N'@mail.co.za'),
       DATEADD(DAY, n.n, '1990-01-01'), c.city, c.province, N'BRONZE'
FROM #n AS n
INNER JOIN #city AS c ON c.city_no = n.n % 8
WHERE n.n BETWEEN 301 AND 325;

/* ---- Batch 3: 2024-03-01 ------------------------------------------------ */
INSERT INTO dbo.src_customer_snapshot
SELECT '2024-03-01',
       s.customer_id,
       s.full_name,
       s.email,
       s.date_of_birth,
       -- messy formatting from the source system: must NOT count as a change
       CASE WHEN s.customer_id % 7 = 0 THEN CONCAT(N'  ', LOWER(s.city), N' ') ELSE s.city END,
       s.province,
       CASE WHEN s.customer_id % 11 = 0
            THEN CASE s.loyalty_tier WHEN N'BRONZE' THEN N'SILVER' WHEN N'SILVER' THEN N'GOLD' ELSE N'PLATINUM' END
            ELSE s.loyalty_tier END
FROM dbo.src_customer_snapshot AS s
WHERE s.batch_date = '2024-02-01';

-- customer 50 returns with the details they had in January
INSERT INTO dbo.src_customer_snapshot
SELECT '2024-03-01', customer_id, full_name, email, date_of_birth, city, province, loyalty_tier
FROM dbo.src_customer_snapshot
WHERE batch_date = '2024-01-01' AND customer_id = 50;

INSERT INTO dbo.src_customer_snapshot
SELECT '2024-03-01', n.n, CONCAT(N'New Customer ', n.n), CONCAT(N'cust', n.n, N'@mail.co.za'),
       DATEADD(DAY, n.n, '1990-01-01'), c.city, c.province, N'BRONZE'
FROM #n AS n
INNER JOIN #city AS c ON c.city_no = n.n % 8
WHERE n.n BETWEEN 326 AND 335;

/* ---- Batch 4: 2024-04-01 (no changes) ----------------------------------- */
INSERT INTO dbo.src_customer_snapshot
SELECT '2024-04-01', customer_id, full_name, email, date_of_birth, city, province, loyalty_tier
FROM dbo.src_customer_snapshot
WHERE batch_date = '2024-03-01';

/* ---- Orders: January - April 2024 --------------------------------------- */
-- Only customers in that month's extract place orders.
DELETE FROM dbo.fact_orders;

INSERT INTO dbo.fact_orders (order_id, order_date, customer_id, order_amount)
SELECT ROW_NUMBER() OVER (ORDER BY s.batch_date, s.customer_id, k.k),
       DATEADD(DAY, (s.customer_id * 7 + k.k * 5) % 28, s.batch_date),
       s.customer_id,
       150 + (s.customer_id * 31 + k.k * 97) % 1850
FROM dbo.src_customer_snapshot AS s
CROSS JOIN (VALUES (1), (2)) AS k (k)
WHERE (s.customer_id + k.k) % 3 <> 0;         -- not every customer orders every month

SELECT batch_date, COUNT(*) AS customers
FROM dbo.src_customer_snapshot
GROUP BY batch_date
ORDER BY batch_date;
GO
