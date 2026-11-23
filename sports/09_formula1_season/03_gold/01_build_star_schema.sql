/* =============================================================================
   01_build_star_schema.sql
   dim_race, dim_driver, dim_team
   fact_result        GRAIN: one driver in one session (race or sprint),
                      with published points and engine points side by side
   v_standing         GRAIN: one driver after one round (running totals)
   v_team_standing    GRAIN: one team after one round
============================================================================= */

USE Formula1;
GO

DROP VIEW IF EXISTS gold.v_team_standing;
DROP VIEW IF EXISTS gold.v_standing;
DROP TABLE IF EXISTS gold.fact_result;
DROP TABLE IF EXISTS gold.dim_driver;
DROP TABLE IF EXISTS gold.dim_team;
DROP TABLE IF EXISTS gold.dim_race;
GO

CREATE TABLE gold.dim_race (
    round_no      INT            NOT NULL PRIMARY KEY,
    race_date     DATE           NULL,
    gp_name       NVARCHAR(100)  NOT NULL,
    country       NVARCHAR(30)   NOT NULL,
    city          NVARCHAR(30)   NOT NULL,
    has_sprint    SMALLINT       NOT NULL,
    is_cancelled  SMALLINT       NOT NULL
);

INSERT INTO gold.dim_race
SELECT round_no, race_date, gp_name, country, city, has_sprint, is_cancelled FROM silver.race;

CREATE TABLE gold.dim_team (
    team_key    INT           NOT NULL PRIMARY KEY,
    team_name   VARCHAR(40)   NOT NULL UNIQUE,
    power_unit  VARCHAR(30)   NOT NULL
);

INSERT INTO gold.dim_team SELECT ROW_NUMBER() OVER (ORDER BY team_name), team_name, power_unit FROM silver.team;

CREATE TABLE gold.dim_driver (
    driver_key    INT            NOT NULL PRIMARY KEY,
    driver_name   NVARCHAR(40)   NOT NULL UNIQUE,
    car_number    INT            NOT NULL,
    country       NVARCHAR(30)   NULL,
    teams_driven  SMALLINT       NOT NULL
);

INSERT INTO gold.dim_driver
SELECT ROW_NUMBER() OVER (ORDER BY d.driver_name), d.driver_name, d.car_number, d.country,
       (SELECT COUNT(DISTINCT r.team_name) FROM silver.result AS r WHERE r.driver_name = d.driver_name)
FROM silver.driver AS d;
GO

CREATE TABLE gold.fact_result (
    session_type      VARCHAR(10)    NOT NULL,
    round_no          INT            NOT NULL REFERENCES gold.dim_race (round_no),
    driver_key        INT            NOT NULL REFERENCES gold.dim_driver (driver_key),
    team_key          INT            NOT NULL REFERENCES gold.dim_team (team_key),
    grid_position     INT            NULL,
    finish_position   INT            NULL,
    positions_gained  INT            NULL,
    status            VARCHAR(15)    NOT NULL,
    gap_seconds       DECIMAL(9, 3)  NULL,
    fastest_lap       SMALLINT       NOT NULL,
    published_points  DECIMAL(5, 1)  NOT NULL,
    engine_points     DECIMAL(5, 1)  NOT NULL,
    PRIMARY KEY (session_type, round_no, driver_key)
);

DECLARE @fl_bonus DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'fastest_lap_bonus');
DECLARE @fl_max   DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'fastest_lap_max_pos');

INSERT INTO gold.fact_result
SELECT r.session_type, r.round_no, d.driver_key, t.team_key,
       r.grid_position, r.finish_position, r.grid_position - r.finish_position,
       r.status, r.gap_seconds, r.fastest_lap, r.published_points,
       COALESCE(p.points, 0)
     + CASE WHEN r.session_type = 'race' AND r.fastest_lap = 1 AND r.finish_position <= @fl_max
            THEN @fl_bonus ELSE 0 END
FROM silver.result AS r
INNER JOIN gold.dim_driver AS d ON d.driver_name = r.driver_name
INNER JOIN gold.dim_team   AS t ON t.team_name   = r.team_name
LEFT JOIN ops.points_rule  AS p ON p.session_type = r.session_type AND p.position = r.finish_position;
GO

CREATE VIEW gold.v_standing
AS
SELECT x.round_no, x.driver_key, x.round_points,
       SUM(x.round_points) OVER (PARTITION BY x.driver_key ORDER BY x.round_no ROWS UNBOUNDED PRECEDING) AS total_points
FROM (SELECT round_no, driver_key, SUM(engine_points) AS round_points
      FROM gold.fact_result GROUP BY round_no, driver_key) AS x;
GO

CREATE VIEW gold.v_team_standing
AS
SELECT x.round_no, x.team_key, x.round_points,
       SUM(x.round_points) OVER (PARTITION BY x.team_key ORDER BY x.round_no ROWS UNBOUNDED PRECEDING) AS total_points
FROM (SELECT round_no, team_key, SUM(engine_points) AS round_points
      FROM gold.fact_result GROUP BY round_no, team_key) AS x;
GO

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'gold', 'fact_result', COUNT(*) FROM gold.fact_result;
GO
