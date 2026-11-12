-- Lineage_Table_and_SP.sql
-- One lineage row per ETL run: source, start/end time, rows at source, rows written to the fact,
-- and status. Its Lineage_Id is stamped on every dimension and fact row the run writes.
-- The reconciliation table stores the checks each run performed.

USE Insignia_DW;
GO

IF OBJECT_ID('dbo.ETL_Lineage') IS NULL
CREATE TABLE dbo.ETL_Lineage (
    Lineage_Id               BIGINT IDENTITY(1,1) PRIMARY KEY,
    Source_System            VARCHAR(100) NOT NULL,
    Load_Stat_Datetime       DATETIME     NOT NULL,
    Load_EndDatetime         DATETIME     NULL,
    Rows_at_Source           INT          NULL,
    Rows_at_destination_Fact INT          NULL,
    Load_Status              BIT          NULL     -- NULL = running, 1 = succeeded, 0 = failed
);
GO

IF OBJECT_ID('dbo.ETL_Reconciliation') IS NULL
CREATE TABLE dbo.ETL_Reconciliation (
    Recon_Id     INT IDENTITY(1,1) PRIMARY KEY,
    Lineage_Id   BIGINT        NOT NULL,
    Check_Name   VARCHAR(100)  NOT NULL,
    Expected     DECIMAL(19,2) NULL,
    Actual       DECIMAL(19,2) NULL,
    Passed       BIT           NOT NULL
);
GO

-- Opens a run before any work starts and hands back its Lineage_Id
CREATE OR ALTER PROCEDURE dbo.usp_Lineage_Start
    @Source_System  VARCHAR(100),
    @Rows_at_Source INT,
    @Lineage_Id     BIGINT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dbo.ETL_Lineage (Source_System, Load_Stat_Datetime, Rows_at_Source)
    VALUES (@Source_System, GETDATE(), @Rows_at_Source);
    SET @Lineage_Id = SCOPE_IDENTITY();
END;
GO

-- Closes the run with its outcome
CREATE OR ALTER PROCEDURE dbo.usp_Lineage_End
    @Lineage_Id               BIGINT,
    @Rows_at_destination_Fact INT,
    @Load_Status              BIT
AS
BEGIN
    SET NOCOUNT ON;
    UPDATE dbo.ETL_Lineage
    SET    Load_EndDatetime = GETDATE(),
           Rows_at_destination_Fact = @Rows_at_destination_Fact,
           Load_Status = @Load_Status
    WHERE  Lineage_Id = @Lineage_Id;
END;
GO
