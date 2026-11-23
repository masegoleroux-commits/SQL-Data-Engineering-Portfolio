/* =============================================================================
   05_indexes.sql
   Supporting indexes for the club-level queries in analysis/.

   The clustered primary keys already cover player-level lookups. These
   nonclustered indexes lead on club_key and INCLUDE the measures each club
   query reads, so club roll-ups are answered from the index alone
   (no key lookups back to the clustered index).
============================================================================= */

USE UCL;
GO

CREATE NONCLUSTERED INDEX ix_fact_attacking_club
    ON dbo.fact_attacking (club_key)
    INCLUDE (assists, dribbles, offsides, matches_played);

CREATE NONCLUSTERED INDEX ix_fact_defending_club
    ON dbo.fact_defending (club_key)
    INCLUDE (balls_recovered, tackles, tackles_won, clearances_attempted, matches_played);

CREATE NONCLUSTERED INDEX ix_fact_distribution_club
    ON dbo.fact_distribution (club_key)
    INCLUDE (passes_attempted, passes_completed, crosses_attempted, crosses_completed);

CREATE NONCLUSTERED INDEX ix_fact_discipline_club
    ON dbo.fact_discipline (club_key)
    INCLUDE (fouls_committed, yellow_cards, red_cards, minutes_played);

-- dim_player is filtered by position in most positional breakdowns
CREATE NONCLUSTERED INDEX ix_dim_player_position
    ON dbo.dim_player (position)
    INCLUDE (player_name, club_name);
GO
