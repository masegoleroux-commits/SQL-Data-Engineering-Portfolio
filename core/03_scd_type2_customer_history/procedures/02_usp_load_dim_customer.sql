/* =============================================================================
   02_usp_load_dim_customer.sql
   dbo.usp_load_dim_customer @batch_date  loads one monthly snapshot.

   Steps (all inside one transaction: a failure leaves nothing half-loaded)
     0  Guard rails   reject an empty batch or one older than the last load
     1  Stage         clean the values and hash the Type 2 columns
     2  Profile       count new / changed / unchanged / Type 1 before changing anything
     3  Type 1        overwrite name and email on every version of the customer
     4  Type 2        MERGE: insert new customers and close changed versions.
                      OUTPUT $action records which customers were closed,
                      then a second INSERT adds their new versions. Doing
                      it in two statements keeps the "one current row"
                      index happy: the old row is closed before the new
                      one arrives.
     5  Deletions     customers missing from the snapshot get a closing
                      version flagged is_deleted
     6  Audit         one row in dbo.load_audit

   dbo.usp_resolve_order_keys gives every order the customer version that
   was valid on the order date.
============================================================================= */

USE CustomerHistory;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

-- Proper case: 'cape town' -> 'Cape Town', 'kwazulu-natal' -> 'Kwazulu-Natal'.
-- Upper-cases the first letter and every letter after a space or hyphen.
CREATE OR ALTER FUNCTION dbo.fn_proper_case (@text NVARCHAR(200))
RETURNS NVARCHAR(200)
WITH SCHEMABINDING
AS
BEGIN
    IF @text IS NULL RETURN NULL;

    DECLARE @out NVARCHAR(200) = LOWER(@text),
            @i   INT = 1;

    WHILE @i <= LEN(@out)
    BEGIN
        IF @i = 1 OR SUBSTRING(@out, @i - 1, 1) IN (N' ', N'-')
            SET @out = STUFF(@out, @i, 1, UPPER(SUBSTRING(@out, @i, 1)));
        SET @i += 1;
    END;

    RETURN @out;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_load_dim_customer
    @batch_date DATE
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @last_batch DATE = (SELECT MAX(batch_date) FROM dbo.load_audit),
            @source_rows INT, @new INT, @changed INT, @unchanged INT, @type1 INT, @deleted INT;

    /* 0. Guard rails ----------------------------------------------------- */
    IF @last_batch IS NOT NULL AND @batch_date <= @last_batch
    BEGIN
        DECLARE @msg NVARCHAR(200) = CONCAT(N'Batch ', @batch_date, N' rejected: batches must be loaded in date order (last loaded ', @last_batch, N').');
        THROW 50010, @msg, 1;
    END;

    SELECT @source_rows = COUNT(*) FROM dbo.src_customer_snapshot WHERE batch_date = @batch_date;
    IF @source_rows = 0
        THROW 50011, N'Batch has no rows. Refusing to load: every customer would be marked deleted.', 1;

    BEGIN TRANSACTION;

    /* 1. Stage: clean, then hash. A separator stops ('AB','C') and ('A','BC')
          hashing the same; '~' stands in for NULL. ----------------------- */
    TRUNCATE TABLE dbo.stg_customer;

    INSERT INTO dbo.stg_customer (customer_id, full_name, email, date_of_birth, city, province, loyalty_tier, type2_hash)
    SELECT c.customer_id, c.full_name, c.email, c.date_of_birth, c.city, c.province, c.loyalty_tier,
           HASHBYTES('MD5', CONCAT(COALESCE(c.city, N'~'), N'|', COALESCE(c.province, N'~'), N'|', COALESCE(c.loyalty_tier, N'~')))
    FROM dbo.src_customer_snapshot AS s
    CROSS APPLY (
        SELECT s.customer_id,
               LTRIM(RTRIM(s.full_name))                                  AS full_name,
               LOWER(LTRIM(RTRIM(s.email)))                               AS email,
               s.date_of_birth,
               -- 'cape town' -> 'Cape Town' (first letter of each word upper case)
               dbo.fn_proper_case(LTRIM(RTRIM(s.city)))                   AS city,
               dbo.fn_proper_case(LTRIM(RTRIM(s.province)))               AS province,
               UPPER(LTRIM(RTRIM(s.loyalty_tier)))                        AS loyalty_tier
    ) AS c
    WHERE s.batch_date = @batch_date;

    /* 2. Profile against the current dimension ---------------------------- */
    SELECT @new       = SUM(x.is_new),
           @changed   = SUM(x.is_changed),
           @unchanged = SUM(x.is_unchanged),
           @type1     = SUM(x.is_type1)
    FROM (
        SELECT CASE WHEN d.customer_id IS NULL THEN 1 ELSE 0 END AS is_new,
               CASE WHEN d.customer_id IS NOT NULL AND (d.type2_hash <> s.type2_hash OR d.is_deleted = 1) THEN 1 ELSE 0 END AS is_changed,
               CASE WHEN d.customer_id IS NOT NULL AND d.type2_hash = s.type2_hash AND d.is_deleted = 0 THEN 1 ELSE 0 END AS is_unchanged,
               -- EXCEPT treats two NULLs as equal, so this is a NULL-safe "did it change?"
               CASE WHEN d.customer_id IS NOT NULL
                     AND EXISTS (SELECT d.full_name, d.email EXCEPT SELECT s.full_name, s.email)
                    THEN 1 ELSE 0 END AS is_type1
        FROM dbo.stg_customer AS s
        LEFT JOIN dbo.dim_customer AS d
            ON d.customer_id = s.customer_id AND d.is_current = 1
    ) AS x;

    /* 3. Type 1: corrections overwrite every version ---------------------- */
    UPDATE d
    SET    d.full_name = s.full_name,
           d.email     = s.email
    FROM dbo.dim_customer AS d
    INNER JOIN dbo.stg_customer AS s ON s.customer_id = d.customer_id
    WHERE EXISTS (SELECT d.full_name, d.email EXCEPT SELECT s.full_name, s.email);

    /* 4. Type 2 ----------------------------------------------------------- */
    DECLARE @changes TABLE (merge_action NVARCHAR(10), customer_id INT, old_version SMALLINT);

    MERGE dbo.dim_customer AS t
    USING dbo.stg_customer AS s
        ON  t.customer_id = s.customer_id
        AND t.is_current  = 1
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (customer_id, full_name, email, date_of_birth, city, province, loyalty_tier,
                type2_hash, valid_from, version_number)
        VALUES (s.customer_id, s.full_name, s.email, s.date_of_birth, s.city, s.province, s.loyalty_tier,
                s.type2_hash, @batch_date, 1)
    WHEN MATCHED AND (t.type2_hash <> s.type2_hash OR t.is_deleted = 1) THEN
        UPDATE SET t.valid_to   = DATEADD(DAY, -1, @batch_date),
                   t.is_current = 0
    OUTPUT $action, inserted.customer_id, deleted.version_number
        INTO @changes (merge_action, customer_id, old_version);

    INSERT INTO dbo.dim_customer
        (customer_id, full_name, email, date_of_birth, city, province, loyalty_tier,
         type2_hash, valid_from, version_number)
    SELECT s.customer_id, s.full_name, s.email, s.date_of_birth, s.city, s.province, s.loyalty_tier,
           s.type2_hash, @batch_date, c.old_version + 1
    FROM @changes AS c
    INNER JOIN dbo.stg_customer AS s ON s.customer_id = c.customer_id
    WHERE c.merge_action = N'UPDATE';

    /* 5. Deletions: close the current version, add a closing deleted version */
    DECLARE @gone TABLE (customer_id INT PRIMARY KEY);

    UPDATE d
    SET    d.valid_to   = DATEADD(DAY, -1, @batch_date),
           d.is_current = 0
    OUTPUT inserted.customer_id INTO @gone
    FROM dbo.dim_customer AS d
    WHERE d.is_current = 1
      AND d.is_deleted = 0
      AND NOT EXISTS (SELECT 1 FROM dbo.stg_customer AS s WHERE s.customer_id = d.customer_id);

    INSERT INTO dbo.dim_customer
        (customer_id, full_name, email, date_of_birth, city, province, loyalty_tier,
         type2_hash, valid_from, is_deleted, version_number)
    SELECT d.customer_id, d.full_name, d.email, d.date_of_birth, d.city, d.province, d.loyalty_tier,
           d.type2_hash, @batch_date, 1, d.version_number + 1
    FROM dbo.dim_customer AS d
    INNER JOIN @gone AS g ON g.customer_id = d.customer_id
    WHERE d.valid_to = DATEADD(DAY, -1, @batch_date);

    SET @deleted = @@ROWCOUNT;

    /* 6. Audit ------------------------------------------------------------ */
    INSERT INTO dbo.load_audit (batch_date, source_rows, new_customers, new_versions, type1_updates, deletions, unchanged)
    VALUES (@batch_date, @source_rows, @new, @changed, @type1, @deleted, @unchanged);

    COMMIT TRANSACTION;

    PRINT CONCAT('Batch ', @batch_date, ': ', @source_rows, ' rows | ', @new, ' new | ', @changed,
                 ' new versions | ', @type1, ' type 1 | ', @deleted, ' deleted | ', @unchanged, ' unchanged');
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_resolve_order_keys
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE f
    SET    f.customer_sk = d.customer_sk
    FROM dbo.fact_orders AS f
    INNER JOIN dbo.dim_customer AS d
        ON  d.customer_id = f.customer_id
        AND f.order_date BETWEEN d.valid_from AND d.valid_to
    WHERE f.customer_sk IS NULL OR f.customer_sk <> d.customer_sk;
END;
GO
