-- Scenario_Tests.sql
-- Proves the SCD, late-arriving and correction logic. Run it after the initial and incremental loads.
-- Everything runs inside one transaction that is rolled back at the end, so no data is changed.
-- (The two files contain no attribute changes of their own, so the changes are simulated here.)

USE Insignia_DW;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;

-- Simulated changes in the incremental file
UPDATE dbo.Insignia_incremental SET CustomerCategory = N'Gift Store'  WHERE Customer_Id = 443;          -- SCD 2
UPDATE dbo.Insignia_incremental SET EmployeeLastName = N'Potter-Lee'  WHERE employee_Id = 20;           -- SCD 2
UPDATE dbo.Insignia_incremental SET Latest_Recorded_Population = 1500 WHERE City_ID = 2815;             -- SCD 3
UPDATE dbo.Insignia_incremental SET Stock_ItemPrice = 2.75            WHERE Stock_Item_Id = 178;        -- SCD 1
UPDATE dbo.Insignia_incremental SET Quantity = 260 WHERE InvoiceId = 66804 AND Stock_Item_Id = 178;     -- correction

-- Late-arriving: a sale for customer 9999 whose details have not arrived yet
INSERT INTO dbo.Insignia_incremental
SELECT 99999, Description, Quantity, Unit_Price, Tax_Rate, Total_Excluding_Tax, Tax_Amount, Profit, Total_Including_Tax,
       employee_Id, EmployeeFirstName, EmployeeLastName, Is_Salesperson, Stock_Item_Id, Stock_Item_Name, Stock_ItemColor,
       Stock_Item_Size, Item_Size, Stock_ItemPrice, 9999, NULL, NULL, NULL, NULL, NULL,
       City_ID, City, State_Province, Country, Continent, Sales_Territory, Region, Subregion, Latest_Recorded_Population
FROM   dbo.Insignia_incremental WHERE InvoiceId = 67705 AND Stock_Item_Id = 219;

EXEC dbo.usp_Run_ETL @Source = 'incremental';

PRINT 'Customer 443: expect an expired Novelty Shop row and a current Gift Store row';
SELECT Customer_Key, Customer_Category, Start_Date, End_Date, Is_Current FROM dbo.Dim_Customer WHERE Customer_Id = 443 ORDER BY Customer_Key;
PRINT 'Employee 20: expect two versions';
SELECT Employee_Key, Last_Name, Is_Current FROM dbo.Dim_Employee WHERE Employee_Id = 20 ORDER BY Employee_Key;
PRINT 'City 2815: expect Current 1500, Previous 0';
SELECT City, Current_Population, Previous_Population FROM dbo.Dim_Geography WHERE City_Id = 2815;
PRINT 'Product 178: expect one row, List_Price 2.75';
SELECT Product_Key, List_Price FROM dbo.Dim_Product WHERE Stock_Item_Id = 178;
PRINT 'Customer 9999: expect one inferred row';
SELECT Customer_Key, Customer_Name, Is_Inferred FROM dbo.Dim_Customer WHERE Customer_Id = 9999;

-- The late customer's details arrive in the next load
UPDATE dbo.Insignia_incremental
SET    CustomerName = N'Late Toys (Testville, TX)', CustomerCategory = N'Gift Store', CustomerContactName = N'Test Person',
       CustomerPostalCode = N'75001', CustomerContactNumber = 9000099999
WHERE  Customer_Id = 9999;
EXEC dbo.usp_Run_ETL @Source = 'incremental';

PRINT 'Customer 9999: expect the same key, details filled in, Is_Inferred = 0';
SELECT Customer_Key, Customer_Name, Is_Inferred FROM dbo.Dim_Customer WHERE Customer_Id = 9999;
PRINT 'Line 66804: expect Quantity 260 (corrected in place)';
SELECT f.Invoice_Id, f.Quantity FROM dbo.Fact_Sales f JOIN dbo.Dim_Product p ON p.Product_Key = f.Product_Key
WHERE  f.Invoice_Id = 66804 AND p.Stock_Item_Id = 178;

ROLLBACK TRANSACTION;
PRINT 'Rolled back: no data was changed.';
GO
