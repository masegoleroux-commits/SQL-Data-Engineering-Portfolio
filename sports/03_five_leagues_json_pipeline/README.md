<p align="center">
  <img src="../../assets/sports.png" alt="Sports projects" width="900">
</p>

# Five Leagues JSON Pipeline

A SQL Server pipeline that ingests six seasons (2019-20 to 2024-25) of the Premier League, La Liga, Bundesliga, Serie A and Ligue 1 from JSON files, resolves inconsistent team names automatically, and builds a tested star schema with league tables, analysis and a Poisson goals model. 10,808 matches, 137 clubs, 30 source documents.

**Skills shown:** JSON ingestion with `OPENJSON` and `JSON_VALUE`, envelope/payload landing pattern, entity resolution with explainable scoring, data steward overrides, handling incomplete and cancelled records, star schema, round-robin integrity checks, a train / validation / test model in T-SQL.

<!-- <img src="screenshots/01_run_all.png" width="800" height="400" alt="Run all"> -->

## The problem

The data comes as nested JSON, one document per league per season, the way a football data API delivers it. Three things make it hard to use as it is:

1. **The same club has different names in different seasons.** "Manchester City" in one file, "Manchester City FC" in the next. "Atlético Madrid" and "Club Atlético de Madrid". "Inter" and "FC Internazionale Milano". 39 name variants across 137 clubs. Without fixing this, every multi-season query splits these clubs in two.
2. **The documents are not uniform.** 680 played matches have no half-time score, 101 Ligue 1 matches were cancelled in March 2020, three results were awarded by the league rather than played, and the 2024-25 La Liga and Serie A files stop before the final round.
3. **Text keys.** Matches have no ID. A key has to be built and proven unique.

## Pipeline

```
data/source_json/*.json        30 files, as published by openfootball
   │  tools/build_landing_file.py wraps each file in an envelope
   ▼
data/raw/api_landing.jsonl     one JSON document per line
   │  BULK INSERT, one NVARCHAR(MAX) column per line
   ▼
bronze   api_landing                 raw documents, never edited
   │  ISJSON check, OPENJSON shredding
   ▼
silver   source_file, match_raw      one row per document / per match, all text
   │  entity resolution
   ▼
silver   team_name_candidate, team_alias
   │  types, statuses, canonical names
   ▼
silver   match                       ──►  ops.cleaning_log, ops.quarantine
   ▼
gold     dim_league, dim_season, dim_team, fact_match, fact_team_match, v_league_table
   │
   ├──► 04_quality   12 checks
   ├──► 05_analysis  champions, home advantage, goals, comebacks, heavy wins, trends
   └──► 06_ml        Poisson goals model
```

## Data stages in detail

### Landing and bronze
Each source file is wrapped in an envelope that records where it came from, then written as one line:

```json
{"source_file":"en.1_2023-24.json","source_url":"https://github.com/...","league_code":"en.1",
 "season":"2023-24","payload":{"name":"English Premier League 2023/24","matches":[...]}}
```

`01_bronze/01_load_bronze.sql` loads all 30 lines with a single `BULK INSERT` into one `NVARCHAR(MAX)` column. A tab is used as the field terminator because compact JSON never contains a raw tab, so each line lands whole. `CODEPAGE = '65001'` keeps names like Köln and Atlético intact.

### Silver step 1: shred the JSON
`02_silver/01_shred_json.sql` checks every document with `ISJSON`, then uses `OPENJSON ... WITH` to turn the envelope into `silver.source_file` and the `matches` array into `silver.match_raw`. Scores are read with array paths such as `'$.score.ft[0]'`. Missing paths come back as NULL instead of failing, which is what lets non-uniform documents load cleanly.

<!-- <img src="screenshots/02_openjson.png" width="800" height="400" alt="Openjson"> -->

### Silver step 2: team name resolution`02_silver/02_resolve_team_names.sql` decides which names belong to the same club, using two kinds of evidence:

**Name evidence.** Names are lower-cased, accents removed with `TRANSLATE`, and club-type words dropped (`FC`, `CF`, `Club`, `de`, `Calcio` ...; the list lives in `ops.name_stop_token`). The remaining words are split with `STRING_SPLIT`. The score is the share of the shorter name's words found in the longer name.

| Pair | Words compared | Score |
|---|---|---|
| Real Betis / Real Betis Balompié | {real, betis} vs {real, betis, balompie} | 1.00 |
| CD Alavés / Deportivo Alavés | {alaves} vs {deportivo, alaves} | 1.00 |
| Real Madrid / Real Betis | {real, madrid} vs {real, betis} | 0.50 |

**Schedule evidence.** One club cannot appear under two names in the same season. Any pair that shares a season is rejected, however similar the names are. This stops "FC Barcelona" matching "Espanyol Barcelona" and "AS Roma" matching "Lazio Roma", both of which score 1.00 on words alone.

A pair is accepted when the score reaches `name_match_min_score` and the names never share a season. The canonical name is the most recently used one. Every comparison and its decision is kept in `silver.team_name_candidate`, so each merge can be explained.

Two cases cannot be solved from words: "Bor. Mönchengladbach" (an abbreviation) and "Inter" (a nickname). They sit in `ops.team_alias_override`, a table a data steward maintains, and an override always wins.

**Result:** 138 pairs compared, 37 merged automatically, 2 by override, 0 false merges.

<!-- <img src="screenshots/03_name_resolution.png" width="800" height="400" alt="Name resolution"> -->

### Silver step 3: typed matches
`02_silver/03_build_match.sql` applies types and canonical names and gives every match a status:

| Status | Meaning | Matches |
|---|---|---|
| played | normal result | 10,684 |
| awarded | result set by the league; counts in the table but not in goal statistics | 3 |
| cancelled | never played (Ligue 1 stopped in March 2020) | 101 |
| result missing | scheduled, no score in the source (last round of 2024-25 La Liga and Serie A) | 20 |

Full cleaning log:

| Step | Rule | Rows |
|---|---|---|
| 1 | Landed documents that are not valid JSON → quarantine | 0 |
| 2 | Matches shredded from JSON arrays | 10,808 |
| 3 | Team name pairs compared | 138 |
| 4 | Name variants merged automatically | 37 |
| 5 | Name variants merged by steward override | 2 |
| 6 | Match sides renamed to the canonical name | 2,108 |
| 7 | Cancelled matches flagged | 101 |
| 8 | Matches with no result flagged | 20 |
| 9 | Awarded results flagged | 3 |
| 10 | Played matches with no half-time score | 680 |
| 11 | Matches with no kick-off time | 101 |
| 12 | `Matchday 12` text converted to a number | 10,808 |

<!-- <img src="screenshots/04_cleaning_log.png" width="800" height="400" alt="Cleaning log"> -->

### Gold
| Table | Grain |
|---|---|
| `fact_match` | one scheduled match, with `counts_in_table` and `counts_in_goals` flags |
| `fact_team_match` | one team in one match that counts in the table |
| `v_league_table` | one team in one league in one season, ranked |

The league table ranks on points, goal difference, then goals scored. La Liga and Serie A use head-to-head results before goal difference; the view applies one rule to all five leagues so they can be compared, and the README says so rather than hiding it.

## Quality checks

`04_quality/01_quality_checks.sql`:

- **Reconciliation:** one `source_file` row per landed document; matches shredded equals the count of array elements inside each document; no match lost during name resolution; every match reaches gold.
- **Entity resolution:** in a double round robin every home/away pairing happens exactly once per season, and a season has `teams × (teams − 1)` matches. If a club were still split across two names, both checks would fail. Also: every canonical name maps to itself, and no accepted pair shares a season.
- **Business rules:** every counted match has a full-time score; half-time goals never exceed full-time goals; points in each table equal 3 per decisive match plus 2 per draw.

<!-- <img src="screenshots/05_quality_checks.png" width="800" height="400" alt="Quality checks"> -->

## Business parameters

| Parameter | Value | Used by |
|---|---|---|
| `points_win` / `points_draw` | 3 / 1 | League tables, points check |
| `name_match_min_score` | 1.00 | Team name resolution |
| `big_win_margin` | 5 | Heavy wins report |
| `max_goals_modelled` | 10 | Size of the score grid in the model |
| `validation_season_start` | 2022 | Season used to tune the model |
| `test_season_start` | 2023 | First test season |
| `new_team_strength` | 0.85 | Model strength for a club with no history |

Reference tables `ops.name_stop_token` and `ops.team_alias_override` can be edited the same way.

## Analysis

`05_analysis/01_analysis.sql`:

1. Champion, runner-up and title margin for every league and season
2. Home advantage with and without crowds
3. Goals per match, over 2.5 goals and both-teams-scored rates
4. Comebacks: how often each club rescues points after trailing at half-time
5. Heavy wins
6. Points per game by season for clubs present in all six seasons

The 2020-21 season was played almost entirely without fans, which turns the data into a natural experiment:

| League | Home win % with crowds | Home win % in 2020-21 |
|---|---|---|
| Premier League | 44.7 | 37.9 |
| Ligue 1 | 43.8 | 37.4 |
| La Liga | 45.1 | 41.6 |
| Bundesliga | 43.4 | 42.2 |
| Serie A | 41.0 | 40.9 |

<!-- <img src="screenshots/06_home_advantage.png" width="800" height="400" alt="Home advantage"> -->

## Poisson goals model

`06_ml/01_poisson_match_model.sql` predicts home win, draw or away win.

1. **Strengths.** Each club's attack is its goals per match divided by the league average; defence is goals conceded per match divided by the same.
2. **Expected goals.** Home xG = league home average × home attack × away defence. Away xG the same way round.
3. **Score grid.** Goals are treated as Poisson counts, so the chance of every score from 0-0 to 10-10 is calculated with `EXP`, `POWER` and a factorial table. Summing the cells where home > away gives P(home win), and so on.
4. **Shrinkage.** Raw strengths over-react to small samples, so each is pulled toward 1.00 by a factor `s`, the one value the model learns.

The data is split three ways so that the test seasons are never used to make a choice: strengths from 2019-20 to 2021-22, `s` chosen on 2022-23, and results reported on 2023-24 and 2024-25 with strengths refitted on everything before them.

| Metric (test seasons, 3,482 matches) | Value |
|---|---|
| Chosen shrinkage | 0.7 |
| Log loss: Poisson model | 1.007 |
| Log loss: league home/draw/away rates | 1.077 |
| Accuracy: Poisson model | 50.5% |
| Accuracy: always pick the home team | 42.7% |
| Average predicted draw chance / actual draw rate | 24.2% / 25.8% |

Log loss is the main measure because the model produces probabilities, and a good probability matters more than a right guess. A shrinkage of 0.7 means past seasons' form is a useful but imperfect guide: about 70% of a club's past difference from average carries into the next season.

<!-- <img src="screenshots/07_model_metrics.png" width="800" height="400" alt="Model metrics"> -->

## How to run

1. Copy this folder to a path without spaces, for example `C:\SQL_Boulevard\sports\03_five_leagues_json_pipeline`.
2. `data/raw/api_landing.jsonl` is already built. To rebuild it from `data/source_json`, run `python tools/build_landing_file.py`.
3. Open `run_all.sql` in SSMS, switch on **Query → SQLCMD Mode**, check the `:setvar` paths (no quotes) and press **F5**.

Requires SQL Server 2017 or later (`TRANSLATE`, `STRING_SPLIT`, `OPENJSON`).

## Folder structure

```
03_five_leagues_json_pipeline/
├── 00_setup/          database, schemas, parameters, stop words, steward overrides
├── 01_bronze/         JSON Lines load
├── 02_silver/         01 shred JSON, 02 resolve team names, 03 typed matches
├── 03_gold/           star schema and league table view
├── 04_quality/        reconciliation, round-robin and business-rule checks
├── 05_analysis/       six analysis queries
├── 06_ml/             Poisson goals model
├── data/source_json/  30 original JSON files
├── data/raw/          landing file
├── tools/             landing file builder
├── docs/
├── screenshots/
└── run_all.sql
```

## Git

```bash
git add sports/03_five_leagues_json_pipeline
git commit -m "Add five leagues JSON pipeline with team name resolution and Poisson model"
git push
```

## Data licence

Match data from [openfootball/football.json](https://github.com/openfootball/football.json), dedicated to the public domain (CC0).

---

[← Back to Sports projects](../README.md) · [Portfolio home](../../README.md)
