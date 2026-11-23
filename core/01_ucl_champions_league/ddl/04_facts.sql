/* =============================================================================
   04_facts.sql
   One fact table per source subject area. All four share the same grain and
   the same conformed dimensions, so they can be combined through dim_player
   without fan-out.

   Grain: one row per player per club, UCL season 2021/22.
   player_key is the primary key because it already encodes the club.
   club_key is carried as well so club-level aggregates do not need dim_player.

   Only additive counts are stored. Ratios (tackle success, pass completion,
   fouls per 90) are derived in views so they always aggregate correctly.
   The one exception is pass_accuracy_src, kept as a source attribute because
   it does not reconcile to the pass counts (see docs/data_quality.md).
============================================================================= */

USE UCL;
GO

CREATE TABLE dbo.fact_attacking (
    player_key          INT NOT NULL,
    club_key            INT NOT NULL,
    matches_played      INT NOT NULL,
    assists             INT NOT NULL,
    corners_taken       INT NOT NULL,
    offsides            INT NOT NULL,
    dribbles            INT NOT NULL,
    CONSTRAINT pk_fact_attacking         PRIMARY KEY CLUSTERED (player_key),
    CONSTRAINT fk_fact_attacking_player  FOREIGN KEY (player_key) REFERENCES dbo.dim_player (player_key),
    CONSTRAINT fk_fact_attacking_club    FOREIGN KEY (club_key)   REFERENCES dbo.dim_club (club_key),
    CONSTRAINT ck_fact_attacking_nonneg  CHECK (matches_played > 0 AND assists >= 0 AND corners_taken >= 0
                                                AND offsides >= 0 AND dribbles >= 0)
);
GO

CREATE TABLE dbo.fact_defending (
    player_key              INT NOT NULL,
    club_key                INT NOT NULL,
    matches_played          INT NOT NULL,
    balls_recovered         INT NOT NULL,
    tackles                 INT NOT NULL,
    tackles_won             INT NOT NULL,
    tackles_lost            INT NOT NULL,
    clearances_attempted    INT NOT NULL,
    CONSTRAINT pk_fact_defending         PRIMARY KEY CLUSTERED (player_key),
    CONSTRAINT fk_fact_defending_player  FOREIGN KEY (player_key) REFERENCES dbo.dim_player (player_key),
    CONSTRAINT fk_fact_defending_club    FOREIGN KEY (club_key)   REFERENCES dbo.dim_club (club_key),
    CONSTRAINT ck_fact_defending_tackles CHECK (tackles = tackles_won + tackles_lost),
    CONSTRAINT ck_fact_defending_nonneg  CHECK (matches_played > 0 AND balls_recovered >= 0 AND tackles_won >= 0
                                                AND tackles_lost >= 0 AND clearances_attempted >= 0)
);
GO

CREATE TABLE dbo.fact_distribution (
    player_key          INT             NOT NULL,
    club_key            INT             NOT NULL,
    matches_played      INT             NOT NULL,
    passes_attempted    INT             NOT NULL,
    passes_completed    INT             NOT NULL,
    crosses_attempted   INT             NOT NULL,
    crosses_completed   INT             NOT NULL,
    free_kicks_taken    INT             NOT NULL,
    pass_accuracy_src   DECIMAL(5, 1)   NULL,
    CONSTRAINT pk_fact_distribution         PRIMARY KEY CLUSTERED (player_key),
    CONSTRAINT fk_fact_distribution_player  FOREIGN KEY (player_key) REFERENCES dbo.dim_player (player_key),
    CONSTRAINT fk_fact_distribution_club    FOREIGN KEY (club_key)   REFERENCES dbo.dim_club (club_key),
    CONSTRAINT ck_fact_distribution_passes  CHECK (passes_completed  BETWEEN 0 AND passes_attempted),
    CONSTRAINT ck_fact_distribution_crosses CHECK (crosses_completed BETWEEN 0 AND crosses_attempted),
    CONSTRAINT ck_fact_distribution_nonneg  CHECK (matches_played > 0 AND free_kicks_taken >= 0)
);
GO

CREATE TABLE dbo.fact_discipline (
    player_key          INT NOT NULL,
    club_key            INT NOT NULL,
    matches_played      INT NOT NULL,
    minutes_played      INT NOT NULL,
    fouls_committed     INT NOT NULL,
    fouls_suffered      INT NOT NULL,
    yellow_cards        INT NOT NULL,
    red_cards           INT NOT NULL,
    CONSTRAINT pk_fact_discipline         PRIMARY KEY CLUSTERED (player_key),
    CONSTRAINT fk_fact_discipline_player  FOREIGN KEY (player_key) REFERENCES dbo.dim_player (player_key),
    CONSTRAINT fk_fact_discipline_club    FOREIGN KEY (club_key)   REFERENCES dbo.dim_club (club_key),
    CONSTRAINT ck_fact_discipline_nonneg  CHECK (matches_played > 0 AND minutes_played > 0 AND fouls_committed >= 0
                                                 AND fouls_suffered >= 0 AND yellow_cards >= 0 AND red_cards >= 0)
);
GO
