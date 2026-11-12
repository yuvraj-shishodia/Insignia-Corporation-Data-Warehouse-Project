-- Dim_Product_SCD1.sql
-- Product (stock item) dimension, SCD Type 1: changes overwrite the row, no history.
-- Written with UPDATE + LEFT JOIN / INSERT; the brief does not allow MERGE.
-- The selling price and tax rate of each sale stay on the fact table, so overwriting
-- the list price here never changes past revenue.

USE Insignia_DW;
GO

IF OBJECT_ID('dbo.Dim_Product') IS NULL
BEGIN
    CREATE TABLE dbo.Dim_Product (
        Product_Key     INT IDENTITY(1,1) PRIMARY KEY,
        Stock_Item_Id   INT            NOT NULL,
        Stock_Item_Name NVARCHAR(100)  NULL,
        Color           NVARCHAR(20)   NULL,
        Size            NVARCHAR(20)   NULL,
        Typical_Weight  DECIMAL(10,3)  NULL,    -- the source column is called Item_Size
        List_Price      DECIMAL(18,2)  NULL,
        Is_Inferred     BIT            NOT NULL,
        Lineage_Id      BIGINT         NOT NULL
    );
    CREATE UNIQUE INDEX UX_Dim_Product_Item ON dbo.Dim_Product (Stock_Item_Id);

    SET IDENTITY_INSERT dbo.Dim_Product ON;
    INSERT INTO dbo.Dim_Product (Product_Key, Stock_Item_Id, Stock_Item_Name, Is_Inferred, Lineage_Id)
    VALUES (-1, -1, N'Missing product', 0, 0);
    SET IDENTITY_INSERT dbo.Dim_Product OFF;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_Dim_Product
    @Lineage_Id BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. One row per stock item
    SELECT Stock_Item_Id, Stock_Item_Name, Color, Size, Typical_Weight, List_Price
    INTO   #Src
    FROM (
        SELECT CAST(Stock_Item_Id AS INT)            AS Stock_Item_Id,
               LTRIM(RTRIM(Stock_Item_Name))         AS Stock_Item_Name,
               LTRIM(RTRIM(Stock_ItemColor))         AS Color,
               LTRIM(RTRIM(Stock_Item_Size))         AS Size,
               CAST(Item_Size AS DECIMAL(10,3))      AS Typical_Weight,
               CAST(Stock_ItemPrice AS DECIMAL(18,2)) AS List_Price,
               ROW_NUMBER() OVER (PARTITION BY Stock_Item_Id ORDER BY InvoiceId DESC) AS rn
        FROM   dbo.Insignia_staging_copy
        WHERE  Stock_Item_Id IS NOT NULL AND Stock_Item_Name IS NOT NULL
    ) AS x
    WHERE  rn = 1;

    -- 2. Type 1: overwrite changed rows (this also fills inferred placeholders)
    UPDATE d
    SET    Stock_Item_Name = s.Stock_Item_Name, Color = s.Color, Size = s.Size,
           Typical_Weight = s.Typical_Weight, List_Price = s.List_Price,
           Is_Inferred = 0, Lineage_Id = @Lineage_Id
    FROM   dbo.Dim_Product d
    JOIN   #Src s ON s.Stock_Item_Id = d.Stock_Item_Id
    WHERE  d.Is_Inferred = 1
       OR  EXISTS (SELECT d.Stock_Item_Name, d.Color, d.Size, d.Typical_Weight, d.List_Price
                   EXCEPT
                   SELECT s.Stock_Item_Name, s.Color, s.Size, s.Typical_Weight, s.List_Price);

    -- 3. New products
    INSERT INTO dbo.Dim_Product (Stock_Item_Id, Stock_Item_Name, Color, Size, Typical_Weight, List_Price, Is_Inferred, Lineage_Id)
    SELECT s.Stock_Item_Id, s.Stock_Item_Name, s.Color, s.Size, s.Typical_Weight, s.List_Price, 0, @Lineage_Id
    FROM   #Src s
    LEFT JOIN dbo.Dim_Product d ON d.Stock_Item_Id = s.Stock_Item_Id
    WHERE  d.Product_Key IS NULL;

    -- 4. Late-arriving dimension: inferred members
    INSERT INTO dbo.Dim_Product (Stock_Item_Id, Stock_Item_Name, Is_Inferred, Lineage_Id)
    SELECT DISTINCT CAST(stg.Stock_Item_Id AS INT), N'Unknown (inferred)', 1, @Lineage_Id
    FROM   dbo.Insignia_staging_copy stg
    LEFT JOIN dbo.Dim_Product d ON d.Stock_Item_Id = CAST(stg.Stock_Item_Id AS INT)
    WHERE  stg.Stock_Item_Id IS NOT NULL AND d.Product_Key IS NULL;
END
GO
