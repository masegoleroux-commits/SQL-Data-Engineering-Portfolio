/* =============================================================================
   01_build_star_schema.sql
   dim_club             one Premier League club (full name)
   fact_club_transfer   GRAIN: one club's side of one move. Right for "what
                        did each club spend"; a move between two Premier
                        League clubs appears once for each.
   fact_transfer        GRAIN: one move. Mirror rows are matched using the
                        learned aliases and only the buying club's row is
                        kept. Right for "how many moves / how much money
                        changed hands in total".
============================================================================= */

USE TransferMarket;
GO

DROP TABLE IF EXISTS gold.fact_transfer;
DROP TABLE IF EXISTS gold.fact_club_transfer;
DROP TABLE IF EXISTS gold.dim_club;
GO

CREATE TABLE gold.dim_club (
    club_key        INT            NOT NULL PRIMARY KEY,
    club_name       NVARCHAR(60)   NOT NULL UNIQUE,
    seasons_in_data SMALLINT       NOT NULL,
    first_season    SMALLINT       NOT NULL,
    last_season     SMALLINT       NOT NULL
);

INSERT INTO gold.dim_club
SELECT ROW_NUMBER() OVER (ORDER BY club_name), club_name,
       COUNT(DISTINCT season_start), MIN(season_start), MAX(season_start)
FROM silver.transfer_row
GROUP BY club_name;

CREATE TABLE gold.fact_club_transfer (
    row_id           INT            NOT NULL PRIMARY KEY,
    club_key         INT            NOT NULL REFERENCES gold.dim_club (club_key),
    other_club       NVARCHAR(60)   NOT NULL,     -- full name when an alias was learned
    player_name      NVARCHAR(80)   NOT NULL,
    position_group   VARCHAR(15)    NULL,
    age              SMALLINT       NULL,
    season_start     SMALLINT       NOT NULL,
    window_name      VARCHAR(6)     NOT NULL,
    movement         VARCHAR(3)     NOT NULL,
    fee_type         VARCHAR(15)    NOT NULL,
    fee_eur_m        DECIMAL(9, 3)  NULL,
    spend_eur_m      DECIMAL(9, 3)  NOT NULL,     -- + paid, - received, 0 when no fee
    is_mirror        SMALLINT       NOT NULL      -- the selling club's copy of a PL-to-PL move
);

INSERT INTO gold.fact_club_transfer
SELECT t.row_id, c.club_key, COALESCE(a.full_name, t.club_involved), t.player_name, t.position_group,
       t.age, t.season_start, t.window_name, t.movement, t.fee_type, t.fee_eur_m,
       CASE WHEN t.movement = 'in' THEN COALESCE(t.fee_eur_m, 0) ELSE -COALESCE(t.fee_eur_m, 0) END,
       CASE WHEN t.movement = 'out' AND EXISTS (
                SELECT 1
                FROM silver.transfer_row AS i
                INNER JOIN silver.club_alias AS ai ON ai.short_name = i.club_involved
                WHERE i.movement = 'in'
                  AND i.player_name  = t.player_name
                  AND i.season_start = t.season_start
                  AND i.window_name  = t.window_name
                  AND COALESCE(i.fee_text, '') = COALESCE(t.fee_text, '')
                  AND ai.full_name   = t.club_name
                  AND i.club_name    = a.full_name)
            THEN 1 ELSE 0 END
FROM silver.transfer_row AS t
INNER JOIN gold.dim_club AS c ON c.club_name = t.club_name
LEFT JOIN silver.club_alias AS a ON a.short_name = t.club_involved;
GO

CREATE TABLE gold.fact_transfer (
    row_id         INT            NOT NULL PRIMARY KEY,
    player_name    NVARCHAR(80)   NOT NULL,
    from_club      NVARCHAR(60)   NOT NULL,
    to_club        NVARCHAR(60)   NOT NULL,
    season_start   SMALLINT       NOT NULL,
    window_name    VARCHAR(6)     NOT NULL,
    fee_type       VARCHAR(15)    NOT NULL,
    fee_eur_m      DECIMAL(9, 3)  NULL,
    both_clubs_pl  SMALLINT       NOT NULL
);

INSERT INTO gold.fact_transfer
SELECT f.row_id, f.player_name,
       CASE WHEN f.movement = 'in' THEN f.other_club ELSE c.club_name END,
       CASE WHEN f.movement = 'in' THEN c.club_name ELSE f.other_club END,
       f.season_start, f.window_name, f.fee_type, f.fee_eur_m,
       CASE WHEN f.other_club IN (SELECT club_name FROM gold.dim_club) THEN 1 ELSE 0 END
FROM gold.fact_club_transfer AS f
INNER JOIN gold.dim_club AS c ON c.club_key = f.club_key
WHERE f.is_mirror = 0;
GO

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'gold', 'dim_club',           COUNT(*) FROM gold.dim_club UNION ALL
SELECT 'gold', 'fact_club_transfer', COUNT(*) FROM gold.fact_club_transfer UNION ALL
SELECT 'gold', 'fact_transfer',      COUNT(*) FROM gold.fact_transfer;
GO
