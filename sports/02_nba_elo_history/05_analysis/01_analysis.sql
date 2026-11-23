/* =============================================================================
   01_analysis.sql
   Questions answered from the gold layer. Thresholds come from
   ops.business_parameter.
============================================================================= */

USE NbaElo;
GO

/* ---- 1. Peak rating of every franchise, and which identity it had then -- */
WITH ranked AS (
    SELECT tg.franchise_key, tg.team_key, tg.game_date, tg.elo_after,
           ROW_NUMBER() OVER (PARTITION BY tg.franchise_key ORDER BY tg.elo_after DESC, tg.game_date) AS rn
    FROM gold.fact_team_game AS tg
)
SELECT f.franchise_id, t.team_code, t.league, r.game_date AS peak_date,
       CAST(r.elo_after AS DECIMAL(7, 1)) AS peak_elo
FROM ranked AS r
INNER JOIN gold.dim_franchise AS f ON f.franchise_key = r.franchise_key
INNER JOIN gold.dim_team      AS t ON t.team_key      = r.team_key
WHERE r.rn = 1
ORDER BY peak_elo DESC;
GO

/* ---- 2. Biggest upsets --------------------------------------------------- */
DECLARE @upset DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'upset_forecast_max');

SELECT TOP (25)
       tg.game_date,
       w.team_code                              AS winner,
       l.team_code                              AS loser,
       CONCAT(tg.pts, '-', tg.opp_pts)          AS score,
       CAST(100 * tg.forecast AS DECIMAL(5, 1)) AS winner_chance_pct,
       CASE WHEN tg.is_playoffs = 1 THEN 'playoffs' ELSE 'regular season' END AS phase
FROM gold.fact_team_game AS tg
INNER JOIN gold.dim_team AS w ON w.team_key = tg.team_key
INNER JOIN gold.dim_team AS l ON l.team_key = tg.opp_team_key
WHERE tg.is_win = 1 AND tg.forecast <= @upset
ORDER BY tg.forecast;
GO

/* ---- 3. Home-court advantage by decade ----------------------------------- */
SELECT (season / 10) * 10                                      AS decade,
       COUNT(*)                                                AS games,
       CAST(100.0 * SUM(home_win) / COUNT(*) AS DECIMAL(5, 1)) AS home_win_pct,
       CAST(AVG(1.0 * (home_pts - away_pts)) AS DECIMAL(4, 1)) AS avg_home_margin
FROM gold.fact_game
WHERE is_neutral = 0 AND is_forfeit = 0
GROUP BY (season / 10) * 10
ORDER BY decade;
GO

/* ---- 4. Longest winning streaks (gaps and islands) ----------------------- */
-- Each loss starts a new group. Counting losses so far gives every game a
-- group number; the wins inside one group form a streak.
DECLARE @min_streak DECIMAL(10, 4) = (SELECT param_value FROM ops.business_parameter WHERE param_name = 'min_win_streak');

WITH grouped AS (
    SELECT franchise_key, team_key, game_date, is_win,
           SUM(1 - is_win) OVER (PARTITION BY franchise_key ORDER BY team_game_no
                                 ROWS UNBOUNDED PRECEDING) AS loss_count
    FROM gold.fact_team_game
)
SELECT f.franchise_id,
       MIN(t.team_code)  AS team_code,
       COUNT(*)          AS streak,
       MIN(g.game_date)  AS started,
       MAX(g.game_date)  AS ended
FROM grouped AS g
INNER JOIN gold.dim_franchise AS f ON f.franchise_key = g.franchise_key
INNER JOIN gold.dim_team      AS t ON t.team_key      = g.team_key
WHERE g.is_win = 1
GROUP BY f.franchise_id, g.franchise_key, g.loss_count
HAVING COUNT(*) >= @min_streak
ORDER BY streak DESC, started;
GO

/* ---- 5. Best-rated team at season end vs the champion ------------------- */
-- the champion is the winner of the last playoff game of the season
WITH last_rating AS (
    SELECT season, franchise_key, team_key, elo_after,
           ROW_NUMBER() OVER (PARTITION BY season, franchise_key ORDER BY team_game_no DESC) AS rn
    FROM gold.fact_team_game
),
top_rated AS (
    SELECT season, team_key, elo_after,
           ROW_NUMBER() OVER (PARTITION BY season ORDER BY elo_after DESC) AS rk
    FROM last_rating
    WHERE rn = 1
),
final_game AS (
    SELECT tg.season, tg.team_key,
           ROW_NUMBER() OVER (PARTITION BY tg.season ORDER BY tg.game_date DESC, tg.game_key DESC) AS rn
    FROM gold.fact_team_game AS tg
    INNER JOIN gold.dim_team AS t ON t.team_key = tg.team_key
    WHERE tg.is_playoffs = 1 AND tg.is_win = 1 AND t.league = 'NBA'
)
SELECT s.season_label,
       tr.team_code                             AS top_rated_team,
       CAST(r.elo_after AS DECIMAL(7, 1))       AS season_end_elo,
       ch.team_code                             AS nba_champion,
       CASE WHEN ch.franchise_key = tr.franchise_key THEN 'yes' ELSE 'no' END AS top_rated_won
FROM top_rated AS r
INNER JOIN gold.dim_season AS s  ON s.season = r.season
INNER JOIN gold.dim_team   AS tr ON tr.team_key = r.team_key
INNER JOIN final_game      AS fg ON fg.season = r.season AND fg.rn = 1
INNER JOIN gold.dim_team   AS ch ON ch.team_key = fg.team_key
WHERE r.rk = 1
ORDER BY r.season;
GO

/* ---- 6. Did moving city change anything? --------------------------------- */
-- compares the last season under the old code with the first under the new
SELECT f.franchise_id,
       old_t.team_code AS moved_from,
       new_t.team_code AS moved_to,
       new_t.valid_from AS first_season,
       CAST(o.avg_elo AS DECIMAL(7, 1)) AS avg_elo_last_season_before,
       CAST(n.avg_elo AS DECIMAL(7, 1)) AS avg_elo_first_season_after,
       CAST(n.avg_elo - o.avg_elo AS DECIMAL(6, 1)) AS change
FROM gold.dim_team AS new_t
INNER JOIN gold.dim_team AS old_t
        ON old_t.franchise_key = new_t.franchise_key AND old_t.version_no = new_t.version_no - 1
INNER JOIN gold.dim_franchise    AS f ON f.franchise_key = new_t.franchise_key
INNER JOIN gold.v_franchise_season AS o ON o.franchise_key = old_t.franchise_key AND o.season = old_t.valid_to
INNER JOIN gold.v_franchise_season AS n ON n.franchise_key = new_t.franchise_key AND n.season = new_t.valid_from
ORDER BY new_t.valid_from;
GO
