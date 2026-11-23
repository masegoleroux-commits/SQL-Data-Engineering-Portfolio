/* =============================================================================
   03_dimensions.sql
   Conformed dimensions shared by all four fact tables.

   dim_club    one row per club                     natural key: club_name
   dim_player  one row per player per club          natural key: player_name + club_name

   Why player + club and not player alone:
   the source identifies players by display name only. "Martínez" appears at
   Ajax, Inter and Leipzig (three different people), and Luis Díaz appears at
   Porto and Liverpool (one person, mid-season transfer). Without a source
   player ID the safest grain is the player-club stint.

   Facts reference these tables, so drop the facts first on a rebuild.
============================================================================= */

USE UCL;
GO

DROP TABLE IF EXISTS dbo.fact_attacking;
DROP TABLE IF EXISTS dbo.fact_defending;
DROP TABLE IF EXISTS dbo.fact_distribution;
DROP TABLE IF EXISTS dbo.fact_discipline;
DROP TABLE IF EXISTS dbo.dim_player;
DROP TABLE IF EXISTS dbo.dim_club;
GO

CREATE TABLE dbo.dim_club (
    club_key        INT             IDENTITY(1, 1)  NOT NULL,
    club_name       NVARCHAR(100)                   NOT NULL,
    CONSTRAINT pk_dim_club      PRIMARY KEY CLUSTERED (club_key),
    CONSTRAINT uq_dim_club_name UNIQUE (club_name)
);
GO

CREATE TABLE dbo.dim_player (
    player_key      INT             IDENTITY(1, 1)  NOT NULL,
    player_name     NVARCHAR(100)                   NOT NULL,
    club_name       NVARCHAR(100)                   NOT NULL,
    position        NVARCHAR(20)                    NOT NULL,
    CONSTRAINT pk_dim_player        PRIMARY KEY CLUSTERED (player_key),
    CONSTRAINT uq_dim_player_nk     UNIQUE (player_name, club_name),
    CONSTRAINT ck_dim_player_pos    CHECK (position IN (N'Goalkeeper', N'Defender', N'Midfielder', N'Forward'))
);
GO
