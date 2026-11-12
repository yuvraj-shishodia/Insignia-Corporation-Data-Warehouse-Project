-- Dim_Geography_SCD3.sql
-- Geography (city) dimension. SCD Type 3 on population: when it changes, the old value moves
-- to Previous_Population and the new one goes into Current_Population. Other attributes are Type 1.
-- Note: about a third of cities arrive with population 0, which means "not recorded".

USE Insignia_DW;
GO

IF OBJECT_ID('dbo.Dim_Geography') IS NULL
BEGIN
    CREATE TABLE dbo.Dim_Geography (
        Geography_Key           INT IDENTITY(1,1) PRIMARY KEY,
        City_Id                 INT           NOT NULL,
        City                    NVARCHAR(50)  NULL,
        State_Province          NVARCHAR(50)  NULL,
        Country                 NVARCHAR(60)  NULL,
        Continent               NVARCHAR(30)  NULL,
        Sales_Territory         NVARCHAR(50)  NULL,
        Region                  NVARCHAR(30)  NULL,
        Subregion               NVARCHAR(30)  NULL,
        Current_Population      BIGINT        NULL,
        Previous_Population     BIGINT        NULL,
        Population_Changed_Date DATETIME      NULL,
        Is_Inferred             BIT           NOT NULL,
        Lineage_Id              BIGINT        NOT NULL
    );
    CREATE UNIQUE INDEX UX_Dim_Geography_City ON dbo.Dim_Geography (City_Id);

    SET IDENTITY_INSERT dbo.Dim_Geography ON;
    INSERT INTO dbo.Dim_Geography (Geography_Key, City_Id, City, Is_Inferred, Lineage_Id)
    VALUES (-1, -1, N'Missing city', 0, 0);
    SET IDENTITY_INSERT dbo.Dim_Geography OFF;
END
GO

CREATE OR ALTER PROCEDURE dbo.usp_Load_Dim_Geography
    @Lineage_Id BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIME = GETDATE();

    -- 1. One row per city
    SELECT City_Id, City, State_Province, Country, Continent, Sales_Territory, Region, Subregion, Population
    INTO   #Src
    FROM (
        SELECT CAST(City_ID AS INT)               AS City_Id,
               LTRIM(RTRIM(City))                 AS City,
               LTRIM(RTRIM(State_Province))       AS State_Province,
               LTRIM(RTRIM(Country))              AS Country,
               LTRIM(RTRIM(Continent))            AS Continent,
               LTRIM(RTRIM(Sales_Territory))      AS Sales_Territory,
               LTRIM(RTRIM(Region))               AS Region,
               LTRIM(RTRIM(Subregion))            AS Subregion,
               CAST(Latest_Recorded_Population AS BIGINT) AS Population,
               ROW_NUMBER() OVER (PARTITION BY City_ID ORDER BY InvoiceId DESC) AS rn
        FROM   dbo.Insignia_staging_copy
        WHERE  City_ID IS NOT NULL AND City IS NOT NULL
    ) AS x
    WHERE  rn = 1;

    -- 2. Late-arriving fix-up: an inferred city gets its details and first population, no history
    UPDATE d
    SET    City = s.City, State_Province = s.State_Province, Country = s.Country, Continent = s.Continent,
           Sales_Territory = s.Sales_Territory, Region = s.Region, Subregion = s.Subregion,
           Current_Population = s.Population, Is_Inferred = 0, Lineage_Id = @Lineage_Id
    FROM   dbo.Dim_Geography d
    JOIN   #Src s ON s.City_Id = d.City_Id
    WHERE  d.Is_Inferred = 1;

    -- 3. Type 3 on population. Right-hand sides read the values from before the UPDATE,
    --    so Previous gets the old Current even though Current is changed in the same statement.
    UPDATE d
    SET    Previous_Population = d.Current_Population,
           Current_Population = s.Population,
           Population_Changed_Date = @Now,
           Lineage_Id = @Lineage_Id
    FROM   dbo.Dim_Geography d
    JOIN   #Src s ON s.City_Id = d.City_Id
    WHERE  EXISTS (SELECT d.Current_Population EXCEPT SELECT s.Population);

    -- 4. Type 1 on everything else
    UPDATE d
    SET    City = s.City, State_Province = s.State_Province, Country = s.Country, Continent = s.Continent,
           Sales_Territory = s.Sales_Territory, Region = s.Region, Subregion = s.Subregion,
           Lineage_Id = @Lineage_Id
    FROM   dbo.Dim_Geography d
    JOIN   #Src s ON s.City_Id = d.City_Id
    WHERE  EXISTS (SELECT d.City, d.State_Province, d.Country, d.Continent, d.Sales_Territory, d.Region, d.Subregion
                   EXCEPT
                   SELECT s.City, s.State_Province, s.Country, s.Continent, s.Sales_Territory, s.Region, s.Subregion);

    -- 5. New cities
    INSERT INTO dbo.Dim_Geography (City_Id, City, State_Province, Country, Continent, Sales_Territory, Region,
                                   Subregion, Current_Population, Previous_Population, Is_Inferred, Lineage_Id)
    SELECT s.City_Id, s.City, s.State_Province, s.Country, s.Continent, s.Sales_Territory, s.Region,
           s.Subregion, s.Population, NULL, 0, @Lineage_Id
    FROM   #Src s
    LEFT JOIN dbo.Dim_Geography d ON d.City_Id = s.City_Id
    WHERE  d.Geography_Key IS NULL;

    -- 6. Late-arriving dimension: inferred members
    INSERT INTO dbo.Dim_Geography (City_Id, City, Is_Inferred, Lineage_Id)
    SELECT DISTINCT CAST(stg.City_ID AS INT), N'Unknown (inferred)', 1, @Lineage_Id
    FROM   dbo.Insignia_staging_copy stg
    LEFT JOIN dbo.Dim_Geography d ON d.City_Id = CAST(stg.City_ID AS INT)
    WHERE  stg.City_ID IS NOT NULL AND d.Geography_Key IS NULL;
END
GO
