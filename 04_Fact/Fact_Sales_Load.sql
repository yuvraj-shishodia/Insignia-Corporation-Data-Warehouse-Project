-- Fact_Sales_Load.sql
-- Sales fact. Grain: one row per invoice line (InvoiceId + Stock_Item_Id), which is unique in both files.
-- Loaded last, after every dimension, so surrogate-key lookups always find a row.
-- Rerunning a load never duplicates rows: existing lines are only updated when their numbers changed
-- (the brief says previously sent data sometimes needs corrections), new lines are inserted.

USE Insignia_DW;
GO

IF OBJECT_ID('dbo.Fact_Sales') IS NULL
BEGIN
    CREATE TABLE dbo.Fact_Sales (
        Sales_Key           BIGINT IDENTITY(1,1) PRIMARY KEY,
        Invoice_Id          INT           NOT NULL,   -- degenerate dimension
        DateKey             INT           NOT NULL,   -- -1: the source files carry no sale date
        Customer_Key        INT           NOT NULL,
        Employee_Key        INT           NOT NULL,
        Geography_Key       INT           NOT NULL,
        Product_Key         INT           NOT NULL,
        Quantity            INT           NOT NULL,
        Unit_Price          DECIMAL(18,2) NOT NULL,
        Tax_Rate            DECIMAL(5,2)  NOT NULL,
        Total_Excluding_Tax DECIMAL(18,2) NOT NULL,
        Tax_Amount          DECIMAL(18,2) NOT NULL,
        Total_Including_Tax DECIMAL(18,2) NOT NULL,
        Profit              DECIMAL(18,2) NOT NULL,
        Lineage_Id          BIGINT        NOT NULL
        -- No FOREIGN KEY constraints (the brief allows for missing permissions);
        -- referential integrity comes from loading dimensions first and the inferred members.
    );
    CREATE UNIQUE INDEX UX_Fact_Sales_Line ON dbo.Fact_Sales (Invoice_Id, Product_Key);
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_Fact_Sales
    @Lineage_Id    BIGINT,
    @Rows_Inserted INT OUTPUT,
    @Rows_Updated  INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Resolve surrogate keys. The source has no sale date, so the current dimension version
    --    at load time is the one in effect for the sale. -1 is only a safety net for a NULL key.
    SELECT CAST(s.InvoiceId AS INT)                       AS Invoice_Id,
           -1                                             AS DateKey,
           COALESCE(c.Customer_Key, -1)                   AS Customer_Key,
           COALESCE(e.Employee_Key, -1)                   AS Employee_Key,
           COALESCE(g.Geography_Key, -1)                  AS Geography_Key,
           COALESCE(p.Product_Key, -1)                    AS Product_Key,
           CAST(s.Quantity AS INT)                        AS Quantity,
           CAST(s.Unit_Price AS DECIMAL(18,2))            AS Unit_Price,
           CAST(s.Tax_Rate AS DECIMAL(5,2))               AS Tax_Rate,
           CAST(s.Total_Excluding_Tax AS DECIMAL(18,2))   AS Total_Excluding_Tax,
           CAST(s.Tax_Amount AS DECIMAL(18,2))            AS Tax_Amount,
           CAST(s.Total_Including_Tax AS DECIMAL(18,2))   AS Total_Including_Tax,
           CAST(s.Profit AS DECIMAL(18,2))                AS Profit
    INTO   #New
    FROM   dbo.Insignia_staging_copy s
    LEFT JOIN dbo.Dim_Customer  c ON c.Customer_Id   = CAST(s.Customer_Id AS INT)   AND c.Is_Current = 1
    LEFT JOIN dbo.Dim_Employee  e ON e.Employee_Id   = CAST(s.employee_Id AS INT)   AND e.Is_Current = 1
    LEFT JOIN dbo.Dim_Geography g ON g.City_Id       = CAST(s.City_ID AS INT)
    LEFT JOIN dbo.Dim_Product   p ON p.Stock_Item_Id = CAST(s.Stock_Item_Id AS INT);

    -- 2. Corrections: a line that was sent before with different numbers is updated in place.
    --    Only the measures change. The dimension keys stay as first loaded, so a re-sent line
    --    keeps pointing at the customer/employee version that was current when the sale arrived.
    UPDATE f
    SET    Quantity = n.Quantity, Unit_Price = n.Unit_Price, Tax_Rate = n.Tax_Rate,
           Total_Excluding_Tax = n.Total_Excluding_Tax, Tax_Amount = n.Tax_Amount,
           Total_Including_Tax = n.Total_Including_Tax, Profit = n.Profit, Lineage_Id = @Lineage_Id
    FROM   dbo.Fact_Sales f
    JOIN   #New n ON n.Invoice_Id = f.Invoice_Id AND n.Product_Key = f.Product_Key
    WHERE  EXISTS (SELECT f.Quantity, f.Unit_Price, f.Tax_Rate, f.Total_Excluding_Tax,
                          f.Tax_Amount, f.Total_Including_Tax, f.Profit
                   EXCEPT
                   SELECT n.Quantity, n.Unit_Price, n.Tax_Rate, n.Total_Excluding_Tax,
                          n.Tax_Amount, n.Total_Including_Tax, n.Profit);
    SET @Rows_Updated = @@ROWCOUNT;

    -- 3. New lines only
    INSERT INTO dbo.Fact_Sales (Invoice_Id, DateKey, Customer_Key, Employee_Key, Geography_Key, Product_Key,
                                Quantity, Unit_Price, Tax_Rate, Total_Excluding_Tax, Tax_Amount,
                                Total_Including_Tax, Profit, Lineage_Id)
    SELECT n.Invoice_Id, n.DateKey, n.Customer_Key, n.Employee_Key, n.Geography_Key, n.Product_Key,
           n.Quantity, n.Unit_Price, n.Tax_Rate, n.Total_Excluding_Tax, n.Tax_Amount,
           n.Total_Including_Tax, n.Profit, @Lineage_Id
    FROM   #New n
    LEFT JOIN dbo.Fact_Sales f ON f.Invoice_Id = n.Invoice_Id AND f.Product_Key = n.Product_Key
    WHERE  f.Sales_Key IS NULL;
    SET @Rows_Inserted = @@ROWCOUNT;
END
GO
