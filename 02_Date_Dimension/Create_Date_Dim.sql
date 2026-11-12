-- Create_Date_Dim.sql
-- Date dimension for 2000-01-01 to 2023-12-31 with the company's July-June fiscal year.
-- Built set-based in one INSERT, and only when empty, so rerunning the script never drops it.

USE Insignia_DW;
GO

IF OBJECT_ID('dbo.Dim_Date') IS NULL
CREATE TABLE dbo.Dim_Date (
    DateKey               INT         NOT NULL PRIMARY KEY,  -- yyyymmdd, e.g. 20230701
    [Date]                DATE        NULL,
    Day_Number            TINYINT     NULL,                  -- day of the month
    Month_Name            VARCHAR(10) NOT NULL,
    Short_Month           CHAR(3)     NOT NULL,
    Calendar_Month_Number TINYINT     NULL,
    Calendar_Year         SMALLINT    NULL,
    Fiscal_Month_Number   TINYINT     NULL,                  -- July = 1 ... June = 12
    Fiscal_Year           SMALLINT    NULL,                  -- named by the year it ends: Jul 2022 - Jun 2023 = FY2023
    Week_Number           TINYINT     NULL                   -- DATEPART(WEEK), depends on SET DATEFIRST
);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Date WHERE DateKey > 0)
BEGIN
    DECLARE @Start DATE = '2000-01-01', @End DATE = '2023-12-31';

    WITH Numbers AS (
        SELECT TOP (DATEDIFF(DAY, @Start, @End) + 1)
               ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS n
        FROM sys.all_objects a CROSS JOIN sys.all_objects b
    ),
    Dates AS (
        SELECT DATEADD(DAY, n, @Start) AS d FROM Numbers
    )
    INSERT INTO dbo.Dim_Date (DateKey, [Date], Day_Number, Month_Name, Short_Month, Calendar_Month_Number,
                              Calendar_Year, Fiscal_Month_Number, Fiscal_Year, Week_Number)
    SELECT CONVERT(INT, CONVERT(CHAR(8), d, 112)),
           d,
           DAY(d),
           DATENAME(MONTH, d),
           LEFT(DATENAME(MONTH, d), 3),
           MONTH(d),
           YEAR(d),
           (MONTH(d) + 5) % 12 + 1,                              -- 7 -> 1, 12 -> 6, 1 -> 7, 6 -> 12
           YEAR(d) + CASE WHEN MONTH(d) >= 7 THEN 1 ELSE 0 END,
           DATEPART(WEEK, d)
    FROM Dates;
END
GO

-- Unknown member: a fact row without a usable date points here instead of being dropped.
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Date WHERE DateKey = -1)
    INSERT INTO dbo.Dim_Date (DateKey, Month_Name, Short_Month) VALUES (-1, 'Unknown', 'UNK');
GO
