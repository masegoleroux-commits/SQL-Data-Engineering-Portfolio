<p align="center">
  <img src="../assets/sports.png" alt="Sports: 10 built and tested" width="900">
</p>

# Sports Projects

**Status:** 10 of 10 built and tested · SQL Server · real public CSV and JSON

Real public sports data, from every World Cup match since 1930 to the 2023 Formula 1 season. Each project loads the files as delivered (bronze), cleans them with every step logged and counted (silver), models them as a star schema (gold), and reconciles the result against the source before any analysis.

| # | Project | Data | What it shows |
| --- | --- | --- | --- |
| 1 | [World Cup data warehouse](01_world_cup_warehouse) | Every match since 1930 | Medallion layers, audit trail, match-outcome model |
| 2 | [NBA Elo history](02_nba_elo_history) | 1946 to 2015 | Mirrored-row de-duplication, SCD2 franchises, win probability |
| 3 | [Five leagues JSON pipeline](03_five_leagues_json_pipeline) | JSON | `OPENJSON`, team-name matching, Poisson score model |
| 4 | [NBA player impact](04_nba_player_impact) | CSV | Sample-size rules, unpivot, z-scores, similarity search |
| 5 | [Fantasy football points engine](05_fantasy_points_engine) | CSV | A rules engine that reproduces published points exactly |
| 6 | [Boston Marathon 2016](06_marathon_results) | CSV | Time parsing, missing timing mats, anomaly detection |
| 7 | [Premier League transfer market](07_transfer_market) | CSV | Fee parsing, learned club aliases, two-sided transfers |
| 8 | [Match tracking data](08_match_tracking_data) | 5 Hz tracking CSV | Multi-row headers, speeds, sprints, possession inference |
| 9 | [Formula 1 2023 season](09_formula1_season) | CSV | Conformed dimensions, points engine, title clinch |
| 10 | [Olympic medal table](10_olympic_medal_table) | 1992 to 2016 | Grain fix for team events, reference reconciliation, forecast |

## Run a project

You need SQL Server 2019 or later (Express is enough) and SSMS.

1. Clone the repo to a path without spaces, for example `C:\SQL_Boulevard`.
2. Open the project's `run_all.sql`, switch on **Query > SQLCMD Mode**, and check `RepoPath` and `DataPath` at the top (no quotes).
3. Execute. The run stops at the first error or failed test.

The SQL Server service reads the data files, so use a folder it can open. `C:\SQL_Boulevard` works; your user profile or OneDrive usually does not.

## How they are tested

Every script is parsed as T-SQL, translated to PostgreSQL and run end to end, including all tests.

## Data

All ten projects use real public datasets. Each project README names its source and licence.

---

[← Back to the portfolio](../README.md)
