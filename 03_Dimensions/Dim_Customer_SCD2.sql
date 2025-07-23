-- SCD2_Load_Dim_Customer.sql
-- Implements SCD Type 2 for Customer Dimension from staging table

USE Insignia_DW;
GO

IF OBJECT_ID('Dim_Customer') IS NULL
BEGIN
    CREATE TABLE Dim_Customer (
        Customer_Key INT IDENTITY(1,1) PRIMARY KEY,
        Customer_ID INT,
        Customer_Name VARCHAR(100),
        Email VARCHAR(100),
        Phone VARCHAR(50),
        Address VARCHAR(200),
        Start_Date DATETIME,
        End_Date DATETIME,
        Is_Current BIT,
        Lineage_Id BIGINT
    );
END
GO

-- Step 1: Expire existing records that have changed
UPDATE Dim_Customer
SET End_Date = GETDATE(), Is_Current = 0
FROM Dim_Customer dc
JOIN Insignia_Staging_Copy stg
  ON dc.Customer_ID = stg.Customer_ID
WHERE dc.Is_Current = 1
  AND (
    ISNULL(dc.Customer_Name, '') <> ISNULL(stg.Customer_Name, '') OR
    ISNULL(dc.Email, '') <> ISNULL(stg.Email, '') OR
    ISNULL(dc.Phone, '') <> ISNULL(stg.Phone, '') OR
    ISNULL(dc.Address, '') <> ISNULL(stg.Address, '')
  );

-- Step 2: Insert new version for changed or new records
INSERT INTO Dim_Customer (
    Customer_ID, Customer_Name, Email, Phone, Address,
    Start_Date, End_Date, Is_Current, Lineage_Id
)
SELECT
    stg.Customer_ID, stg.Customer_Name, stg.Email, stg.Phone, stg.Address,
    GETDATE(), NULL, 1, @Lineage_Id
FROM Insignia_Staging_Copy stg
LEFT JOIN Dim_Customer dc
    ON stg.Customer_ID = dc.Customer_ID AND dc.Is_Current = 1
WHERE dc.Customer_ID IS NULL
   OR (
        ISNULL(dc.Customer_Name, '') <> ISNULL(stg.Customer_Name, '') OR
        ISNULL(dc.Email, '') <> ISNULL(stg.Email, '') OR
        ISNULL(dc.Phone, '') <> ISNULL(stg.Phone, '') OR
        ISNULL(dc.Address, '') <> ISNULL(stg.Address, '')
   );
