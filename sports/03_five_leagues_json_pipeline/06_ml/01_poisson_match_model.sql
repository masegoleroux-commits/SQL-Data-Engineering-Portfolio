/* =============================================================================
   01_poisson_match_model.sql
   A Poisson goals model, the standard starting point for football
   prediction, built set-based in T-SQL.

   1. STRENGTHS. For each team: attack  = goals scored per match / league
                                          average goals per team per match
                                defence = goals conceded per match / same
      1.20 attack means 20% more goals than an average team.
   2. EXPECTED GOALS for a match:
         home_xg = league home average x home attack x away defence
         away_xg = league away average x away attack x home defence
   3. SCORE PROBABILITIES. Goals are treated as Poisson counts:
         P(k goals) = e^(-xg) * xg^k / k!
      Every score from 0-0 to max_goals_modelled each way is scored; adding
      the cells where home > away gives P(home win), and so on.
   4. SHRINKAGE. Raw strengths over-react to small samples, so each is
      pulled toward 1.00:  shrunk = 1 + s * (raw - 1). s is the one value
      the model learns.

   Three-way split, so the test seasons are never used to make a choice:
     fit        seasons before validation_season_start  -> strengths
     validation the validation season                   -> choose s
     test       seasons from test_season_start          -> report results
                (strengths refit on everything before the test seasons)

   Only played matches are used. Awarded results say nothing about goals.
============================================================================= */

USE FootballLeagues;
GO

DROP TABLE IF EXISTS ml.model_metric;
DROP TABLE IF EXISTS ml.prediction;
DROP TABLE IF EXISTS ml.shrink_search;
DROP TABLE IF EXISTS ml.match_input;
DROP TABLE IF EXISTS ml.team_strength;
DROP TABLE IF EXISTS ml.league_average;
DROP TABLE IF EXISTS ml.goal_count;
GO

/* ---- Goal counts 0..max with k! ------------------------------------------ */
CREATE TABLE ml.goal_count (
    goals      INT            NOT NULL PRIMARY KEY,
    factorial  DECIMAL(18, 0) NOT NULL
);

DECLARE @max_goals DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'max_goals_modelled');

-- k! = e^(ln 1 + ln 2 + ... + ln k), a running sum of logs
INSERT INTO ml.goal_count
SELECT n,
       ROUND(EXP(SUM(LOG(CASE WHEN n = 0 THEN 1 ELSE n END))
                 OVER (ORDER BY n ROWS UNBOUNDED PRECEDING)), 0)
FROM (SELECT TOP (100) ROW_NUMBER() OVER (ORDER BY object_id) - 1 AS n FROM sys.all_objects) AS nums
WHERE n <= @max_goals;
GO

/* ---- 1. League averages and team strengths for both windows -------------- */
CREATE TABLE ml.league_average (
    window_name  VARCHAR(10)    NOT NULL,   -- fit / final
    league_key   INT            NOT NULL,
    home_goals   DECIMAL(6, 4)  NOT NULL,
    away_goals   DECIMAL(6, 4)  NOT NULL,
    home_rate    DECIMAL(6, 4)  NOT NULL,   -- share of home wins, used by the baseline
    draw_rate    DECIMAL(6, 4)  NOT NULL,
    away_rate    DECIMAL(6, 4)  NOT NULL,
    PRIMARY KEY (window_name, league_key)
);

DECLARE @val_start  DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'validation_season_start');
DECLARE @test_start DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'test_season_start');

INSERT INTO ml.league_average
SELECT w.window_name, f.league_key,
       AVG(1.0 * f.ft_home), AVG(1.0 * f.ft_away),
       AVG(CASE WHEN f.result = 'H' THEN 1.0 ELSE 0 END),
       AVG(CASE WHEN f.result = 'D' THEN 1.0 ELSE 0 END),
       AVG(CASE WHEN f.result = 'A' THEN 1.0 ELSE 0 END)
FROM gold.fact_match AS f
INNER JOIN (SELECT 'fit' AS window_name, @val_start AS before_season
            UNION ALL SELECT 'final', @test_start) AS w
        ON f.season_key < w.before_season
WHERE f.counts_in_goals = 1
GROUP BY w.window_name, f.league_key;

CREATE TABLE ml.team_strength (
    window_name  VARCHAR(10)    NOT NULL,
    team_key     INT            NOT NULL,
    matches      INT            NOT NULL,
    attack       DECIMAL(6, 4)  NOT NULL,
    defence      DECIMAL(6, 4)  NOT NULL,
    PRIMARY KEY (window_name, team_key)
);

INSERT INTO ml.team_strength
SELECT w.window_name, tm.team_key, COUNT(*),
       AVG(1.0 * tm.goals_for)     / ((la.home_goals + la.away_goals) / 2),
       AVG(1.0 * tm.goals_against) / ((la.home_goals + la.away_goals) / 2)
FROM gold.fact_team_match AS tm
INNER JOIN (SELECT 'fit' AS window_name, @val_start AS before_season
            UNION ALL SELECT 'final', @test_start) AS w
        ON tm.season_key < w.before_season
INNER JOIN ml.league_average AS la
        ON la.window_name = w.window_name AND la.league_key = tm.league_key
WHERE tm.counts_in_goals = 1
GROUP BY w.window_name, tm.team_key, la.home_goals, la.away_goals;
GO

/* ---- 2. One input row per match to predict ------------------------------- */
CREATE TABLE ml.match_input (
    match_key     INT            NOT NULL PRIMARY KEY,
    data_split    VARCHAR(10)    NOT NULL,   -- validation / test
    window_name   VARCHAR(10)    NOT NULL,
    league_key    INT            NOT NULL,
    home_attack   DECIMAL(6, 4)  NOT NULL,
    home_defence  DECIMAL(6, 4)  NOT NULL,
    away_attack   DECIMAL(6, 4)  NOT NULL,
    away_defence  DECIMAL(6, 4)  NOT NULL,
    actual_result CHAR(1)        NOT NULL
);

DECLARE @val_start  DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'validation_season_start');
DECLARE @test_start DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'test_season_start');
DECLARE @new_team   DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'new_team_strength');

-- a team with no history (normally just promoted) gets new_team_strength
-- for attack and the inverse for defence: fewer goals for, more against
INSERT INTO ml.match_input
SELECT f.match_key, s.data_split, s.window_name, f.league_key,
       COALESCE(sh.attack,  @new_team), COALESCE(sh.defence, 1.0 / @new_team),
       COALESCE(sa.attack,  @new_team), COALESCE(sa.defence, 1.0 / @new_team),
       f.result
FROM gold.fact_match AS f
INNER JOIN (SELECT 'validation' AS data_split, 'fit' AS window_name
            UNION ALL SELECT 'test', 'final') AS s
        ON (s.data_split = 'validation' AND f.season_key = @val_start)
        OR (s.data_split = 'test'       AND f.season_key >= @test_start)
LEFT JOIN ml.team_strength AS sh ON sh.window_name = s.window_name AND sh.team_key = f.home_team_key
LEFT JOIN ml.team_strength AS sa ON sa.window_name = s.window_name AND sa.team_key = f.away_team_key
WHERE f.counts_in_goals = 1;
GO

/* ---- 3. Validation: choose the shrinkage --------------------------------- */
CREATE TABLE ml.shrink_search (
    shrink          DECIMAL(3, 1)  NOT NULL PRIMARY KEY,
    matches         INT            NOT NULL,
    log_loss        DECIMAL(8, 5)  NOT NULL,
    is_chosen       SMALLINT       NOT NULL
);

WITH shrink AS (
    SELECT CAST(n / 10.0 AS DECIMAL(3, 1)) AS shrink
    FROM (SELECT TOP (11) ROW_NUMBER() OVER (ORDER BY object_id) - 1 AS n FROM sys.all_objects) AS nums
),
xg AS (
    SELECT s.shrink, mi.match_key, mi.actual_result,
           la.home_goals * (1 + s.shrink * (mi.home_attack - 1)) * (1 + s.shrink * (mi.away_defence - 1)) AS home_xg,
           la.away_goals * (1 + s.shrink * (mi.away_attack - 1)) * (1 + s.shrink * (mi.home_defence - 1)) AS away_xg
    FROM ml.match_input AS mi
    CROSS JOIN shrink AS s
    INNER JOIN ml.league_average AS la ON la.window_name = mi.window_name AND la.league_key = mi.league_key
    WHERE mi.data_split = 'validation'
),
cell AS (
    SELECT x.shrink, x.match_key, x.actual_result, h.goals AS hg, a.goals AS ag,
           (EXP(-x.home_xg) * POWER(x.home_xg, h.goals) / h.factorial)
         * (EXP(-x.away_xg) * POWER(x.away_xg, a.goals) / a.factorial) AS p
    FROM xg AS x
    CROSS JOIN ml.goal_count AS h
    CROSS JOIN ml.goal_count AS a
),
outcome AS (
    SELECT shrink, match_key, actual_result,
           SUM(CASE WHEN hg > ag THEN p ELSE 0 END) / SUM(p) AS p_home,
           SUM(CASE WHEN hg = ag THEN p ELSE 0 END) / SUM(p) AS p_draw,
           SUM(CASE WHEN hg < ag THEN p ELSE 0 END) / SUM(p) AS p_away
    FROM cell
    GROUP BY shrink, match_key, actual_result
),
scored AS (
    SELECT shrink, COUNT(*) AS matches,
           -AVG(LOG(CASE actual_result WHEN 'H' THEN p_home WHEN 'D' THEN p_draw ELSE p_away END)) AS log_loss
    FROM outcome
    GROUP BY shrink
)
INSERT INTO ml.shrink_search
SELECT shrink, matches, CAST(log_loss AS DECIMAL(8, 5)),
       CASE WHEN ROW_NUMBER() OVER (ORDER BY log_loss, shrink) = 1 THEN 1 ELSE 0 END
FROM scored;
GO

/* ---- 4. Test: predict the held-back seasons with the chosen shrinkage ---- */
CREATE TABLE ml.prediction (
    match_key        INT            NOT NULL PRIMARY KEY,
    home_xg          DECIMAL(6, 3)  NOT NULL,
    away_xg          DECIMAL(6, 3)  NOT NULL,
    p_home           DECIMAL(6, 4)  NOT NULL,
    p_draw           DECIMAL(6, 4)  NOT NULL,
    p_away           DECIMAL(6, 4)  NOT NULL,
    predicted_result CHAR(1)        NOT NULL,
    actual_result    CHAR(1)        NOT NULL
);

DECLARE @shrink DECIMAL(10, 4) = (SELECT shrink FROM ml.shrink_search WHERE is_chosen = 1);

WITH xg AS (
    SELECT mi.match_key, mi.actual_result,
           la.home_goals * (1 + @shrink * (mi.home_attack - 1)) * (1 + @shrink * (mi.away_defence - 1)) AS home_xg,
           la.away_goals * (1 + @shrink * (mi.away_attack - 1)) * (1 + @shrink * (mi.home_defence - 1)) AS away_xg
    FROM ml.match_input AS mi
    INNER JOIN ml.league_average AS la ON la.window_name = mi.window_name AND la.league_key = mi.league_key
    WHERE mi.data_split = 'test'
),
cell AS (
    SELECT x.match_key, x.actual_result, x.home_xg, x.away_xg, h.goals AS hg, a.goals AS ag,
           (EXP(-x.home_xg) * POWER(x.home_xg, h.goals) / h.factorial)
         * (EXP(-x.away_xg) * POWER(x.away_xg, a.goals) / a.factorial) AS p
    FROM xg AS x
    CROSS JOIN ml.goal_count AS h
    CROSS JOIN ml.goal_count AS a
),
outcome AS (
    SELECT match_key, actual_result, home_xg, away_xg,
           SUM(CASE WHEN hg > ag THEN p ELSE 0 END) / SUM(p) AS p_home,
           SUM(CASE WHEN hg = ag THEN p ELSE 0 END) / SUM(p) AS p_draw,
           SUM(CASE WHEN hg < ag THEN p ELSE 0 END) / SUM(p) AS p_away
    FROM cell
    GROUP BY match_key, actual_result, home_xg, away_xg
)
INSERT INTO ml.prediction
SELECT match_key, home_xg, away_xg, p_home, p_draw, p_away,
       CASE WHEN p_home >= p_draw AND p_home >= p_away THEN 'H'
            WHEN p_away >= p_draw THEN 'A'
            ELSE 'D' END,
       actual_result
FROM outcome;
GO

/* ---- 5. Metrics against a baseline ---------------------------------------- */
-- baseline: every match gets its league's historical home / draw / away rates
CREATE TABLE ml.model_metric (
    metric_name   VARCHAR(60)    NOT NULL PRIMARY KEY,
    metric_value  DECIMAL(10, 4) NOT NULL
);

INSERT INTO ml.model_metric
SELECT 'chosen shrinkage', shrink FROM ml.shrink_search WHERE is_chosen = 1
UNION ALL
SELECT 'test matches', COUNT(*) FROM ml.prediction
UNION ALL
SELECT 'test log loss: Poisson model',
       -AVG(LOG(CASE actual_result WHEN 'H' THEN p_home WHEN 'D' THEN p_draw ELSE p_away END))
FROM ml.prediction
UNION ALL
SELECT 'test log loss: league-rate baseline',
       -AVG(LOG(CASE p.actual_result WHEN 'H' THEN la.home_rate WHEN 'D' THEN la.draw_rate ELSE la.away_rate END))
FROM ml.prediction AS p
INNER JOIN ml.match_input    AS mi ON mi.match_key = p.match_key
INNER JOIN ml.league_average AS la ON la.window_name = mi.window_name AND la.league_key = mi.league_key
UNION ALL
SELECT 'test accuracy: Poisson model',
       AVG(CASE WHEN predicted_result = actual_result THEN 1.0 ELSE 0 END) FROM ml.prediction
UNION ALL
SELECT 'test accuracy: always pick home',
       AVG(CASE WHEN actual_result = 'H' THEN 1.0 ELSE 0 END) FROM ml.prediction
UNION ALL
SELECT 'test: average predicted draw chance',  AVG(p_draw) FROM ml.prediction
UNION ALL
SELECT 'test: actual draw rate', AVG(CASE WHEN actual_result = 'D' THEN 1.0 ELSE 0 END) FROM ml.prediction;

SELECT metric_name, metric_value FROM ml.model_metric ORDER BY metric_name;
GO
