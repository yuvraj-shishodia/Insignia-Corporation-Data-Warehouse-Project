-- Lineage_Update.sql
-- Logs the ETL operation details into the Lineage table

USE Insignia_DW;
GO

-- Create Lineage table if not exists
IF OBJECT_ID('ETL_Lineage') IS NULL
BEGIN
    CREATE TABLE ETL_Lineage (
        Lineage_Id BIGINT IDENTITY(1,1) PRIMARY KEY,
        Source_System VARCHAR(100),
        Load_Stat_Datetime DATETIME,
        Load_EndDatetime DATETIME,
        Rows_at_Source INT,
        Rows_at_destination_Fact INT,
        Load_Status BIT -- 1 = Success, 0 = Failed
    );
END
GO

-- Sample Lineage Logging Procedure
CREATE OR ALTER PROCEDURE usp_Log_Lineage
    @Source_System VARCHAR(100),
    @Load_Stat_Datetime DATETIME,
    @Load_EndDatetime DATETIME,
    @Rows_at_Source INT,
    @Rows_at_destination_Fact INT,
    @Load_Status BIT
AS
BEGIN
    INSERT INTO ETL_Lineage (
        Source_System, Load_Stat_Datetime, Load_EndDatetime,
        Rows_at_Source, Rows_at_destination_Fact, Load_Status
    )
    VALUES (
        @Source_System, @Load_Stat_Datetime, @Load_EndDatetime,
        @Rows_at_Source, @Rows_at_destination_Fact, @Load_Status
    );
END;
GO
