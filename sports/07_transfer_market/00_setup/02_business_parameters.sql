/* =============================================================================
   02_business_parameters.sql
============================================================================= */

USE TransferMarket;
GO

DROP TABLE IF EXISTS ops.business_parameter;
CREATE TABLE ops.business_parameter (
    param_name    VARCHAR(50)     NOT NULL PRIMARY KEY,
    param_value   DECIMAL(10, 4)  NOT NULL,
    description   VARCHAR(200)    NOT NULL
);

INSERT INTO ops.business_parameter (param_name, param_value, description) VALUES
    ('alias_min_evidence',  3,     'Mirrored transfers needed before a short club name is linked to a full name'),
    ('alias_min_share',     0.90,  'Share of the evidence the top candidate must have'),
    ('fee_tolerance',       0.001, 'Allowed gap (EUR millions) between the parsed fee and the source''s own cleaned fee'),
    ('big_fee_millions',    50,    'Fee that counts as a major signing'),
    ('base_year',           1993,  'Year used as 100 in the fee inflation index');

-- values that appear where a club name should be, but are not clubs
DROP TABLE IF EXISTS ops.non_club_value;
CREATE TABLE ops.non_club_value (
    value_text  NVARCHAR(60)  NOT NULL PRIMARY KEY
);

INSERT INTO ops.non_club_value VALUES
    (N'Without Club'), (N'Retired'), (N'Unknown'), (N'Career break'), (N'Banned');

-- the source mixes detailed positions with broad ones ('midfield')
DROP TABLE IF EXISTS ops.position_group;
CREATE TABLE ops.position_group (
    source_position  VARCHAR(40)  NOT NULL PRIMARY KEY,
    position_group   VARCHAR(15)  NOT NULL
);

INSERT INTO ops.position_group VALUES
    ('Goalkeeper', 'Goalkeeper'),
    ('Centre-Back', 'Defender'), ('Right-Back', 'Defender'), ('Left-Back', 'Defender'), ('defence', 'Defender'),
    ('Central Midfield', 'Midfielder'), ('Defensive Midfield', 'Midfielder'), ('Attacking Midfield', 'Midfielder'),
    ('Right Midfield', 'Midfielder'), ('Left Midfield', 'Midfielder'), ('midfield', 'Midfielder'),
    ('Centre-Forward', 'Forward'), ('Second Striker', 'Forward'), ('Right Winger', 'Forward'),
    ('Left Winger', 'Forward'), ('attack', 'Forward');
GO
