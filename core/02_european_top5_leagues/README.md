<p align="center">
  <img src="../../assets/core.png" alt="Core projects" width="900">
</p>

# European Top-5 Leagues: Staged Pipeline and Match Outcome Model

Three seasons (2022/23 to 2024/25) of results and match statistics for the Premier League, La Liga, Serie A, Bundesliga and Ligue 1, taken from 15 CSV files to a tested star schema and an Elo-based model that predicts home win, draw and away win. Every stage keeps its own schema, so any number in a report can be traced back to a line in a file.

**Skills shown:** layered pipeline (raw, staging, clean, model), `BULK INSERT` with delivery logging, `TRY_CONVERT` with error counting, team-name standardisation, quarantine with reason codes, a cleaning log, star schema with two fact grains, leakage-safe features, Elo ratings, probability calibration, Brier score and log loss, business parameters in a table.

<!-- <img src="screenshots/01_cleaning_log.png" width="800" height="400" alt="Cleaning log"> -->

## Stages

| Stage | Schema | What happens |
|---|---|---|
| 0 | `cfg` | Business parameters, leagues, the 15 source files, teams per season, team-name aliases |
| 1 | `raw` | Each file loaded as delivered, every column as text, with file name, load id and line number. Nothing is ever changed or deleted here |
| 2 | `stg` | Latest delivery of each file in proper types. A value that will not convert becomes NULL and is counted in `type_errors` |
| 3 | `cln` | Team names standardised, rules applied, failing rows quarantined in `cln.match_issue`, every step logged in `cln.cleaning_log` |
| 4 | `dw` | Star schema: `fact_match` (one row per match) and `fact_team_match` (one row per team per match), with league, season, team, referee and date dimensions |
| 5 | `ml` | Form features, Elo ratings, calibrated probabilities, evaluation on a held-back season |
| 6 | `rpt` | League tables rebuilt from results |

### Cleaning rules

| Rule | Row goes to quarantine when |
|---|---|
| `UNMAPPED_TEAM` | a team name is not in the alias table |
| `TYPE_ERROR` | a value was present but would not convert |
| `MISSING_RESULT` | date, full-time score or result is empty |
| `RESULT_MISMATCH` | the result letter disagrees with the score |
| `IMPOSSIBLE_STATS` | for example, more shots on target than shots |
| `DATE_OUTSIDE_SEASON` | the date falls outside the file's season |
| `DUPLICATE_FIXTURE` | the same home and away pairing appears twice in a season |

Rows with missing statistics are kept and flagged, not dropped, because the result is still valid for the league table.

<!-- <img src="screenshots/02_quarantine.png" width="800" height="400" alt="Quarantine"> -->

<!-- <img src="screenshots/03_league_table.png" width="800" height="400" alt="League table"> -->

## Business parameters (`cfg.business_parameter`)

Points for a win and a draw, the form window (5 matches), Elo starting rating (1500), rating for promoted teams (1450), K-factor (20), home advantage (60), season carry-over (0.8), number of calibration bands (10), the burn-in, training and test seasons, and the minimum matches for the referee ranking. Changing a value and re-running changes the result; no code is edited.

## The model

1. **Form features** look back over each team's previous matches and never include the match being predicted.
2. **Elo ratings** are computed match by match in date order; each rating is stored as it was before kick-off.
3. **Calibration**: the Elo expected score is split into bands, and the home, draw and away rates in each band in the training season (with Laplace smoothing) become the probabilities.
4. **Evaluation** on the 2024/25 season, which the model never saw: accuracy, Brier score and log loss, against two baselines (always back the home team; the training season's average rates). A test fails the run if the model does not beat the baseline Brier score.

`ml.v_training_dataset` is the hand-over point to a data scientist: one row per match with everything known before kick-off and the result as the label.

<!-- <img src="screenshots/04_model_evaluation.png" width="800" height="400" alt="Model evaluation"> -->

## Tests

27 tests in `tests/`, each with expected and actual values, stop the run on failure:

- raw: rows = teams x (teams - 1) for every file; staged rows = latest delivery
- clean: clean + quarantined = staged; each team plays 2 x (teams - 1) matches; every source name is mapped
- model: one row per match; two team rows per match; goals and points reconcile; one champion per league season
- features: no form history before a team's first match; form uses earlier matches only
- Elo and model: expected scores between 0 and 1; ratings chain from match to match; probabilities add to 1; calibration uses only the training season; the model beats the baseline

<!-- <img src="screenshots/05_tests.png" width="800" height="400" alt="Tests"> -->

## How to run

1. Copy the project to a path without spaces, for example `C:\SQL_Boulevard\core\02_european_top5_leagues`.
2. Open `run_all.sql` in SSMS, switch on **Query > SQLCMD Mode**, check `RepoPath` and `DataPath` at the top.
3. Execute (F5). The run stops at the first error or failed test.

The raw load (`pipeline/01_load_raw.sql`) is one block per file: `BULK INSERT` into a landing table, a row in `raw.load_log`, a copy into `raw.match` under that load id. It uses no dynamic SQL, so the paths are checked by SQLCMD before anything runs.

## Data

Match results and statistics from [football-data.co.uk](https://www.football-data.co.uk/), in the form republished by the [datasets/football-datasets](https://github.com/datasets/football-datasets) repository. Referee names are supplied for the Premier League only; other leagues use the unknown-referee member.

---

[← Back to Core projects](../README.md) · [Portfolio home](../../README.md)
