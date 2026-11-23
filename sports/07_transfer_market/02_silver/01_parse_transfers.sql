/* =============================================================================
   01_parse_transfers.sql
   silver.transfer_row   GRAIN: one club's record of one move (the source
                         is written from each Premier League club's side)

   The fee column holds six different kinds of value in one text field:

     '€5.4m'                    permanent move, fee in millions
     '€910Th.' / '€500k'        permanent move, fee in thousands
     'Loan fee:€1.2m'           loan with a fee
     'loan transfer'            loan, no fee
     'free transfer'            free move
     'End of loanMay 31, 2019'  player returning from a loan, with a date
     '?' / '-' / ''             fee not known

   Parsing rules, each counted in ops.cleaning_log:
     1. Exact duplicate rows removed.
     2. fee_type assigned from the pattern above.
     3. Fee amount parsed to EUR millions: the number between the euro sign
        and the unit, divided by 1,000 for Th. and k.
     4. Loan end date parsed from the text after 'End of loan'.
     5. 'NA' in age and in the cleaned fee becomes NULL.
     6. Position mapped to a group (the source mixes 'Centre-Back' with
        plain 'defence').
     7. from_club / to_club derived from the direction of the move.
============================================================================= */

USE TransferMarket;
GO

DROP TABLE IF EXISTS silver.transfer_row;
GO

CREATE TABLE silver.transfer_row (
    row_id            INT             NOT NULL PRIMARY KEY,
    club_name         NVARCHAR(60)    NOT NULL,      -- the Premier League club whose record this is
    club_involved     NVARCHAR(60)    NOT NULL,      -- the other club, often a short name
    player_name       NVARCHAR(80)    NOT NULL,
    age               SMALLINT        NULL,
    source_position   VARCHAR(40)     NOT NULL,
    position_group    VARCHAR(15)     NULL,
    movement          VARCHAR(3)      NOT NULL,      -- in / out
    window_name       VARCHAR(6)      NOT NULL,      -- Summer / Winter
    season_start      SMALLINT        NOT NULL,
    fee_text          NVARCHAR(60)    NULL,
    fee_type          VARCHAR(15)     NOT NULL,
    fee_eur_m         DECIMAL(9, 3)   NULL,
    source_fee_eur_m  DECIMAL(9, 3)   NULL,          -- the source's own cleaned figure, for reconciliation
    loan_end_date     DATE            NULL
);

WITH distinct_rows AS (
    SELECT DISTINCT club_name, player_name, age, position, club_involved_name, fee,
           transfer_movement, transfer_period, fee_cleaned, year
    FROM bronze.premier_league_transfers
),
typed AS (
    SELECT d.*,
           CASE WHEN fee LIKE 'Loan fee:%'      THEN 'loan with fee'
                WHEN fee LIKE N'€%'             THEN 'permanent'
                WHEN fee = 'loan transfer'      THEN 'loan'
                WHEN fee = 'free transfer'      THEN 'free'
                WHEN fee LIKE 'End of loan%'    THEN 'loan return'
                ELSE 'unknown' END AS fee_type,
           -- the amount and its unit, without the 'Loan fee:' prefix and euro sign
           REPLACE(REPLACE(fee, 'Loan fee:', ''), N'€', '') AS amount_text
    FROM distinct_rows AS d
)
INSERT INTO silver.transfer_row
SELECT ROW_NUMBER() OVER (ORDER BY t.year, t.transfer_period, t.club_name, t.transfer_movement, t.player_name, t.club_involved_name, t.fee),
       t.club_name, t.club_involved_name, t.player_name,
       CASE WHEN t.age = 'NA' THEN NULL ELSE CAST(t.age AS SMALLINT) END,
       t.position, pg.position_group, t.transfer_movement, t.transfer_period,
       CAST(t.year AS SMALLINT),
       NULLIF(t.fee, ''),
       t.fee_type,
       CASE WHEN t.fee_type IN ('permanent', 'loan with fee') THEN
            CASE WHEN t.amount_text LIKE '%m'   THEN CAST(REPLACE(t.amount_text, 'm', '') AS DECIMAL(9, 3))
                 WHEN t.amount_text LIKE '%Th.' THEN CAST(REPLACE(t.amount_text, 'Th.', '') AS DECIMAL(9, 3)) / 1000
                 WHEN t.amount_text LIKE '%k'   THEN CAST(REPLACE(t.amount_text, 'k', '') AS DECIMAL(9, 3)) / 1000
            END
       END,
       CASE WHEN t.fee_cleaned = 'NA' THEN NULL ELSE CAST(t.fee_cleaned AS DECIMAL(9, 3)) END,
       CASE WHEN t.fee_type = 'loan return'
            THEN CONVERT(DATE, REPLACE(t.fee, 'End of loan', ''), 107) END
FROM typed AS t
LEFT JOIN ops.position_group AS pg ON pg.source_position = t.position;
GO

INSERT INTO ops.cleaning_log (step_no, table_name, step_name, rows_affected)
SELECT 1, 'transfer_row', 'Exact duplicate rows removed',
       (SELECT COUNT(*) FROM bronze.premier_league_transfers) - (SELECT COUNT(*) FROM silver.transfer_row)
UNION ALL
SELECT 2, 'transfer_row', CONCAT('Fee type assigned: ', fee_type), COUNT(*)
FROM silver.transfer_row GROUP BY fee_type
UNION ALL
SELECT 3, 'transfer_row', 'Fee parsed from text to EUR millions', COUNT(*) FROM silver.transfer_row WHERE fee_eur_m IS NOT NULL
UNION ALL
SELECT 4, 'transfer_row', 'Loan end date parsed from text', COUNT(*) FROM silver.transfer_row WHERE loan_end_date IS NOT NULL
UNION ALL
SELECT 5, 'transfer_row', 'Age ''NA'' set to NULL', COUNT(*) FROM silver.transfer_row WHERE age IS NULL
UNION ALL
SELECT 6, 'transfer_row', 'Broad positions (defence / midfield / attack) mapped to a group',
       COUNT(*) FROM silver.transfer_row WHERE source_position IN ('defence', 'midfield', 'attack');

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'silver', 'transfer_row', COUNT(*) FROM silver.transfer_row;
GO
