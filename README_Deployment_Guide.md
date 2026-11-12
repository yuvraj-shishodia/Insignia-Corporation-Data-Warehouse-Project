# Insignia Corporation Data Warehouse

Internship project (Celebal Technologies, Data Engineering, 2025). A SQL Server star schema and incremental ETL for Insignia Corporation, a fictional online gift retailer, built to the brief in `Problem statement and Insignia xlsx files/ProblemStatement 1.sql`.

> **Revision, November 2026.** The first upload (July 2025) referenced columns that are not in the provided data, so it did not run. The scripts were rewritten to match the data and the brief and tested end to end on SQL Server Express. The original version is in the commit history.

---

## The data

| | Insignia_staging | Insignia_incremental |
|---|---|---|
| Invoice lines (rows) | 6,549 | 5,923 |
| Invoices | 2,020 | 1,856 |
| Total including tax | 5,834,255.09 | 5,236,062.81 |

- 34 columns: invoice line measures, salesperson, stock item, customer and city.
- **Grain: one row per invoice line** (`InvoiceId` + `Stock_Item_Id`). Unique in both files; the files share no lines.
- 403 customers, 10 salespeople, 227 stock items, 653 US cities across both files.
- `Customer_Id 0` is the source's own "Unknown" customer (39% of lines). It is loaded as a normal member.
- **There is no sale date column**, so fact rows point at the date dimension's unknown member (`DateKey = -1`).
- `CustomerContactNumber` is different on every line, so it is treated as SCD Type 1. Versioning it would create one customer version per sale.
- About a third of cities have `Latest_Recorded_Population = 0`, meaning not recorded.
- `Description` always equals `Stock_Item_Name`; employee first names carry a trailing space (trimmed).

## Model

| Table | Business key | Type | Notes |
|---|---|---|---|
| `Dim_Customer` | `Customer_Id` | SCD 2 | Name, category, contact name, postal code versioned; contact number Type 1 |
| `Dim_Employee` | `Employee_Id` | SCD 2 | First name, last name, salesperson flag |
| `Dim_Geography` | `City_Id` | SCD 3 | `Current_Population` / `Previous_Population`; other columns Type 1 |
| `Dim_Product` | `Stock_Item_Id` | SCD 1 | Name, colour, size, weight, list price |
| `Dim_Date` | `DateKey` (yyyymmdd) | static | 2000–2023, fiscal year July–June, plus `-1` Unknown |
| `Fact_Sales` | `Invoice_Id` + `Product_Key` | fact | Quantity, unit price, tax rate, totals, profit |
| `ETL_Lineage` | `Lineage_Id` | audit | One row per run, columns as specified in the brief |
| `ETL_Reconciliation` | `Recon_Id` | audit | The checks each run performed |

Every dimension and fact row carries the `Lineage_Id` of the load that last wrote it. Surrogate keys are `IDENTITY` columns. There are no foreign keys (the brief allows for missing permissions); integrity comes from loading dimensions before the fact and from inferred members. A filtered unique index guarantees one current version per SCD 2 business key.

## ETL (`dbo.usp_Run_ETL`)

1. Open a lineage row (outside the transaction, so it survives a failure).
2. Truncate `Insignia_staging_copy` and refill it from the chosen source. Dimension and fact tables are never truncated.
3. Load the dimensions: deduplicate to one row per business key, fill inferred members, apply the SCD rule, insert new members, then create inferred members for keys that arrived without details (late-arriving dimensions).
4. Load the fact: look up surrogate keys, update lines that were sent again with different numbers, insert new lines.
5. Reconcile the staging copy against the fact (row count, line count, quantity, total including tax, profit, lines on a missing member). Commit if every check passes, otherwise roll back.
6. Close the lineage row with the rows written and the status.

SCDs use `UPDATE ... JOIN` and `INSERT ... LEFT JOIN ... IS NULL`. No `MERGE`, as the brief requires. Change detection uses `EXISTS (SELECT ... EXCEPT SELECT ...)`, which compares NULLs correctly.

## Deployment

1. `01_Database_Setup/Create_Database.sql`
2. `01_Database_Setup/Create_Staging_Tables.sql`, then import the two Excel files into `Insignia_staging` and `Insignia_incremental` (SSMS: Tasks > Import Data)
3. `02_Date_Dimension/Create_Date_Dim.sql`
4. Every script in `03_Dimensions/`
5. `04_Fact/Fact_Sales_Load.sql`
6. `05_Lineage/Lineage_Table_and_SP.sql`
7. `06_ETL_Scripts/Main_ETL_Procedure.sql`
8. Run the loads:
   ```sql
   EXEC dbo.usp_Run_ETL @Source = 'staging';
   EXEC dbo.usp_Run_ETL @Source = 'incremental';
   ```
9. Optional: `07_Tests/Scenario_Tests.sql` simulates SCD changes, a late-arriving customer and a correction, then rolls everything back.

## Results

| Run | Source | Rows at source | Fact rows written | Status |
|---|---|---|---|---|
| 1 | `Insignia_staging` | 6,549 | 6,549 inserted | Succeeded, all checks passed |
| 2 | `Insignia_incremental` | 5,923 | 5,923 inserted | Succeeded, all checks passed |
| 3 | `Insignia_incremental` again | 5,923 | 0 | Succeeded: reruns never duplicate |

After both loads: 12,472 fact rows, 403 customers, 10 employees, 653 cities, 227 products, 8,767 dates.

## Tech stack

SQL Server (T-SQL), SSMS, dimensional modelling, Excel source files.

## Author

**Yuvraj Shishodia**, Data Engineering Intern. [LinkedIn](https://www.linkedin.com/in/yuvraj-shishodia)
