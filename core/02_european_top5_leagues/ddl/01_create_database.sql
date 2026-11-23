/* =============================================================================
   01_create_database.sql
   Creates the EuroLeagues database and one schema per data stage.

   Stage   Schema  Holds
   -----   ------  ---------------------------------------------------------
   0       cfg     Reference data and business parameters
   1       raw     The CSV files exactly as delivered, every column as text
   2       stg     Typed copy of the latest delivery of each file
   3       cln     Cleaned, standardised and validated rows + cleaning log
   4       dw      Star schema for reporting
   5       ml      Features, Elo ratings, model predictions and evaluation
   6       rpt     Reporting views

   Target: SQL Server 2019 or later (Express edition is fine).
============================================================================= */

IF DB_ID(N'EuroLeagues') IS NULL
    CREATE DATABASE EuroLeagues;
GO

USE EuroLeagues;
GO

IF SCHEMA_ID(N'cfg') IS NULL EXEC (N'CREATE SCHEMA cfg AUTHORIZATION dbo;');
IF SCHEMA_ID(N'raw') IS NULL EXEC (N'CREATE SCHEMA raw AUTHORIZATION dbo;');
IF SCHEMA_ID(N'stg') IS NULL EXEC (N'CREATE SCHEMA stg AUTHORIZATION dbo;');
IF SCHEMA_ID(N'cln') IS NULL EXEC (N'CREATE SCHEMA cln AUTHORIZATION dbo;');
IF SCHEMA_ID(N'dw')  IS NULL EXEC (N'CREATE SCHEMA dw  AUTHORIZATION dbo;');
IF SCHEMA_ID(N'ml')  IS NULL EXEC (N'CREATE SCHEMA ml  AUTHORIZATION dbo;');
IF SCHEMA_ID(N'rpt') IS NULL EXEC (N'CREATE SCHEMA rpt AUTHORIZATION dbo;');
GO
