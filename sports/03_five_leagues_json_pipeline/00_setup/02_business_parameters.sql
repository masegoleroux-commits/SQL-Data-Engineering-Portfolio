/* =============================================================================
   02_business_parameters.sql
   Business parameters and reference data the pipeline depends on.

   ops.business_parameter      numbers used by tables, analysis and model
   ops.name_stop_token         words ignored when comparing team names
   ops.team_alias_override     a data steward's manual decisions, for names
                               the automatic matching cannot settle
============================================================================= */

USE FootballLeagues;
GO

DROP TABLE IF EXISTS ops.business_parameter;
CREATE TABLE ops.business_parameter (
    param_name    VARCHAR(50)     NOT NULL PRIMARY KEY,
    param_value   DECIMAL(10, 4)  NOT NULL,
    description   VARCHAR(200)    NOT NULL
);

INSERT INTO ops.business_parameter (param_name, param_value, description) VALUES
    ('points_win',              3,    'League points for a win'),
    ('points_draw',             1,    'League points for a draw'),
    ('name_match_min_score',    1.00, 'Share of the shorter name''s words that must appear in the other name'),
    ('big_win_margin',          5,    'Goal margin that counts as a heavy win'),
    ('max_goals_modelled',      10,   'Model: highest score per team included in the probability grid'),
    ('validation_season_start', 2022, 'Model: season starting this year is used to tune shrinkage'),
    ('test_season_start',       2023, 'Model: seasons starting this year onward are the test set'),
    ('new_team_strength',       0.85, 'Model: attack and defence factor for a team with no history (usually promoted)');

DROP TABLE IF EXISTS ops.name_stop_token;
CREATE TABLE ops.name_stop_token (
    token   NVARCHAR(20)  NOT NULL PRIMARY KEY
);

-- club-type prefixes and suffixes that say nothing about which club it is
INSERT INTO ops.name_stop_token (token) VALUES
    (N'fc'), (N'cf'), (N'afc'), (N'club'), (N'de'), (N'cd'), (N'rcd'), (N'sd'), (N'ud'),
    (N'ca'), (N'rc'), (N'sc'), (N'ac'), (N'as'), (N'ss'), (N'ssc'), (N'us'), (N'uc'),
    (N'bc'), (N'vfl'), (N'vfb'), (N'tsg'), (N'sv'), (N'fsv'), (N'1'), (N'calcio');

DROP TABLE IF EXISTS ops.team_alias_override;
CREATE TABLE ops.team_alias_override (
    league_code     VARCHAR(5)     NOT NULL,
    source_name     NVARCHAR(60)   NOT NULL,
    canonical_name  NVARCHAR(60)   NOT NULL,
    reason          VARCHAR(200)   NOT NULL,
    PRIMARY KEY (league_code, source_name)
);

INSERT INTO ops.team_alias_override (league_code, source_name, canonical_name, reason) VALUES
    ('de.1', N'Bor. Mönchengladbach', N'Borussia Mönchengladbach', 'Abbreviated first word; word matching cannot see Bor. = Borussia'),
    ('it.1', N'Inter',                N'FC Internazionale Milano', 'Short name shares no word with the official name');
GO
