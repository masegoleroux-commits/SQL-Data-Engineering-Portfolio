<p align="center">
  <img src="../../assets/sports.png" alt="Sports projects" width="900">
</p>

# World Cup Data Warehouse

A SQL Server warehouse built from every FIFA World Cup match since 1930: 30 tournaments (men's and women's), 1,248 matches, 3,637 goals and 10,401 players. Raw CSV files move through bronze, silver and gold layers into a tested star schema, which then feeds an analysis layer and a small match-prediction model written entirely in T-SQL.

**Skills shown:** medallion layering, data cleaning with an audit trail, quarantine of bad rows, star schema design, surrogate keys, layer-to-layer reconciliation, business parameters, window functions, set-based model training and evaluation.

<!-- <img src="screenshots/01_run_all.png" width="800" height="400" alt="Run all"> -->

## The problem

The source data is detailed but uneven. Stage names are spelt two ways, some birth dates are the word "not available", one score uses a different separator from the other 1,247, and penalty shootouts mean a match can be both a draw and a win depending on the question. Reports written straight against the CSV files would each handle these differently and disagree with each other. The warehouse handles them once, records what it changed, and proves the numbers still add up.

## Pipeline

```
data/raw/*.csv
   │  BULK INSERT, every column as text
   ▼
bronze   exact copy of the files, row counts logged
   │  type, standardise, check, quarantine
   ▼
silver   typed tables with keys   ──►  ops.cleaning_log, ops.quarantine
   │  surrogate keys, facts at a fixed grain
   ▼
gold     star schema + v_team_tournament
   │
   ├──► 04_quality   13 checks, the run stops if any fail
   ├──► 05_analysis  all-time table, scorers, late goals, host effect, shootouts
   └──► 06_ml        pre-tournament strength model, trained then tested
```

## Data stages in detail

### Bronze: land it as it is
`01_bronze/01_load_bronze.sql` loads the eight CSV files into tables where every column is `NVARCHAR`. Nothing is converted, so a bad value can never stop the load and the original text is always available for comparison. Each load writes its row count to `ops.load_log`.

### Silver: clean it and say what changed
`02_silver/01_build_silver.sql` converts types, applies the cleaning rules and logs a count for each one:

| Step | Rule | Rows |
|---|---|---|
| 1 | Stage names standardised (`quarter-final` → `quarter-finals`) | 48 |
| 2 | Birth date `not available` → NULL | 77 |
| 3 | Gender derived from the tournament name | 8 |
| 4 | Shootout matches get a separate regulation result | 43 |
| 5 | Score separator standardised (hyphen → en dash) | 1 |
| 6 | Score text still disagreeing with the numeric score → quarantine | 0 |

When a match fails a rule, its goals and cards are quarantined with it (`PARENT_MATCH_QUARANTINED`), so no fact row is ever left pointing at a missing match.

<!-- <img src="screenshots/02_cleaning_log.png" width="800" height="400" alt="Cleaning log"> -->

### Gold: model it for questions
`03_gold/01_build_star_schema.sql` builds four dimensions and four facts. The key design choice is `fact_team_match`, which stores every match twice, once from each team's side. A question like "how many goals has Brazil scored" becomes a simple `SUM(goals_for)` instead of a pair of CASE expressions over home and away columns.

<!-- <img src="screenshots/04_star_schema.png" width="800" height="400" alt="Star schema"> -->

| Table | Grain |
|---|---|
| `fact_match` | one match |
| `fact_team_match` | one team in one match |
| `fact_goal` | one goal |
| `fact_booking` | one card |

Full column notes and grain definitions are in [`docs/data_dictionary.md`](docs/data_dictionary.md).

## Quality checks

`04_quality/01_quality_checks.sql` runs 13 checks and raises an error if any fail, which stops `run_all.sql`.

- **Reconciliation:** every bronze row is either in silver or in quarantine; every silver row reaches gold; `fact_team_match` has exactly two rows per match.
- **Business rules:** goal records add up to each final score; goals credited to a team match its `goals_for`; every shootout was level on the score; every knockout match has a team going through; each tournament winner won its last match.
- **Domain:** every stage name exists in `dim_stage`; no birth dates in the future or before 1880.

The knockout check found four drawn knockout matches from 1934 and 1938. They are correct: before penalty shootouts existed, those games were replayed. The check now allows a draw when the match is flagged as replayed.

<!-- <img src="screenshots/03_quality_checks.png" width="800" height="400" alt="Quality checks"> -->

## Business parameters

Thresholds live in `ops.business_parameter`, not in the queries:

| Parameter | Value | Used by |
|---|---|---|
| `points_win` / `points_draw` | 3 / 1 | All-time table and model features |
| `min_matches_ranking` | 10 | Teams shown in the all-time table |
| `min_goals_scorer` | 5 | Players shown in the scorer list |
| `late_goal_minute` | 80 | Late-goal analysis |
| `new_team_ppm` | 1.00 | Model strength for a team with no history |
| `host_advantage_ppm` | 0.50 | Model boost for the host nation |
| `test_from_year` | 2010 | Model train / test split |

Changing a value and re-running `05_analysis` or `06_ml` changes the result with no code edits.

## Analysis

`05_analysis/01_analysis.sql` answers six questions:

1. All-time men's table under today's 3-1-0 points system
2. All-time scorers by gender, with penalty counts
3. Share of goals scored late, by decade
4. Win rate of host nations at home compared with their record elsewhere
5. Penalty shootout records by team
6. How far each team went at each tournament

<!-- <img src="screenshots/05_all_time_table.png" width="800" height="400" alt="All time table"> -->

## Match prediction model

`06_ml/01_match_outcome_model.sql` predicts whether a match ends in a home win, draw or away win on the score.

**Features.** Each team's strength is its points per match in earlier World Cups of the same gender, plus a bonus if it is the host. Only earlier tournaments are used, so the model never sees the result it is predicting.

**Training.** The model predicts a draw when the two strengths are within a band of each other. Every band width from 0.00 to 1.50 is scored against the 856 matches before 2010 and the most accurate one is kept.

**Testing.** The chosen band is applied without change to the 392 matches from 2010 onward.

| Metric | Value |
|---|---|
| Chosen draw band | 0.00 |
| Train accuracy | 49.8% |
| Test accuracy | 56.1% |
| Baseline: always pick the home team (test) | 44.9% |

The model beats the baseline by about 11 points on unseen tournaments. It also learned something real: the best band is zero, meaning it never predicts a draw. Draws happen in about one match in five, but they are hard to see coming from history alone, so guessing the stronger side wins more often than any draw rule does. The confusion matrix at the end of the script shows exactly where it goes wrong.

<!-- <img src="screenshots/06_model_metrics.png" width="800" height="400" alt="Model metrics"> -->

## How to run

1. Install SQL Server (Express is fine) and SSMS.
2. Copy this folder to a path without spaces, for example `C:\SQL_Boulevard\sports\01_world_cup_warehouse`.
3. Open `run_all.sql` in SSMS and switch on **Query → SQLCMD Mode**.
4. Edit the two `:setvar` lines if your path is different. Do not put quotes around the paths.
5. Press **F5**. The run creates the `WorldCup` database and stops at the first failed check.

Each script can also be opened and run on its own once the earlier stages have run.

## Folder structure

```
01_world_cup_warehouse/
├── 00_setup/       database, schemas, ops tables, business parameters
├── 01_bronze/      raw CSV load
├── 02_silver/      typing, cleaning, quarantine
├── 03_gold/        star schema and mart view
├── 04_quality/     reconciliation and business-rule checks
├── 05_analysis/    six analysis queries
├── 06_ml/          match prediction model
├── data/raw/       source CSV files
├── docs/           data dictionary, grain, data findings
├── screenshots/    SSMS screenshots
└── run_all.sql     runs everything in order
```

## Git

```bash
git add sports/01_world_cup_warehouse
git commit -m "Add World Cup warehouse: bronze/silver/gold, quality checks, prediction model"
git push
```

## Data licence

Data from [The Fjelstul World Cup Database](https://github.com/jfjelstul/worldcup) © Joshua C. Fjelstul, Ph.D., used under CC-BY-SA 4.0.

---

[← Back to Sports projects](../README.md) · [Portfolio home](../../README.md)
