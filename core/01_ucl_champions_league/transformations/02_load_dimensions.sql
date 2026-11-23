/* =============================================================================
   02_load_dimensions.sql
   Upserts dim_club and dim_player from all four staging tables.

   Both dimensions are Type 1: a changed attribute (e.g. a player's listed
   position) overwrites the old value. Surrogate keys are never reissued, so
   facts loaded earlier keep pointing at the same rows.

   Names are trimmed on the way in so ' Inter' and 'Inter' cannot become two
   clubs.
============================================================================= */

USE UCL;
GO

SET NOCOUNT ON;

/* ---- dim_club ------------------------------------------------------------ */
WITH src AS (
    SELECT LTRIM(RTRIM(club)) AS club_name FROM dbo.stg_attacking
    UNION
    SELECT LTRIM(RTRIM(club))              FROM dbo.stg_defending
    UNION
    SELECT LTRIM(RTRIM(club))              FROM dbo.stg_distribution
    UNION
    SELECT LTRIM(RTRIM(club))              FROM dbo.stg_disciplinary
)
MERGE dbo.dim_club AS tgt
USING (SELECT club_name FROM src WHERE club_name IS NOT NULL) AS s
    ON tgt.club_name = s.club_name
WHEN NOT MATCHED BY TARGET THEN
    INSERT (club_name) VALUES (s.club_name);

/* ---- dim_player ---------------------------------------------------------- */
WITH src AS (
    SELECT LTRIM(RTRIM(player_name)) AS player_name, LTRIM(RTRIM(club)) AS club_name, LTRIM(RTRIM(position)) AS position
    FROM dbo.stg_attacking
    UNION
    SELECT LTRIM(RTRIM(player_name)), LTRIM(RTRIM(club)), LTRIM(RTRIM(position)) FROM dbo.stg_defending
    UNION
    SELECT LTRIM(RTRIM(player_name)), LTRIM(RTRIM(club)), LTRIM(RTRIM(position)) FROM dbo.stg_distribution
    UNION
    SELECT LTRIM(RTRIM(player_name)), LTRIM(RTRIM(club)), LTRIM(RTRIM(position)) FROM dbo.stg_disciplinary
),
one_row_per_player AS (
    -- Guards the grain: if two files ever disagree on position, keep one value
    -- (tests/01_grain_checks.sql reports the conflict).
    SELECT player_name, club_name, MAX(position) AS position
    FROM src
    WHERE player_name IS NOT NULL AND club_name IS NOT NULL
    GROUP BY player_name, club_name
)
MERGE dbo.dim_player AS tgt
USING one_row_per_player AS s
    ON  tgt.player_name = s.player_name
    AND tgt.club_name   = s.club_name
WHEN MATCHED AND tgt.position <> s.position THEN
    UPDATE SET tgt.position = s.position
WHEN NOT MATCHED BY TARGET THEN
    INSERT (player_name, club_name, position)
    VALUES (s.player_name, s.club_name, s.position);

-- Expected: 32 clubs, 704 player-club rows
SELECT 'dim_club' AS table_name, COUNT(*) AS row_count FROM dbo.dim_club
UNION ALL
SELECT 'dim_player',            COUNT(*)              FROM dbo.dim_player;
GO
