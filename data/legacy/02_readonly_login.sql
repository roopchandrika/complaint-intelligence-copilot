-- Day 4: least-privilege login for the copilot. SELECT only, no writes, no DDL, no procedures.
-- setup_legacy.py replaces {{RO_PASSWORD}} with LEGACY_RO_PASSWORD from .env before running this.
-- Safe to re-run: existing login/user are reused and the password is reset.

USE master;
GO

IF SUSER_ID('copilot_readonly') IS NULL
    CREATE LOGIN copilot_readonly WITH PASSWORD = '{{RO_PASSWORD}}', CHECK_POLICY = ON, DEFAULT_DATABASE = BankLegacy;
ELSE
    ALTER LOGIN copilot_readonly WITH PASSWORD = '{{RO_PASSWORD}}';
GO

USE BankLegacy;
GO

IF USER_ID('copilot_readonly') IS NULL
    CREATE USER copilot_readonly FOR LOGIN copilot_readonly;
GO

-- Allow: read every table and view in the dbo schema
GRANT SELECT ON SCHEMA::dbo TO copilot_readonly;

-- Deny: changing data, changing tables, running procedures (DENY always beats GRANT)
DENY INSERT, UPDATE, DELETE, ALTER, EXECUTE ON SCHEMA::dbo TO copilot_readonly;
DENY CREATE TABLE, CREATE VIEW, CREATE PROCEDURE, CREATE FUNCTION TO copilot_readonly;

-- Belt and braces: the built-in role that denies writes on every table in the database
ALTER ROLE db_denydatawriter ADD MEMBER copilot_readonly;
GO
