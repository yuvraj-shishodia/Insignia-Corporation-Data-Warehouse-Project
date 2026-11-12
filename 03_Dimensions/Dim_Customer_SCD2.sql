-- Dim_Customer_SCD2.sql
-- Customer dimension. SCD Type 2 on name, category, contact name and postal code.
-- Contact number is Type 1 (overwritten, not versioned): the source sends a different
-- number on every sales line, so versioning it would create one "customer version" per sale.
-- Late-arriving members: a Customer_Id seen without its details gets an inferred row,
-- which is filled in place (not versioned) once the details arrive.

USE Insignia_DW;
GO

IF OBJECT_ID('dbo.Dim_Customer') IS NULL
BEGIN
    CREATE TABLE dbo.Dim_Customer (
        Customer_Key      INT IDENTITY(1,1) PRIMARY KEY,   -- surrogate key
        Customer_Id       INT           NOT NULL,           -- business key from the source
        Customer_Name     NVARCHAR(100) NULL,
        Customer_Category NVARCHAR(50)  NULL,
        Contact_Name      NVARCHAR(100) NULL,
        Postal_Code       NVARCHAR(10)  NULL,
        Contact_Number    VARCHAR(20)   NULL,
        Start_Date        DATETIME      NOT NULL,
        End_Date          DATETIME      NOT NULL,           -- 9999-12-31 while current
        Is_Current        BIT           NOT NULL,
        Is_Inferred       BIT           NOT NULL,
        Lineage_Id        BIGINT        NOT NULL            -- last load that wrote this row
    );
    -- Guarantees at most one current version per customer
    CREATE UNIQUE INDEX UX_Dim_Customer_Current ON dbo.Dim_Customer (Customer_Id) WHERE Is_Current = 1;

    SET IDENTITY_INSERT dbo.Dim_Customer ON;
    INSERT INTO dbo.Dim_Customer (Customer_Key, Customer_Id, Customer_Name, Start_Date, End_Date, Is_Current, Is_Inferred, Lineage_Id)
    VALUES (-1, -1, N'Missing customer', '1900-01-01', '9999-12-31', 1, 0, 0);
    SET IDENTITY_INSERT dbo.Dim_Customer OFF;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_Dim_Customer
    @Lineage_Id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIME = GETDATE();

    -- 1. One row per customer. The staging copy repeats customer details on every sales line;
    --    keep the latest line (highest InvoiceId) for each customer.
    SELECT Customer_Id, Customer_Name, Customer_Category, Contact_Name, Postal_Code, Contact_Number
    INTO   #Src
    FROM (
        SELECT CAST(Customer_Id AS INT)           AS Customer_Id,
               LTRIM(RTRIM(CustomerName))         AS Customer_Name,
               LTRIM(RTRIM(CustomerCategory))     AS Customer_Category,
               LTRIM(RTRIM(CustomerContactName))  AS Contact_Name,
               LTRIM(RTRIM(CustomerPostalCode))   AS Postal_Code,
               CONVERT(VARCHAR(20), CONVERT(BIGINT, CustomerContactNumber)) AS Contact_Number,
               ROW_NUMBER() OVER (PARTITION BY Customer_Id
                                  ORDER BY InvoiceId DESC, CustomerContactNumber DESC) AS rn
        FROM   dbo.Insignia_staging_copy
        WHERE  Customer_Id IS NOT NULL AND CustomerName IS NOT NULL
    ) AS x
    WHERE  rn = 1;

    -- 2. Late-arriving fix-up: fill an inferred placeholder in place, no new version
    UPDATE d
    SET    Customer_Name = s.Customer_Name, Customer_Category = s.Customer_Category,
           Contact_Name = s.Contact_Name, Postal_Code = s.Postal_Code,
           Contact_Number = s.Contact_Number, Is_Inferred = 0, Lineage_Id = @Lineage_Id
    FROM   dbo.Dim_Customer d
    JOIN   #Src s ON s.Customer_Id = d.Customer_Id
    WHERE  d.Is_Current = 1 AND d.Is_Inferred = 1;

    -- 3. Type 2: expire the current version when a tracked attribute changed.
    --    EXISTS (... EXCEPT ...) is a NULL-safe "is anything different?"
    UPDATE d
    SET    End_Date = @Now, Is_Current = 0, Lineage_Id = @Lineage_Id
    FROM   dbo.Dim_Customer d
    JOIN   #Src s ON s.Customer_Id = d.Customer_Id
    WHERE  d.Is_Current = 1
      AND  EXISTS (SELECT d.Customer_Name, d.Customer_Category, d.Contact_Name, d.Postal_Code
                   EXCEPT
                   SELECT s.Customer_Name, s.Customer_Category, s.Contact_Name, s.Postal_Code);

    -- 4. Insert new customers and the new version of changed ones.
    --    After step 3 a changed customer has no current row, so one LEFT JOIN finds both.
    INSERT INTO dbo.Dim_Customer (Customer_Id, Customer_Name, Customer_Category, Contact_Name, Postal_Code,
                                  Contact_Number, Start_Date, End_Date, Is_Current, Is_Inferred, Lineage_Id)
    SELECT s.Customer_Id, s.Customer_Name, s.Customer_Category, s.Contact_Name, s.Postal_Code,
           s.Contact_Number, @Now, '9999-12-31', 1, 0, @Lineage_Id
    FROM   #Src s
    LEFT JOIN dbo.Dim_Customer d ON d.Customer_Id = s.Customer_Id AND d.Is_Current = 1
    WHERE  d.Customer_Key IS NULL;

    -- 5. Type 1: overwrite the contact number on every version of the customer
    UPDATE d
    SET    Contact_Number = s.Contact_Number, Lineage_Id = @Lineage_Id
    FROM   dbo.Dim_Customer d
    JOIN   #Src s ON s.Customer_Id = d.Customer_Id
    WHERE  EXISTS (SELECT d.Contact_Number EXCEPT SELECT s.Contact_Number);

    -- 6. Late-arriving dimension: a sales line whose customer has no details yet gets an
    --    inferred member, so its fact row is kept instead of dropped.
    INSERT INTO dbo.Dim_Customer (Customer_Id, Customer_Name, Start_Date, End_Date, Is_Current, Is_Inferred, Lineage_Id)
    SELECT DISTINCT CAST(stg.Customer_Id AS INT), N'Unknown (inferred)', @Now, '9999-12-31', 1, 1, @Lineage_Id
    FROM   dbo.Insignia_staging_copy stg
    LEFT JOIN dbo.Dim_Customer d ON d.Customer_Id = CAST(stg.Customer_Id AS INT) AND d.Is_Current = 1
    WHERE  stg.Customer_Id IS NOT NULL AND d.Customer_Key IS NULL;
END
GO
