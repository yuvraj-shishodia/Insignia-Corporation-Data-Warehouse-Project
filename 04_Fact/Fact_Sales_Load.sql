-- Fact_Sales_Load.sql
-- Populates the Fact_Sales table after dimension loads

USE Insignia_DW;
GO

-- Create Fact_Sales table if not exists
IF OBJECT_ID('Fact_Sales') IS NULL
BEGIN
    CREATE TABLE Fact_Sales (
        Sales_Key INT IDENTITY(1,1) PRIMARY KEY,
        Product_Key INT,
        Customer_Key INT,
        Employee_Key INT,
        Geography_Key INT,
        Channel_Key INT,
        DateKey INT,
        Units_Sold INT,
        Revenue DECIMAL(18,2),
        Discount DECIMAL(18,2),
        Lineage_Id BIGINT
        -- No FOREIGN KEYs enforced, but keys must align logically
    );
END
GO

-- Insert Data Into Fact_Sales
INSERT INTO Fact_Sales (
    Product_Key, Customer_Key, Employee_Key, Geography_Key, Channel_Key, DateKey,
    Units_Sold, Revenue, Discount, Lineage_Id
)
SELECT
    P.Product_Key,
    C.Customer_Key,
    E.Employee_Key,
    G.Geography_Key,
    CH.Channel_Key,
    D.DateKey,
    S.Units_Sold,
    S.Revenue,
    S.Discount,
    @Lineage_Id
FROM Insignia_Staging_Copy S
INNER JOIN Dim_Product P ON S.Product_Code = P.Product_Code
INNER JOIN Dim_Customer C ON S.Customer_Id = C.Customer_Id AND C.Is_Current = 1
INNER JOIN Dim_Employee E ON S.Employee_Id = E.Employee_Id AND E.Is_Current = 1
INNER JOIN Dim_Geography G ON S.Pincode = G.Pincode AND G.Is_Current = 1
INNER JOIN Dim_Channel CH ON S.Channel_Code = CH.Channel_Code
INNER JOIN Dim_Date D ON CAST(S.Sales_Date AS DATE) = D.Date;

-- Ensure integrity: join only on current records for SCD2/3 dimensions
GO
