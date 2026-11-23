/* =============================================================================
   01_points_engine.sql
   Gold layer and the points engine.

   dim_player              one row per player (position, current club)
   fact_player_fixture     GRAIN: one player in one fixture
   fact_points_breakdown   GRAIN: one rule set, player, fixture and event,
                           so every point can be explained

   The engine is a single join: events x rules. A rule matches an event
   when the event names match, the rule's position is the player's
   position or ALL, and the player reached the rule's minimum minutes.

       points = (quantity / unit_size) x points      (integer division,
                                                      so 5 saves = 1 unit)
============================================================================= */

USE FantasyPoints;
GO

DROP TABLE IF EXISTS gold.fact_points_breakdown;
DROP TABLE IF EXISTS gold.fact_player_fixture;
DROP TABLE IF EXISTS gold.dim_player;
GO

CREATE TABLE gold.dim_player (
    player_id      INT            NOT NULL PRIMARY KEY,
    player_name    NVARCHAR(60)   NOT NULL,
    position       VARCHAR(3)     NOT NULL,
    current_team   VARCHAR(40)    NOT NULL,
    clubs_this_season SMALLINT    NOT NULL
);

INSERT INTO gold.dim_player
SELECT p.player_id, p.player_name, p.position, p.team_name,
       (SELECT COUNT(DISTINCT q.team_name) FROM silver.player_fixture AS q WHERE q.player_id = p.player_id)
FROM (SELECT player_id, player_name, position, team_name,
             ROW_NUMBER() OVER (PARTITION BY player_id ORDER BY kickoff_utc DESC) AS rn
      FROM silver.player_fixture) AS p
WHERE p.rn = 1;

CREATE TABLE gold.fact_points_breakdown (
    rule_set     INT          NOT NULL,
    player_id    INT          NOT NULL REFERENCES gold.dim_player (player_id),
    fixture_id   INT          NOT NULL,
    event        VARCHAR(30)  NOT NULL,
    quantity     INT          NOT NULL,
    points       INT          NOT NULL,
    PRIMARY KEY (rule_set, player_id, fixture_id, event)
);

INSERT INTO gold.fact_points_breakdown
SELECT r.rule_set, e.player_id, e.fixture_id, e.event, e.quantity,
       (e.quantity / r.unit_size) * r.points
FROM silver.player_fixture_event AS e
INNER JOIN silver.player_fixture AS p
        ON p.player_id = e.player_id AND p.fixture_id = e.fixture_id
INNER JOIN ops.scoring_rule AS r
        ON r.event = e.event
       AND r.position IN (p.position, 'ALL')
       AND p.minutes >= r.min_minutes;
GO

CREATE TABLE gold.fact_player_fixture (
    player_id        INT            NOT NULL REFERENCES gold.dim_player (player_id),
    fixture_id       INT            NOT NULL,
    gameweek         SMALLINT       NOT NULL,
    kickoff_utc      DATETIME2(0)   NOT NULL,
    team_name        VARCHAR(40)    NOT NULL,
    opponent_name    VARCHAR(40)    NOT NULL,
    is_home          SMALLINT       NOT NULL,
    minutes          SMALLINT       NOT NULL,
    official_points  SMALLINT       NOT NULL,
    engine_points    SMALLINT       NOT NULL,   -- official rule set
    scenario_points  SMALLINT       NOT NULL,   -- what-if rule set
    expected_points  DECIMAL(5, 2)  NOT NULL,
    price_millions   DECIMAL(4, 1)  NOT NULL,
    PRIMARY KEY (player_id, fixture_id)
);

DECLARE @official DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'official_rule_set');
DECLARE @scenario DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'scenario_rule_set');

INSERT INTO gold.fact_player_fixture
SELECT p.player_id, p.fixture_id, p.gameweek, p.kickoff_utc, p.team_name, p.opponent_name,
       p.is_home, p.minutes, p.official_points,
       COALESCE((SELECT SUM(b.points) FROM gold.fact_points_breakdown AS b
                 WHERE b.rule_set = @official AND b.player_id = p.player_id AND b.fixture_id = p.fixture_id), 0),
       COALESCE((SELECT SUM(b.points) FROM gold.fact_points_breakdown AS b
                 WHERE b.rule_set = @scenario AND b.player_id = p.player_id AND b.fixture_id = p.fixture_id), 0),
       p.expected_points, p.price_millions
FROM silver.player_fixture AS p;
GO

INSERT INTO ops.load_log (layer, table_name, row_count)
SELECT 'gold', 'dim_player',            COUNT(*) FROM gold.dim_player UNION ALL
SELECT 'gold', 'fact_points_breakdown', COUNT(*) FROM gold.fact_points_breakdown UNION ALL
SELECT 'gold', 'fact_player_fixture',   COUNT(*) FROM gold.fact_player_fixture;
GO
