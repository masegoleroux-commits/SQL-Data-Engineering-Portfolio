/* =============================================================================
   01_create_database.sql
   Creates the UCL database if it does not exist yet.
   Target: SQL Server 2017 or later
============================================================================= */

IF DB_ID(N'UCL') IS NULL
    CREATE DATABASE UCL;
GO

USE UCL;
GO
