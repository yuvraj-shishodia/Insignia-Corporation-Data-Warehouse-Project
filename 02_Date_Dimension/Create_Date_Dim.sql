-- Date_Dimension_Load.sql
-- Creates and populates the Date Dimension with fiscal year logic

USE Insignia_DW;
GO

IF OBJECT_ID('Dim_Date') IS NOT NULL
    DROP TABLE Dim_Date;
GO

CREATE TABLE Dim_Date (
    DateKey INT PRIMARY KEY,
    [Date] DATE,
    Day_Number INT,
    Month_Name VARCHAR(20),
    Short_Month CHAR(3),
    Calendar_Month_Number INT,
    Calendar_Year INT,
    Fiscal_Month_Number INT,
    Fiscal_Year INT,
    Week_Number INT
);
GO

DECLARE @StartDate DATE = '2000-01-01';
DECLARE @EndDate DATE = '2023-12-31';

WHILE @StartDate <= @EndDate
BEGIN
    DECLARE @DateKey INT = CAST(CONVERT(CHAR(8), @StartDate, 112) AS INT);
    DECLARE @DayNumber INT = DAY(@StartDate);
    DECLARE @MonthName VARCHAR(20) = DATENAME(MONTH, @StartDate);
    DECLARE @ShortMonth CHAR(3) = LEFT(DATENAME(MONTH, @StartDate), 3);
    DECLARE @CalendarMonth INT = MONTH(@StartDate);
    DECLARE @CalendarYear INT = YEAR(@StartDate);
    DECLARE @WeekNumber INT = DATEPART(WEEK, @StartDate);

    DECLARE @FiscalYear INT, @FiscalMonth INT;
    IF @CalendarMonth >= 7
    BEGIN
        SET @FiscalYear = @CalendarYear + 1;
        SET @FiscalMonth = @CalendarMonth - 6;
    END
    ELSE
    BEGIN
        SET @FiscalYear = @CalendarYear;
        SET @FiscalMonth = @CalendarMonth + 6;
    END

    INSERT INTO Dim_Date
    VALUES (
        @DateKey,
        @StartDate,
        @DayNumber,
        @MonthName,
        @ShortMonth,
        @CalendarMonth,
        @CalendarYear,
        @FiscalMonth,
        @FiscalYear,
        @WeekNumber
    );

    SET @StartDate = DATEADD(DAY, 1, @StartDate);
END
GO
