/* =============================================================================
   04_register_rules.sql
   The rule catalogue for raw_sales: 20 rules across six quality dimensions.
   Most come from the templates; the rest are custom SQL for checks a
   template cannot express (email format, reconciliation, freshness).
============================================================================= */

USE DataQuality;
GO

SET NOCOUNT ON;

/* ---- Completeness ------------------------------------------------------- */
-- Missing emails are tolerated up to 1% and only raise a warning
EXEC dq.usp_add_not_null_rule 'CUS_EMAIL_NOT_NULL',    'raw_sales', 'customers', 'email', 'WARN', 1.0;
EXEC dq.usp_add_not_null_rule 'CUS_NAME_NOT_NULL',     'raw_sales', 'customers', 'full_name';
EXEC dq.usp_add_not_null_rule 'PRD_CATEGORY_NOT_NULL', 'raw_sales', 'products',  'category';
EXEC dq.usp_add_not_null_rule 'ORD_DATE_NOT_NULL',     'raw_sales', 'orders',    'order_date';

/* ---- Uniqueness --------------------------------------------------------- */
EXEC dq.usp_add_unique_rule 'CUS_ID_UNIQUE', 'raw_sales', 'customers',   'customer_id';
EXEC dq.usp_add_unique_rule 'PRD_ID_UNIQUE', 'raw_sales', 'products',    'product_id';
EXEC dq.usp_add_unique_rule 'ORD_ID_UNIQUE', 'raw_sales', 'orders',      'order_id';
EXEC dq.usp_add_unique_rule 'ITM_PK_UNIQUE', 'raw_sales', 'order_items', 'order_id, line_no';

/* ---- Validity ----------------------------------------------------------- */
EXEC dq.usp_add_accepted_values_rule 'CUS_PROVINCE_VALID', 'raw_sales', 'customers', 'province',
     N'Gauteng|Western Cape|KwaZulu-Natal|Eastern Cape|Free State|Limpopo|Mpumalanga|North West|Northern Cape';

EXEC dq.usp_add_accepted_values_rule 'ORD_STATUS_VALID', 'raw_sales', 'orders', 'status',
     N'COMPLETE|SHIPPED|RETURNED|CANCELLED';

DECLARE @max_qty DECIMAL(18, 4)   = (SELECT setting_value FROM dq.setting WHERE setting_name = 'max_quantity'),
        @max_price DECIMAL(18, 4) = (SELECT setting_value FROM dq.setting WHERE setting_name = 'max_price');

EXEC dq.usp_add_range_rule 'ITM_QTY_POSITIVE', 'raw_sales', 'order_items', 'quantity',   1, @max_qty;
EXEC dq.usp_add_range_rule 'ITM_PRICE_RANGE',  'raw_sales', 'order_items', 'unit_price', 1, @max_price;

-- Email format. SQL Server 2019 has no regular expressions, so the rule
-- combines LIKE patterns: something@something.something, one @ only,
-- no spaces, no empty part between dots.
EXEC dq.usp_register_rule
    'CUS_EMAIL_FORMAT', 'Validity', N'[raw_sales].[customers]',
    N'email must look like name@domain.tld',
    N'SELECT customer_id, email FROM raw_sales.customers
      WHERE email IS NOT NULL
        AND (   email NOT LIKE ''%_@_%._%''
             OR email LIKE ''%@%@%''
             OR email LIKE ''% %''
             OR email LIKE ''%..%''
             OR email LIKE ''%@.%''
             OR email LIKE ''%.@%''
             OR email LIKE ''%.'')',
    N'SELECT COUNT(*) FROM raw_sales.customers WHERE email IS NOT NULL';

EXEC dq.usp_register_rule
    'ORD_DATE_NOT_FUTURE', 'Validity', N'[raw_sales].[orders]',
    N'order_date cannot be after today',
    N'SELECT order_id, order_date FROM raw_sales.orders WHERE order_date > CAST(SYSDATETIME() AS DATE)',
    N'SELECT COUNT(*) FROM raw_sales.orders';

/* ---- Integrity ---------------------------------------------------------- */
EXEC dq.usp_add_relationship_rule 'ORD_CUSTOMER_FK', 'raw_sales', 'orders',      'customer_id', 'raw_sales', 'customers', 'customer_id';
EXEC dq.usp_add_relationship_rule 'ITM_ORDER_FK',    'raw_sales', 'order_items', 'order_id',    'raw_sales', 'orders',    'order_id';
EXEC dq.usp_add_relationship_rule 'ITM_PRODUCT_FK',  'raw_sales', 'order_items', 'product_id',  'raw_sales', 'products',  'product_id';

/* ---- Consistency -------------------------------------------------------- */
EXEC dq.usp_register_rule
    'ORD_TOTAL_RECONCILES', 'Consistency', N'[raw_sales].[orders]',
    N'order_total must equal SUM(quantity x unit_price) of its lines',
    N'SELECT o.order_id, o.order_total, l.line_total, o.order_total - l.line_total AS difference
      FROM raw_sales.orders AS o
      INNER JOIN (SELECT order_id, SUM(quantity * unit_price) AS line_total
                  FROM raw_sales.order_items GROUP BY order_id) AS l ON l.order_id = o.order_id
      WHERE ABS(o.order_total - l.line_total) > 0.005',
    N'SELECT COUNT(*) FROM raw_sales.orders';

EXEC dq.usp_register_rule
    'ORD_HAS_LINES', 'Consistency', N'[raw_sales].[orders]',
    N'every order must have at least one line',
    N'SELECT o.* FROM raw_sales.orders AS o
      WHERE NOT EXISTS (SELECT 1 FROM raw_sales.order_items AS i WHERE i.order_id = o.order_id)',
    N'SELECT COUNT(*) FROM raw_sales.orders';

/* ---- Timeliness --------------------------------------------------------- */
-- The limit (hours) is read from dq.setting each time the rule runs
EXEC dq.usp_register_rule
    'ORD_FRESHNESS', 'Timeliness', N'[raw_sales].[orders]',
    N'orders must have been loaded within dq.setting freshness_hours',
    N'SELECT MAX(loaded_at) AS last_load, DATEDIFF(HOUR, MAX(loaded_at), SYSDATETIME()) AS age_hours
      FROM raw_sales.orders
      HAVING MAX(loaded_at) IS NULL
          OR DATEDIFF(HOUR, MAX(loaded_at), SYSDATETIME())
             > (SELECT setting_value FROM dq.setting WHERE setting_name = ''freshness_hours'')',
    N'SELECT 1';

SELECT rule_id, rule_code, quality_dimension, severity, threshold_pct, description
FROM dq.rule
ORDER BY rule_id;
GO
