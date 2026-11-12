-- Create_Staging_Tables.sql
-- Raw tables for the two Excel files, plus the ETL's working copy.
-- Load "Insignia_staging 2.xlsx" into dbo.Insignia_staging and "Insignia_incremental 2.xlsx"
-- into dbo.Insignia_incremental (SSMS: Tasks > Import Data). The column types match what the
-- Import Wizard produces for Excel: FLOAT for numbers, NVARCHAR(255) for text. The ETL converts
-- them to proper types (INT keys, DECIMAL money) on the way into the warehouse.

USE Insignia_DW;
GO

IF OBJECT_ID('dbo.Insignia_staging') IS NULL
CREATE TABLE dbo.Insignia_staging (
    InvoiceId FLOAT, Description NVARCHAR(255), Quantity FLOAT, Unit_Price FLOAT, Tax_Rate FLOAT,
    Total_Excluding_Tax FLOAT, Tax_Amount FLOAT, Profit FLOAT, Total_Including_Tax FLOAT,
    employee_Id FLOAT, EmployeeFirstName NVARCHAR(255), EmployeeLastName NVARCHAR(255), Is_Salesperson FLOAT,
    Stock_Item_Id FLOAT, Stock_Item_Name NVARCHAR(255), Stock_ItemColor NVARCHAR(255), Stock_Item_Size NVARCHAR(255),
    Item_Size FLOAT, Stock_ItemPrice FLOAT,
    Customer_Id FLOAT, CustomerName NVARCHAR(255), CustomerCategory NVARCHAR(255), CustomerContactName NVARCHAR(255),
    CustomerPostalCode NVARCHAR(255), CustomerContactNumber FLOAT,
    City_ID FLOAT, City NVARCHAR(255), State_Province NVARCHAR(255), Country NVARCHAR(255), Continent NVARCHAR(255),
    Sales_Territory NVARCHAR(255), Region NVARCHAR(255), Subregion NVARCHAR(255), Latest_Recorded_Population FLOAT
);
GO

IF OBJECT_ID('dbo.Insignia_incremental') IS NULL
    SELECT TOP (0) * INTO dbo.Insignia_incremental FROM dbo.Insignia_staging;

-- Working copy: truncated and refilled by every ETL run. Dimension and fact tables never are.
IF OBJECT_ID('dbo.Insignia_staging_copy') IS NULL
    SELECT TOP (0) * INTO dbo.Insignia_staging_copy FROM dbo.Insignia_staging;
GO
