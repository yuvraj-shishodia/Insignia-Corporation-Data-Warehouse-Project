-- SCD1_Load_Dim_Product_Channel.sql
-- Implements SCD Type 1 logic for Product and Channel dimensions

USE Insignia_DW;
GO

-- Product Dimension
IF OBJECT_ID('Dim_Product') IS NULL
BEGIN
    CREATE TABLE Dim_Product (
        Product_Key INT IDENTITY(1,1) PRIMARY KEY,
        Product_Code VARCHAR(100),
        Product_Name VARCHAR(255),
        Category VARCHAR(100),
        Price DECIMAL(18,2),
        Lineage_Id BIGINT
    );
END
GO

-- Channel Dimension
IF OBJECT_ID('Dim_Channel') IS NULL
BEGIN
    CREATE TABLE Dim_Channel (
        Channel_Key INT IDENTITY(1,1) PRIMARY KEY,
        Channel_Code VARCHAR(100),
        Channel_Name VARCHAR(255),
        Lineage_Id BIGINT
    );
END
GO

-- SCD1 Logic for Product
MERGE Dim_Product AS target
USING (
    SELECT DISTINCT Product_Code, Product_Name, Category, Price FROM Insignia_Staging_Copy
) AS source
ON target.Product_Code = source.Product_Code
WHEN MATCHED AND (
    ISNULL(target.Product_Name, '') <> ISNULL(source.Product_Name, '') OR
    ISNULL(target.Category, '') <> ISNULL(source.Category, '') OR
    ISNULL(target.Price, 0) <> ISNULL(source.Price, 0)
) THEN
    UPDATE SET 
        Product_Name = source.Product_Name,
        Category = source.Category,
        Price = source.Price,
        Lineage_Id = @Lineage_Id
WHEN NOT MATCHED THEN
    INSERT (Product_Code, Product_Name, Category, Price, Lineage_Id)
    VALUES (source.Product_Code, source.Product_Name, source.Category, source.Price, @Lineage_Id);
GO

-- SCD1 Logic for Channel
MERGE Dim_Channel AS target
USING (
    SELECT DISTINCT Channel_Code, Channel_Name FROM Insignia_Staging_Copy
) AS source
ON target.Channel_Code = source.Channel_Code
WHEN MATCHED AND (
    ISNULL(target.Channel_Name, '') <> ISNULL(source.Channel_Name, '')
) THEN
    UPDATE SET Channel_Name = source.Channel_Name,
               Lineage_Id = @Lineage_Id
WHEN NOT MATCHED THEN
    INSERT (Channel_Code, Channel_Name, Lineage_Id)
    VALUES (source.Channel_Code, source.Channel_Name, @Lineage_Id);
