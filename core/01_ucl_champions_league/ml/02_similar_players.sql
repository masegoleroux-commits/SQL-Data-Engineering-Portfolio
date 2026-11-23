/* =============================================================================
   02_similar_players.sql
   Player similarity search (nearest neighbours) on ml.player_features.

   Use case: a club loses a key player and the recruitment team wants a
   shortlist of players with the most similar statistical profile.

   Method
   ------
   Each player is a point in a 10-dimensional space (the z-score columns).
   Distance between two players = Euclidean distance between their points.
   Smaller distance = more similar. similarity_score = 1 / (1 + distance)
   turns it into a 0-1 number that is easier to read.

   Only players in the same position are compared. Change @player_name and
   @club_name to search for someone else. The number of results comes from
   business_parameter.similar_players_top_n.
============================================================================= */

USE UCL;
GO

SET NOCOUNT ON;

DECLARE @player_name NVARCHAR(100) = N'Rodri',
        @club_name   NVARCHAR(100) = N'Man. City';

DECLARE @top_n INT = (SELECT param_value FROM dbo.business_parameter WHERE param_name = 'similar_players_top_n');

IF NOT EXISTS (SELECT 1 FROM ml.player_features WHERE player_name = @player_name AND club_name = @club_name)
BEGIN
    RAISERROR(N'Player not found in ml.player_features (goalkeeper, too few minutes, or a typo in the name).', 16, 1);
    RETURN;
END;

-- 1. The target player's profile
SELECT player_name, club_name, position, minutes_played,
       passes_p90, pass_completion_pct, recoveries_p90, tackles_p90,
       tackle_success_pct, clearances_p90, fouls_p90, assists_p90
FROM ml.player_features
WHERE player_name = @player_name
  AND club_name   = @club_name;

-- 2. Most similar players in the same position
WITH target AS (
    SELECT *
    FROM ml.player_features
    WHERE player_name = @player_name
      AND club_name   = @club_name
),
distances AS (
    SELECT
        c.player_name,
        c.club_name,
        c.position,
        c.minutes_played,
        c.passes_p90,
        c.pass_completion_pct,
        c.recoveries_p90,
        c.tackles_p90,
        SQRT(
              SQUARE(c.z_passes          - t.z_passes)
            + SQUARE(c.z_pass_completion - t.z_pass_completion)
            + SQUARE(c.z_crosses         - t.z_crosses)
            + SQUARE(c.z_recoveries      - t.z_recoveries)
            + SQUARE(c.z_tackles         - t.z_tackles)
            + SQUARE(c.z_tackle_success  - t.z_tackle_success)
            + SQUARE(c.z_clearances      - t.z_clearances)
            + SQUARE(c.z_fouls           - t.z_fouls)
            + SQUARE(c.z_fouled          - t.z_fouled)
            + SQUARE(c.z_assists         - t.z_assists)
        ) AS distance
    FROM ml.player_features AS c
    INNER JOIN target AS t
        ON  t.position   =  c.position
        AND t.player_key <> c.player_key
)
SELECT TOP (@top_n)
    ROW_NUMBER() OVER (ORDER BY distance) AS rank_no,
    player_name,
    club_name,
    minutes_played,
    passes_p90,
    pass_completion_pct,
    recoveries_p90,
    tackles_p90,
    CAST(distance             AS DECIMAL(6, 3)) AS distance,
    CAST(1.0 / (1 + distance) AS DECIMAL(5, 3)) AS similarity_score
FROM distances
ORDER BY distance;
GO
