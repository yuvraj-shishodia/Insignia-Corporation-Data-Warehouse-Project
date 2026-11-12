-- Main_ETL_Procedure.sql
-- Runs one full ETL cycle, following the steps in the problem statement:
--   EXEC dbo.usp_Run_ETL @Source = 'staging';      -- initial load from Insignia_staging
--   EXEC dbo.usp_Run_ETL @Source = 'incremental';  -- incremental load from Insignia_incremental
-- Steps: open lineage -> truncate and refill the staging copy -> dimensions -> fact ->
--        reconciliation -> commit (all checks pass) or roll back -> close lineage.

USE Insignia_DW;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Run_ETL
    @Source VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Source NOT IN ('staging', 'incremental')
        THROW 50001, 'Use @Source = ''staging'' or ''incremental''.', 1;

    DECLARE @Lineage_Id BIGINT, @Rows_at_Source INT, @Inserted INT = 0, @Updated INT = 0,
            @Source_System VARCHAR(100) = CASE @Source WHEN 'staging' THEN 'dbo.Insignia_staging'
                                                                      ELSE 'dbo.Insignia_incremental' END;

    -- A table variable keeps its rows after a ROLLBACK, so failed checks are still recorded
    DECLARE @Recon TABLE (Check_Name VARCHAR(100), Expected DECIMAL(19,2), Actual DECIMAL(19,2));

    SET @Rows_at_Source = CASE @Source WHEN 'staging' THEN (SELECT COUNT(*) FROM dbo.Insignia_staging)
                                                      ELSE (SELECT COUNT(*) FROM dbo.Insignia_incremental) END;

    -- Lineage row is written outside the transaction, so it survives a failed run
    EXEC dbo.usp_Lineage_Start @Source_System, @Rows_at_Source, @Lineage_Id OUTPUT;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Steps 1, 4, 5: refill the working copy. Dimension and fact tables are never truncated.
        TRUNCATE TABLE dbo.Insignia_staging_copy;
        IF @Source = 'staging'
            INSERT INTO dbo.Insignia_staging_copy SELECT * FROM dbo.Insignia_staging;
        ELSE
            INSERT INTO dbo.Insignia_staging_copy SELECT * FROM dbo.Insignia_incremental;

        -- Steps 2 and 6: dimensions first
        EXEC dbo.usp_Load_Dim_Product   @Lineage_Id;
        EXEC dbo.usp_Load_Dim_Geography @Lineage_Id;
        EXEC dbo.usp_Load_Dim_Employee  @Lineage_Id;
        EXEC dbo.usp_Load_Dim_Customer  @Lineage_Id;

        -- Steps 3 and 6: fact last
        EXEC dbo.usp_Load_Fact_Sales @Lineage_Id, @Inserted OUTPUT, @Updated OUTPUT;

        -- Reconciliation: everything in the staging copy must be in the fact, with the same totals
        WITH Stg AS (
            SELECT COUNT(*)                                            AS Lines,
                   SUM(CAST(Quantity AS INT))                          AS Qty,
                   SUM(CAST(Total_Including_Tax AS DECIMAL(18,2)))     AS Incl,
                   SUM(CAST(Profit AS DECIMAL(18,2)))                  AS Profit
            FROM   dbo.Insignia_staging_copy
        ),
        Fct AS (
            SELECT COUNT(*) AS Lines, SUM(f.Quantity) AS Qty, SUM(f.Total_Including_Tax) AS Incl, SUM(f.Profit) AS Profit,
                   SUM(CASE WHEN -1 IN (f.Customer_Key, f.Employee_Key, f.Geography_Key, f.Product_Key) THEN 1 ELSE 0 END) AS On_Missing
            FROM   dbo.Fact_Sales f
            JOIN   dbo.Dim_Product p ON p.Product_Key = f.Product_Key
            JOIN  (SELECT DISTINCT CAST(InvoiceId AS INT) AS Invoice_Id, CAST(Stock_Item_Id AS INT) AS Stock_Item_Id
                   FROM dbo.Insignia_staging_copy) s
                   ON s.Invoice_Id = f.Invoice_Id AND s.Stock_Item_Id = p.Stock_Item_Id
        )
        INSERT INTO @Recon (Check_Name, Expected, Actual)
        SELECT v.Check_Name, v.Expected, v.Actual
        FROM   Stg CROSS JOIN Fct
        CROSS APPLY (VALUES ('Rows: source = staging copy',        @Rows_at_Source, Stg.Lines),
                            ('Lines: staging copy = fact',         Stg.Lines,       Fct.Lines),
                            ('SUM(Quantity)',                      Stg.Qty,         Fct.Qty),
                            ('SUM(Total_Including_Tax)',           Stg.Incl,        Fct.Incl),
                            ('SUM(Profit)',                        Stg.Profit,      Fct.Profit),
                            ('Fact lines on a missing (-1) member', 0,              Fct.On_Missing)
                    ) AS v (Check_Name, Expected, Actual);

        IF EXISTS (SELECT 1 FROM @Recon WHERE NOT EXISTS (SELECT Expected INTERSECT SELECT Actual))
        BEGIN
            ROLLBACK TRANSACTION;
            SET @Inserted = 0; SET @Updated = 0;
        END
        ELSE
            COMMIT TRANSACTION;

        INSERT INTO dbo.ETL_Reconciliation (Lineage_Id, Check_Name, Expected, Actual, Passed)
        SELECT @Lineage_Id, Check_Name, Expected, Actual,
               CASE WHEN EXISTS (SELECT Expected INTERSECT SELECT Actual) THEN 1 ELSE 0 END
        FROM   @Recon;

        DECLARE @Ok BIT = CASE WHEN EXISTS (SELECT 1 FROM dbo.ETL_Reconciliation
                                            WHERE Lineage_Id = @Lineage_Id AND Passed = 0) THEN 0 ELSE 1 END;
        DECLARE @Written INT = @Inserted + @Updated;
        EXEC dbo.usp_Lineage_End @Lineage_Id, @Written, @Ok;

        SELECT l.Lineage_Id, l.Source_System, l.Rows_at_Source, l.Rows_at_destination_Fact, l.Load_Status,
               @Inserted AS Fact_Rows_Inserted, @Updated AS Fact_Rows_Updated,
               DATEDIFF(MILLISECOND, l.Load_Stat_Datetime, l.Load_EndDatetime) AS Duration_ms
        FROM   dbo.ETL_Lineage l WHERE l.Lineage_Id = @Lineage_Id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        EXEC dbo.usp_Lineage_End @Lineage_Id, 0, 0;
        THROW;
    END CATCH
END
GO
