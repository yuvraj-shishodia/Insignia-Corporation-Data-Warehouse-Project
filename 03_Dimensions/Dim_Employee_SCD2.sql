-- SCD2_Load_Dim_Employee.sql
-- Implements SCD Type 2 for Employee Dimension from staging table

USE Insignia_DW;
GO

IF OBJECT_ID('Dim_Employee') IS NULL
BEGIN
    CREATE TABLE Dim_Employee (
        Employee_Key INT IDENTITY(1,1) PRIMARY KEY,
        Employee_ID INT,
        Employee_Name VARCHAR(100),
        Email VARCHAR(100),
        Designation VARCHAR(100),
        Department VARCHAR(100),
        Start_Date DATETIME,
        End_Date DATETIME,
        Is_Current BIT,
        Lineage_Id BIGINT
    );
END
GO

-- Step 1: Expire existing records that have changed
UPDATE Dim_Employee
SET End_Date = GETDATE(), Is_Current = 0
FROM Dim_Employee de
JOIN Insignia_Staging_Copy stg
  ON de.Employee_ID = stg.Employee_ID
WHERE de.Is_Current = 1
  AND (
    ISNULL(de.Employee_Name, '') <> ISNULL(stg.Employee_Name, '') OR
    ISNULL(de.Email, '') <> ISNULL(stg.Email, '') OR
    ISNULL(de.Designation, '') <> ISNULL(stg.Designation, '') OR
    ISNULL(de.Department, '') <> ISNULL(stg.Department, '')
  );

-- Step 2: Insert new version for changed or new records
INSERT INTO Dim_Employee (
    Employee_ID, Employee_Name, Email, Designation, Department,
    Start_Date, End_Date, Is_Current, Lineage_Id
)
SELECT
    stg.Employee_ID, stg.Employee_Name, stg.Email, stg.Designation, stg.Department,
    GETDATE(), NULL, 1, @Lineage_Id
FROM Insignia_Staging_Copy stg
LEFT JOIN Dim_Employee de
    ON stg.Employee_ID = de.Employee_ID AND de.Is_Current = 1
WHERE de.Employee_ID IS NULL
   OR (
        ISNULL(de.Employee_Name, '') <> ISNULL(stg.Employee_Name, '') OR
        ISNULL(de.Email, '') <> ISNULL(stg.Email, '') OR
        ISNULL(de.Designation, '') <> ISNULL(stg.Designation, '') OR
        ISNULL(de.Department, '') <> ISNULL(stg.Department, '')
   );
