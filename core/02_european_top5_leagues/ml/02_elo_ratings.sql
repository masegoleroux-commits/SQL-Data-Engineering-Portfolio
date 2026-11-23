/* =============================================================================
   02_elo_ratings.sql
   Stage 5b: Elo team-strength ratings, match by match, in date order.

   How Elo works
   -------------
   * Every team has a rating. Before a match the model works out the home
     team's expected score:
         expected_home = 1 / (1 + 10 ^ ((away_rating - (home_rating + home_advantage)) / 400))
     0.5 means an even match; 0.8 means the home side is a strong favourite.
   * Actual score: win = 1, draw = 0.5, loss = 0.
   * After the match both ratings move by  K x (actual - expected).
     Whatever the home team gains, the away team loses (zero-sum).
   * Between seasons every rating is pulled part of the way back towards
     1500 (squads change), and promoted teams start below average.

   All settings (K, home advantage, carry-over, starting ratings) are read
   from cfg.business_parameter.

   Ratings depend on the previous match, so this is one of the few places a
   loop is the right tool. About 5,300 matches run in a few seconds.
   Each rating is stored as it was BEFORE the match, which is what the
   prediction model is allowed to use.
============================================================================= */

USE EuroLeagues;
GO

SET NOCOUNT ON;

DECLARE @k             FLOAT = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'elo_k_factor'),
        @home_adv      FLOAT = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'elo_home_advantage'),
        @carryover     FLOAT = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'elo_season_carryover'),
        @initial       FLOAT = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'elo_initial_rating'),
        @promoted      FLOAT = (SELECT param_value FROM cfg.business_parameter WHERE param_name = 'elo_promoted_rating'),
        @first_season  SMALLINT = (SELECT MIN(season_key) FROM dw.fact_match);

DROP TABLE IF EXISTS ml.elo_history;
CREATE TABLE ml.elo_history (
    match_key           INT       NOT NULL,
    season_key          SMALLINT  NOT NULL,
    home_team_key       SMALLINT  NOT NULL,
    away_team_key       SMALLINT  NOT NULL,
    home_elo_before     FLOAT     NOT NULL,
    away_elo_before     FLOAT     NOT NULL,
    expected_home       FLOAT     NOT NULL,     -- 0..1, includes home advantage
    actual_home         FLOAT     NOT NULL,     -- 1 / 0.5 / 0
    rating_change       FLOAT     NOT NULL,     -- added to home, taken from away
    CONSTRAINT pk_elo_history PRIMARY KEY (match_key)
);

DROP TABLE IF EXISTS #rating;
CREATE TABLE #rating (team_key SMALLINT PRIMARY KEY, rating FLOAT NOT NULL);

DECLARE @match_key INT, @season SMALLINT, @home SMALLINT, @away SMALLINT, @result CHAR(1),
        @current_season SMALLINT = NULL,
        @r_home FLOAT, @r_away FLOAT, @expected FLOAT, @actual FLOAT, @change FLOAT;

DECLARE match_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT match_key, season_key, home_team_key, away_team_key, ft_result
    FROM dw.fact_match
    ORDER BY season_key, date_key, match_key;

OPEN match_cursor;
FETCH NEXT FROM match_cursor INTO @match_key, @season, @home, @away, @result;

BEGIN TRANSACTION;     -- one commit at the end is much faster than 5,000 small ones

WHILE @@FETCH_STATUS = 0
BEGIN
    -- New season: pull every rating part of the way back to the starting value
    IF @current_season IS NOT NULL AND @season <> @current_season
        UPDATE #rating SET rating = @initial + @carryover * (rating - @initial);
    SET @current_season = @season;

    -- First appearance: average rating in the first season, below average later (promoted)
    IF NOT EXISTS (SELECT 1 FROM #rating WHERE team_key = @home)
        INSERT INTO #rating VALUES (@home, CASE WHEN @season = @first_season THEN @initial ELSE @promoted END);
    IF NOT EXISTS (SELECT 1 FROM #rating WHERE team_key = @away)
        INSERT INTO #rating VALUES (@away, CASE WHEN @season = @first_season THEN @initial ELSE @promoted END);

    SELECT @r_home = rating FROM #rating WHERE team_key = @home;
    SELECT @r_away = rating FROM #rating WHERE team_key = @away;

    SET @expected = 1.0 / (1.0 + POWER(CAST(10.0 AS FLOAT), (@r_away - (@r_home + @home_adv)) / 400.0));
    SET @actual   = CASE @result WHEN 'H' THEN 1.0 WHEN 'D' THEN 0.5 ELSE 0.0 END;
    SET @change   = @k * (@actual - @expected);

    INSERT INTO ml.elo_history
    VALUES (@match_key, @season, @home, @away, @r_home, @r_away, @expected, @actual, @change);

    UPDATE #rating SET rating = rating + @change WHERE team_key = @home;
    UPDATE #rating SET rating = rating - @change WHERE team_key = @away;

    FETCH NEXT FROM match_cursor INTO @match_key, @season, @home, @away, @result;
END;

COMMIT TRANSACTION;

CLOSE match_cursor;
DEALLOCATE match_cursor;

-- Final ratings (after the last match in the data)
DROP TABLE IF EXISTS ml.team_rating_current;
SELECT r.team_key, t.team_name, l.league_name, CAST(r.rating AS DECIMAL(7, 1)) AS elo_rating
INTO ml.team_rating_current
FROM #rating AS r
INNER JOIN dw.dim_team   AS t ON t.team_key   = r.team_key
INNER JOIN dw.dim_league AS l ON l.league_key = t.league_key;

DROP TABLE #rating;
GO

-- Highest-rated team in each league (ratings are comparable only within a league)
SELECT league_name, team_name, elo_rating
FROM (SELECT league_name, team_name, elo_rating,
             ROW_NUMBER() OVER (PARTITION BY league_name ORDER BY elo_rating DESC) AS rn
      FROM ml.team_rating_current) AS r
WHERE rn = 1
ORDER BY league_name;
GO
