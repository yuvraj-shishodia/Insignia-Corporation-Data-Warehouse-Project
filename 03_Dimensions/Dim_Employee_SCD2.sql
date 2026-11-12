-- Dim_Employee_SCD2.sql
-- Employee (salesperson) dimension, SCD Type 2 on first name, last name and salesperson flag.
-- Same pattern as Dim_Customer: dedupe, fill inferred rows, expire changed, insert new/changed,
-- then create inferred members for late-arriving keys.

USE Insignia_DW;
GO

IF OBJECT_ID('dbo.Dim_Employee') IS NULL
BEGIN
    CREATE TABLE dbo.Dim_Employee (
        Employee_Key   INT IDENTITY(1,1) PRIMARY KEY,
        Employee_Id    INT           NOT NULL,
        First_Name     NVARCHAR(50)  NULL,
        Last_Name      NVARCHAR(50)  NULL,
        Is_Salesperson BIT           NULL,
        Start_Date     DATETIME      NOT NULL,
        End_Date       DATETIME      NOT NULL,
        Is_Current     BIT           NOT NULL,
        Is_Inferred    BIT           NOT NULL,
        Lineage_Id     BIGINT        NOT NULL
    );
    CREATE UNIQUE INDEX UX_Dim_Employee_Current ON dbo.Dim_Employee (Employee_Id) WHERE Is_Current = 1;

    SET IDENTITY_INSERT dbo.Dim_Employee ON;
    INSERT INTO dbo.Dim_Employee (Employee_Key, Employee_Id, First_Name, Start_Date, End_Date, Is_Current, Is_Inferred, Lineage_Id)
    VALUES (-1, -1, N'Missing employee', '1900-01-01', '9999-12-31', 1, 0, 0);
    SET IDENTITY_INSERT dbo.Dim_Employee OFF;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_Dim_Employee
    @Lineage_Id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIME = GETDATE();

    -- 1. One row per employee. First names arrive with a trailing space ("Jack "), so trim.
    SELECT Employee_Id, First_Name, Last_Name, Is_Salesperson
    INTO   #Src
    FROM (
        SELECT CAST(employee_Id AS INT)          AS Employee_Id,
               LTRIM(RTRIM(EmployeeFirstName))   AS First_Name,
               LTRIM(RTRIM(EmployeeLastName))    AS Last_Name,
               CAST(Is_Salesperson AS BIT)       AS Is_Salesperson,
               ROW_NUMBER() OVER (PARTITION BY employee_Id ORDER BY InvoiceId DESC) AS rn
        FROM   dbo.Insignia_staging_copy
        WHERE  employee_Id IS NOT NULL AND EmployeeLastName IS NOT NULL
    ) AS x
    WHERE  rn = 1;

    -- 2. Late-arriving fix-up
    UPDATE d
    SET    First_Name = s.First_Name, Last_Name = s.Last_Name, Is_Salesperson = s.Is_Salesperson,
           Is_Inferred = 0, Lineage_Id = @Lineage_Id
    FROM   dbo.Dim_Employee d
    JOIN   #Src s ON s.Employee_Id = d.Employee_Id
    WHERE  d.Is_Current = 1 AND d.Is_Inferred = 1;

    -- 3. Type 2: expire changed current versions
    UPDATE d
    SET    End_Date = @Now, Is_Current = 0, Lineage_Id = @Lineage_Id
    FROM   dbo.Dim_Employee d
    JOIN   #Src s ON s.Employee_Id = d.Employee_Id
    WHERE  d.Is_Current = 1
      AND  EXISTS (SELECT d.First_Name, d.Last_Name, d.Is_Salesperson
                   EXCEPT
                   SELECT s.First_Name, s.Last_Name, s.Is_Salesperson);

    -- 4. Insert new employees and new versions of changed ones
    INSERT INTO dbo.Dim_Employee (Employee_Id, First_Name, Last_Name, Is_Salesperson,
                                  Start_Date, End_Date, Is_Current, Is_Inferred, Lineage_Id)
    SELECT s.Employee_Id, s.First_Name, s.Last_Name, s.Is_Salesperson,
           @Now, '9999-12-31', 1, 0, @Lineage_Id
    FROM   #Src s
    LEFT JOIN dbo.Dim_Employee d ON d.Employee_Id = s.Employee_Id AND d.Is_Current = 1
    WHERE  d.Employee_Key IS NULL;

    -- 5. Late-arriving dimension: inferred members
    INSERT INTO dbo.Dim_Employee (Employee_Id, First_Name, Start_Date, End_Date, Is_Current, Is_Inferred, Lineage_Id)
    SELECT DISTINCT CAST(stg.employee_Id AS INT), N'Unknown (inferred)', @Now, '9999-12-31', 1, 1, @Lineage_Id
    FROM   dbo.Insignia_staging_copy stg
    LEFT JOIN dbo.Dim_Employee d ON d.Employee_Id = CAST(stg.employee_Id AS INT) AND d.Is_Current = 1
    WHERE  stg.employee_Id IS NOT NULL AND d.Employee_Key IS NULL;
END
GO
