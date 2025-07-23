-- SCD3_Load_Dim_Geography.sql
-- Implements SCD Type 3 for Geography Dimension (tracking historical and current population)

USE Insignia_DW;
GO

IF OBJECT_ID('Dim_Geography') IS NULL
BEGIN
    CREATE TABLE Dim_Geography (
        Geography_Key INT IDENTITY(1,1) PRIMARY KEY,
        Country VARCHAR(100),
        State VARCHAR(100),
        City VARCHAR(100),
        Current_Population INT,
        Previous_Population INT,
        Lineage_Id BIGINT
    );
END
GO

-- Step 1: Update population change (SCD Type 3)
UPDATE Dim_Geography
SET Previous_Population = Current_Population,
    Current_Population = stg.Population,
    Lineage_Id = @Lineage_Id
FROM Dim_Geography dim
JOIN Insignia_Staging_Copy stg
  ON dim.City = stg.City AND dim.State = stg.State AND dim.Country = stg.Country
WHERE ISNULL(dim.Current_Population, 0) <> ISNULL(stg.Population, 0);

-- Step 2: Insert new geography records if not exists
INSERT INTO Dim_Geography (Country, State, City, Current_Population, Previous_Population, Lineage_Id)
SELECT stg.Country, stg.State, stg.City, stg.Population, NULL, @Lineage_Id
FROM Insignia_Staging_Copy stg
LEFT JOIN Dim_Geography dim
    ON dim.City = stg.City AND dim.State = stg.State AND dim.Country = stg.Country
WHERE dim.City IS NULL;
