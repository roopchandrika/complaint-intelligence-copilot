-- Day 4: schema of the fictional bank's legacy case system (SQL Server / T-SQL).
-- Deliberately "legacy-style": short cryptic names, code tables, a status history with a current flag.
-- Run by setup_legacy.py as the admin login (sa). Safe to re-run: it rebuilds the tables.

IF DB_ID('BankLegacy') IS NULL CREATE DATABASE BankLegacy;
GO

USE BankLegacy;
GO

DROP TABLE IF EXISTS dbo.TBL_CASE_STATUS;
DROP TABLE IF EXISTS dbo.TBL_CASE;
DROP TABLE IF EXISTS dbo.REF_STAT_CD;
GO

-- Lookup of status codes
CREATE TABLE dbo.REF_STAT_CD (
    STAT_CD   CHAR(3)       NOT NULL PRIMARY KEY,   -- e.g. 'OPN'
    STAT_DESC VARCHAR(50)   NOT NULL                -- e.g. 'Open'
);

-- One row per customer complaint case
CREATE TABLE dbo.TBL_CASE (
    CASE_ID   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,   -- internal case number
    CMPL_ID   BIGINT        NOT NULL UNIQUE,            -- CFPB complaint ID
    PRD_DESC  NVARCHAR(100) NULL,                       -- product
    ISS_DESC  NVARCHAR(255) NULL,                       -- issue
    CO_NM     NVARCHAR(255) NULL,                       -- company name as received
    ST_CD     CHAR(2)       NULL,                       -- customer state
    RCV_DT    DATE          NOT NULL,                   -- date received
    CHNL      VARCHAR(30)   NULL,                       -- submission channel
    NARR_TXT  NVARCHAR(4000) NULL                       -- customer narrative (truncated to 4000 chars)
);

-- One row per status change (history). CUR_FLG = 1 marks the current status of a case.
CREATE TABLE dbo.TBL_CASE_STATUS (
    STAT_ID   INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CASE_ID   INT          NOT NULL REFERENCES dbo.TBL_CASE (CASE_ID),
    STAT_CD   CHAR(3)      NOT NULL REFERENCES dbo.REF_STAT_CD (STAT_CD),
    ASGN_TEAM VARCHAR(50)  NULL,                        -- team owning the case at that time
    UPD_TS    DATETIME2(0) NOT NULL,                    -- when the status changed
    CUR_FLG   BIT          NOT NULL DEFAULT 0           -- 1 = current status row
);
GO

CREATE INDEX IX_CASE_STATUS_CASE ON dbo.TBL_CASE_STATUS (CASE_ID, CUR_FLG);
CREATE INDEX IX_CASE_STATUS_CODE ON dbo.TBL_CASE_STATUS (STAT_CD, CUR_FLG);
CREATE INDEX IX_CASE_CO_DT       ON dbo.TBL_CASE (CO_NM, RCV_DT);
GO

INSERT INTO dbo.REF_STAT_CD (STAT_CD, STAT_DESC) VALUES
    ('OPN', 'Open'),
    ('INV', 'Under investigation'),
    ('ESC', 'Escalated'),
    ('LGL', 'Legal hold'),
    ('CLS', 'Closed');
GO
