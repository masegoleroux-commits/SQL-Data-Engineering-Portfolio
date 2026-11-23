/* =============================================================================
   07_business_parameters.sql
   Thresholds used by the analysis and ML scripts, kept in one table instead
   of being typed into each query.

   A scout who wants "minimum 360 minutes" instead of 270 changes one row.
   Every leaderboard and the similarity model pick up the new value on the
   next run, and the table records who changed it and when.
============================================================================= */

USE UCL;
GO

DROP TABLE IF EXISTS dbo.business_parameter;
CREATE TABLE dbo.business_parameter (
    param_name      VARCHAR(50)     NOT NULL,
    param_value     DECIMAL(10, 2)  NOT NULL,
    unit            VARCHAR(20)     NOT NULL,
    description     NVARCHAR(200)   NOT NULL,
    updated_by      SYSNAME         NOT NULL CONSTRAINT df_business_parameter_by DEFAULT SUSER_SNAME(),
    updated_at      DATETIME2(0)    NOT NULL CONSTRAINT df_business_parameter_at DEFAULT SYSDATETIME(),
    CONSTRAINT pk_business_parameter PRIMARY KEY (param_name),
    CONSTRAINT ck_business_parameter_nonneg CHECK (param_value >= 0)
);
GO

INSERT INTO dbo.business_parameter (param_name, param_value, unit, description)
VALUES
    ('min_matches',            5,   'matches',  N'Minimum appearances before a per-match rate is ranked'),
    ('min_minutes',            270, 'minutes',  N'Minimum minutes before a per-90 rate is ranked (three full games)'),
    ('min_passes',             100, 'passes',   N'Minimum passes attempted before completion % is ranked'),
    ('min_crosses',            10,  'crosses',  N'Minimum crosses attempted before cross completion % is ranked'),
    ('min_tackles',            10,  'tackles',  N'Minimum tackles before tackle success % is ranked'),
    ('min_dribbles',           20,  'dribbles', N'Minimum dribbles for the dribble-vs-fouls comparison'),
    ('ever_present_share',     0.8, 'ratio',    N'Share of the maximum appearances that counts as an ever-present'),
    ('outperform_margin_pts',  5,   'points',   N'Points above the positional pass completion average to be flagged'),
    ('similar_players_top_n',  10,  'players',  N'Number of players returned by the similarity search');
GO

SELECT param_name, param_value, unit, description
FROM dbo.business_parameter
ORDER BY param_name;
GO
