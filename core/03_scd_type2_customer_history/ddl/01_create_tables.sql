/* =============================================================================
   01_create_tables.sql
   Database and tables for a Type 2 slowly changing customer dimension.

   How each attribute is handled is a business decision, so it is stored as
   data in dbo.scd_column_policy rather than only in a comment:
     Type 0  never changes          customer_id, date_of_birth
     Type 1  overwrite, no history  full_name, email   (corrections)
     Type 2  new version per change city, province, loyalty_tier
============================================================================= */

IF DB_ID(N'CustomerHistory') IS NULL
    CREATE DATABASE CustomerHistory;
GO

USE CustomerHistory;
GO

DROP TABLE IF EXISTS dbo.fact_orders;
DROP TABLE IF EXISTS dbo.dim_customer;
DROP TABLE IF EXISTS dbo.stg_customer;
DROP TABLE IF EXISTS dbo.src_customer_snapshot;
DROP TABLE IF EXISTS dbo.load_audit;
DROP TABLE IF EXISTS dbo.scd_column_policy;
GO

/* ---- Business rules: which columns keep history ------------------------- */
CREATE TABLE dbo.scd_column_policy (
    column_name     SYSNAME        NOT NULL,
    scd_type        TINYINT        NOT NULL,
    reason          NVARCHAR(200)  NOT NULL,
    CONSTRAINT pk_scd_column_policy PRIMARY KEY (column_name),
    CONSTRAINT ck_scd_column_policy_type CHECK (scd_type IN (0, 1, 2))
);

INSERT INTO dbo.scd_column_policy VALUES
    ('customer_id',   0, N'Business key. Never changes.'),
    ('date_of_birth', 0, N'Fixed fact about the person.'),
    ('full_name',     1, N'Changes are corrections. Reports should show the latest spelling.'),
    ('email',         1, N'Contact detail. Only the current value is useful.'),
    ('city',          2, N'Sales must be reported by where the customer lived at the time.'),
    ('province',      2, N'Follows city.'),
    ('loyalty_tier',  2, N'Revenue by tier must use the tier at the time of the order.');

/* ---- Landing: one full CRM extract per month ---------------------------- */
CREATE TABLE dbo.src_customer_snapshot (
    batch_date      DATE           NOT NULL,
    customer_id     INT            NOT NULL,
    full_name       NVARCHAR(120)  NOT NULL,
    email           NVARCHAR(120)  NULL,
    date_of_birth   DATE           NULL,
    city            NVARCHAR(80)   NOT NULL,
    province        NVARCHAR(50)   NOT NULL,
    loyalty_tier    NVARCHAR(10)   NOT NULL,
    CONSTRAINT pk_src_customer_snapshot PRIMARY KEY (batch_date, customer_id)
);

/* ---- Staging: the batch being processed, cleaned and hashed ------------- */
CREATE TABLE dbo.stg_customer (
    customer_id     INT            NOT NULL,
    full_name       NVARCHAR(120)  NOT NULL,
    email           NVARCHAR(120)  NULL,
    date_of_birth   DATE           NULL,
    city            NVARCHAR(80)   NOT NULL,
    province        NVARCHAR(50)   NOT NULL,
    loyalty_tier    NVARCHAR(10)   NOT NULL,
    type2_hash      BINARY(16)     NOT NULL,   -- MD5 of the cleaned Type 2 columns
    CONSTRAINT pk_stg_customer PRIMARY KEY (customer_id)
);

/* ---- The Type 2 dimension ----------------------------------------------- */
CREATE TABLE dbo.dim_customer (
    customer_sk     INT IDENTITY(1, 1) NOT NULL,   -- surrogate key, one per version
    customer_id     INT            NOT NULL,       -- business key, repeats across versions
    full_name       NVARCHAR(120)  NOT NULL,
    email           NVARCHAR(120)  NULL,
    date_of_birth   DATE           NULL,
    city            NVARCHAR(80)   NOT NULL,
    province        NVARCHAR(50)   NOT NULL,
    loyalty_tier    NVARCHAR(10)   NOT NULL,
    type2_hash      BINARY(16)     NOT NULL,
    valid_from      DATE           NOT NULL,
    valid_to        DATE           NOT NULL CONSTRAINT df_dim_customer_valid_to DEFAULT ('9999-12-31'),
    is_current      BIT            NOT NULL CONSTRAINT df_dim_customer_is_current DEFAULT (1),
    is_deleted      BIT            NOT NULL CONSTRAINT df_dim_customer_is_deleted DEFAULT (0),
    version_number  SMALLINT       NOT NULL,
    CONSTRAINT pk_dim_customer PRIMARY KEY (customer_sk),
    CONSTRAINT uq_dim_customer_version UNIQUE (customer_id, version_number),
    CONSTRAINT ck_dim_customer_range CHECK (valid_to >= valid_from),
    CONSTRAINT ck_dim_customer_current CHECK ((is_current = 1 AND valid_to = '9999-12-31')
                                           OR (is_current = 0 AND valid_to < '9999-12-31'))
);

-- At most one current row per customer, enforced by the database.
-- A filtered index only contains the rows that match its WHERE clause.
CREATE UNIQUE NONCLUSTERED INDEX ux_dim_customer_current
    ON dbo.dim_customer (customer_id)
    WHERE is_current = 1;

-- Point-in-time lookups: "which version was valid on this date?"
CREATE NONCLUSTERED INDEX ix_dim_customer_validity
    ON dbo.dim_customer (customer_id, valid_from, valid_to)
    INCLUDE (loyalty_tier, city);

/* ---- One row per batch processed ---------------------------------------- */
CREATE TABLE dbo.load_audit (
    batch_date      DATE          NOT NULL,
    source_rows     INT           NOT NULL,
    new_customers   INT           NOT NULL,
    new_versions    INT           NOT NULL,
    type1_updates   INT           NOT NULL,
    deletions       INT           NOT NULL,
    unchanged       INT           NOT NULL,
    loaded_at       DATETIME2(0)  NOT NULL CONSTRAINT df_load_audit_at DEFAULT SYSDATETIME(),
    CONSTRAINT pk_load_audit PRIMARY KEY (batch_date)
);

/* ---- Orders, to show why history matters -------------------------------- */
CREATE TABLE dbo.fact_orders (
    order_id        INT            NOT NULL,
    order_date      DATE           NOT NULL,
    customer_id     INT            NOT NULL,    -- business key from the order system
    customer_sk     INT            NULL,        -- version valid on order_date (filled by the load)
    order_amount    DECIMAL(10, 2) NOT NULL,
    CONSTRAINT pk_fact_orders PRIMARY KEY (order_id),
    CONSTRAINT fk_fact_orders_customer FOREIGN KEY (customer_sk) REFERENCES dbo.dim_customer (customer_sk)
);
GO
