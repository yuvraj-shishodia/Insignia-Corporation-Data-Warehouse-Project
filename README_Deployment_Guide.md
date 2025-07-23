# 📦 Insignia Corporation Data Warehouse Project

A comprehensive Data Engineering project simulating a real-world business scenario for Insignia Corporation — a fictional online gift retailer. The goal was to build a robust data warehouse solution to enable modern data analysis and reporting capabilities.

---

## 🔍 Project Overview

This project involved designing and implementing an **enterprise-grade data warehouse** using SQL Server. Tasks included:

- Building a **star schema** data model from raw transactional data.
- Implementing **ETL pipelines** to load dimension and fact tables.
- Supporting **Slowly Changing Dimensions (SCD Type 1, 2, and 3)**.
- Handling **incremental loads**, **late arriving dimensions**, and **data reconciliation**.
- Creating a **date dimension** covering years 2000 to 2023 with fiscal calendar logic (July to June).
- Designing a **lineage tracking** mechanism to monitor ETL health and row-level metrics.

---

## ⚙️ Deployment Steps

1. Run `01_Database_Setup/Create_Database.sql` to create and switch to the `InsigniaDB`.
2. Run `02_Date_Dimension/Create_Date_Dim.sql` to create and populate the Date Dimension.
3. Load all scripts under `03_Dimensions/` to create and configure dimension tables:
   - Customer (SCD Type 2)
   - Employee (SCD Type 2)
   - Geography (SCD Type 3 on Population)
   - Product & Channel (SCD Type 1)
4. Load `04_Fact/Fact_Sales_Load.sql` to load Fact data from dimension keys.
5. Create the lineage tracking structure using `05_Lineage/Lineage_Table_and_SP.sql`.
6. Run `06_ETL_Scripts/Main_ETL_Procedure.sql` to perform a full ETL cycle.
7. Load sample Excel/CSV data into `Insignia_staging` and `Insignia_incremental`.

> 💡 Note: All SQL scripts begin with `USE InsigniaDB;` to maintain correct context.

---

## 📌 Key Features

- ⭐ Star Schema Model
- 🔁 SCD Implementation (Types 1, 2, 3)
- 📅 Fully functional Date Dimension with Fiscal Calendar Support
- ⚙️ ETL pipelines using T-SQL and staging architecture
- 🕵️ Lineage and audit tracking system (`usp_Log_Lineage`)
- 🔁 Incremental Load Strategy with reconciliation checks
- 🚧 No use of `MERGE`; SCDs handled via `LEFT JOIN`, `UPDATE`, and `INSERT`

---

## 🛠️ Tech Stack

- **SQL Server (T-SQL)**
- **SSMS (SQL Server Management Studio)**
- **Dimensional Modeling**
- **ETL Architecture**
- **Excel/CSV for initial data**

---

## 📈 Learning Outcomes

- Gained hands-on experience in **data warehousing concepts** including dimension modeling and SCDs.
- Designed and deployed **incremental ETL pipelines** from scratch.
- Developed critical thinking to simulate **enterprise data challenges** like late-arriving data and audit logging.
- Learned and followed **SQL Server best practices** and naming conventions.

---

## 👨‍💻 Author

**Yuvraj Shishodia**  
_Data Engineering Intern | Passionate about building scalable data systems_

Feel free to connect with me on [LinkedIn](https://www.linkedin.com/in/yuvraj-shishodia).

---
