<p align="center">
  <img src="../../assets/sports.png" alt="Sports projects" width="900">
</p>

# NBA Elo History Warehouse

A SQL Server warehouse over 69 seasons of professional basketball (NBA and ABA, 1946-47 to 2014-15): 63,157 games, 53 franchises and every team's Elo rating before and after each game. The project focuses on two problems that come up in almost every real warehouse: a source that stores each event twice, and entities that change identity over time.

**Skills shown:** de-duplicating mirrored rows, Slowly Changing Dimension Type 2 built with gaps-and-islands, window functions (LAG, running SUM, ROW_NUMBER), zero-sum and continuity checks, a trained and tested probability model with calibration.

<!-- <img src="screenshots/01_run_all.png" width="800" height="400" alt="Run all"> -->

## The problem

The source file has one row per team per game, so every game appears twice: once for each side, with a `_iscopy` flag on the mirror. Counting rows counts every game twice. Summing points double-counts them.

Teams also move. The Kings have been the Rochester Royals, Cincinnati Royals, Kansas City-Omaha Kings, Kansas City Kings and Sacramento Kings. A question about "the Kings franchise" needs all five; a question about "Kansas City" needs only the right years. The New Orleans team is harder still: NOH, then NOK for two seasons after Hurricane Katrina, then NOH again.

## Pipeline

```
data/raw/nba_elo_games.csv   126,314 rows (every game twice)
   │  BULK INSERT, every column as text
   ▼
bronze   exact copy of the file
   │  mirror check, type, clean, flag
   ▼
silver   team_game  (one team in one game)
         game       (one game, copy rows removed)   ──►  ops.cleaning_log, ops.quarantine
   │  SCD Type 2 team dimension, surrogate keys
   ▼
gold     dim_franchise, dim_team (SCD2), dim_season, fact_game, fact_team_game
   │
   ├──► 04_quality   12 checks, the run stops if any fail
   ├──► 05_analysis  peak ratings, upsets, home court, streaks, champions, relocations
   └──► 06_ml        home-court advantage learned from data, then tested
```

## Data stages in detail

### Bronze
`01_bronze/01_load_bronze.sql` loads the file with every column as text and logs the row count.

### Silver
Before anything is typed, each game's two rows are compared. A clean game has exactly two rows where one side's points and rating are the other side's opponent points and opponent rating. Games that fail are quarantined as a whole. None failed, which is itself worth knowing before building on the file.

| Step | Rule | Rows |
|---|---|---|
| 1 | Dates converted from `M/D/YYYY` text with `CONVERT(DATE, x, 101)` | 126,314 |
| 2 | The text `NULL` in notes replaced with a real NULL | 88,308 |
| 2 | Leading spaces trimmed from notes (a Seattle note arrives cut off as ` Edmundson Pavillion)`) | 20 |
| 3 | Games whose two rows do not mirror → quarantine | 0 |
| 4 | Forfeits flagged from the notes (Denver at Virginia, 1972, recorded as 2-0) | 2 |
| 5 | Neutral-site games flagged, venue taken from the notes | 38 |
| 6 | Mirror rows removed for the one-row-per-game table | 63,157 |

Silver keeps both shapes on purpose. `team_game` is right for anything about one team's season. `game` is right for anything about matchups, such as home-court advantage.

<!-- <img src="screenshots/02_cleaning_log.png" width="800" height="400" alt="Cleaning log"> -->

### Gold: the Type 2 team dimension
`dim_team` has one row per spell a franchise spent under one team code, with `valid_from`, `valid_to`, `version_no` and `is_current`. It is built with a gaps-and-islands pattern:

1. List each franchise's seasons in order with the code used that season.
2. Use `LAG` to mark a season as the start of a new spell when its code differs from the season before.
3. A running `SUM` of those marks gives each spell a number.
4. Group by spell number for the start and end season.

Grouping by team code alone would give New Orleans one NOH row covering 2003 to 2013, swallowing the two NOK seasons. The island method gives three separate rows. The result is 107 team rows for 53 franchises.

Facts look up their team key by code **and** season, so every game points to the identity the team actually had that night.

| Table | Grain |
|---|---|
| `fact_game` | one game |
| `fact_team_game` | one team in one game |
| `dim_team` | one franchise under one code for one unbroken run of seasons |
| `v_franchise_season` | one franchise in one season |

<!-- <img src="screenshots/04_star_schema.png" width="800" height="400" alt="Star schema"> -->

## Quality checks

`04_quality/01_quality_checks.sql`:

- **Reconciliation:** every bronze row reaches silver or is quarantined; silver has exactly two team rows per game; every silver row reaches gold.
- **Game rules:** one winner per game; the winner scored more points.
- **Elo arithmetic:** rating changes in a game are equal and opposite (Elo is zero-sum); the two pre-game forecasts add up to 1; within a season, each game's starting rating equals the previous game's finishing rating.
- **SCD Type 2:** no overlapping spells within a franchise; exactly one current row per franchise; no season gaps between spells.

The continuity check skips the change between seasons on purpose. Ratings are pulled back toward the league average each summer, so they are not expected to match there.

<!-- <img src="screenshots/03_quality_checks.png" width="800" height="400" alt="Quality checks"> -->

## Business parameters

| Parameter | Value | Used by |
|---|---|---|
| `elo_scale` | 400 | Converting a rating gap into a probability |
| `upset_forecast_max` | 0.20 | What counts as an upset |
| `min_win_streak` | 15 | Streak report |
| `elo_tolerance` | 0.01 | Rounding allowed in the Elo checks |
| `test_from_season` | 2006 | Model train / test split |
| `hca_search_max` / `hca_search_step` | 200 / 10 | Range searched for home-court advantage |
| `calibration_buckets` | 10 | Calibration table |

## Analysis

`05_analysis/01_analysis.sql`:

1. Peak rating of every franchise, and which identity it had at the time (the 1996 Bulls top the list)
2. Biggest upsets, with each winner's pre-game chance
3. Home-court advantage by decade, as win rate and average margin
4. Longest winning streaks, using gaps and islands over wins and losses
5. The best-rated team at the end of each season compared with the champion
6. Rating in the last season before each relocation compared with the first season after

<!-- <img src="screenshots/05_streaks.png" width="800" height="400" alt="Streaks"> -->

## Win probability model

`06_ml/01_win_probability_model.sql` turns two ratings into a home-win probability:

```
p(home win) = 1 / (1 + 10 ^ (-(home_elo - away_elo + hca) / 400))
```

**Training.** The model learns `hca`, the home-court advantage in rating points. Every value from 0 to 200 is scored on the 50,256 games before 2006 using the Brier score, the average squared gap between the probability and what happened (0 is perfect, 0.25 is a coin flip). The lowest score wins.

**Testing.** The learned value is applied, unchanged, to the 12,900 games from 2006 to 2015.

| Metric (test seasons) | Value |
|---|---|
| Learned home-court advantage | 110 Elo points |
| Brier score: this model | 0.2077 |
| Brier score: FiveThirtyEight's published forecast | 0.2070 |
| Brier score: baseline (home-win rate for every game) | 0.2409 |
| Accuracy: this model | 67.0% |

The model learned a home-court value of 110 points from the data alone. FiveThirtyEight's published method uses 100, and the two sets of forecasts score almost the same on games neither was tuned on.

The calibration table checks whether the probabilities can be trusted: of the games the model gave a 75% chance, about 72% were home wins. The model is slightly overconfident in the middle of the range, which fits query 3: the home-win rate fell from about 65% in the 1980s to under 60% in the 2010s, so a home edge learned on older seasons is a little too generous for newer ones.

<!-- <img src="screenshots/06_model_metrics.png" width="800" height="400" alt="Model metrics"> -->

## How to run

1. Copy this folder to a path without spaces, for example `C:\SQL_Boulevard\sports\02_nba_elo_history`.
2. Open `run_all.sql` in SSMS and switch on **Query → SQLCMD Mode**.
3. Edit the two `:setvar` lines if needed (no quotes around paths).
4. Press **F5**. The run creates the `NbaElo` database.

## Folder structure

```
02_nba_elo_history/
├── 00_setup/       database, schemas, ops tables, business parameters
├── 01_bronze/      raw CSV load
├── 02_silver/      mirror check, typing, cleaning
├── 03_gold/        SCD2 team dimension, facts, franchise-season view
├── 04_quality/     reconciliation, Elo and SCD checks
├── 05_analysis/    six analysis queries
├── 06_ml/          win probability model and calibration
├── data/raw/       source CSV
├── docs/           data dictionary
├── screenshots/
└── run_all.sql
```

## Git

```bash
git add sports/02_nba_elo_history
git commit -m "Add NBA Elo warehouse with SCD Type 2 franchises and win probability model"
git push
```

## Data licence

Data from FiveThirtyEight's [NBA Elo dataset](https://github.com/fivethirtyeight/data/tree/master/nba-elo), used under CC BY 4.0.

---

[← Back to Sports projects](../README.md) · [Portfolio home](../../README.md)
