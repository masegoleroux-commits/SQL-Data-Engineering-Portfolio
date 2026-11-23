<p align="center">
  <img src="../assets/core.png" alt="Core projects: 6 built and tested" width="900">
</p>

# Core Projects

**Status:** 6 of 6 built and tested · SQL Server 2019+ · real CSV and generated data

My six original SQL Server projects, rebuilt in 2026 to the standards in [DATA_ENGINEERING_STANDARDS.md](../DATA_ENGINEERING_STANDARDS.md). They keep their original subject and data; the code, structure, tests and documentation are new.

| # | Project | Data | What it shows |
| --- | --- | --- | --- |
| 1 | [UEFA Champions League warehouse](01_ucl_champions_league) | Real CSV | Four flat extracts to a star schema; grain checks; player similarity |
| 2 | [European top-5 leagues pipeline](02_european_top5_leagues) | 15 real CSV files | Raw, staging, clean and model layers; quarantine; Elo match model |
| 3 | [SCD Type 2 customer history](03_scd_type2_customer_history) | Generated | Type 0, 1 and 2 per column; `MERGE` with `OUTPUT`; point-in-time joins |
| 4 | [Data quality framework](04_data_quality_framework) | Generated, 56 known defects | Rules as data; safe dynamic SQL; quarantine; testing the tester |
| 5 | [Query performance tuning](05_query_performance_tuning) | 2 million generated orders | Seven slow queries measured, tuned and proven equivalent |
| 6 | [Customer analytics](06_customer_analytics) | Generated | RFM, cohorts, basket analysis, `GROUPING SETS`, churn model |

## Run a project

You need SQL Server 2019 or later (Express is enough) and SSMS.

1. Clone the repo to a path without spaces, for example `C:\SQL_Boulevard`.
2. Open the project's `run_all.sql`, switch on **Query > SQLCMD Mode**, and check `RepoPath` and `DataPath` at the top (no quotes).
3. Execute. The run stops at the first error or failed test.

## How they are tested

Syntax-checked and the file loads run. These projects use SQL Server-only features (procedures, temp tables, partitioning, plan cache), so `run_all.sql` in SSMS is their full test.

## Data

The two football projects use real public datasets. The other four use generated data. No real customer data is used.

---

[← Back to the portfolio](../README.md)
