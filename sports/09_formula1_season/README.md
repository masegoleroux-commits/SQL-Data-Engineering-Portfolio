<p align="center">
  <img src="../../assets/sports.png" alt="Sports projects" width="900">
</p>

# Formula 1 2023 Season

A compact SQL Server project on the 2023 Formula 1 season: 22 Grands Prix, 6 sprints, qualifying for every round and the calendar. The project integrates six files that describe the same season in different ways, parses race-result text into statuses and gaps, rebuilds the championship from a points table and checks it against the published points.

**Skills shown:** conformed dimensions across sources, matching rules with a steward override, repairing malformed values, mixed-format text parsing, table-driven points, running totals, "mathematically decided" logic, least-squares regression in SQL.

<!-- <img src="screenshots/01_run_all.png" width="800" height="400" alt="Run all"> -->

## Data stages

| Layer | Table | Grain |
|---|---|---|
| Bronze | 6 CSV files | as delivered |
| Silver | `race` | one calendar round, including a cancelled one |
| Silver | `result` | one driver in one race or sprint |
| Silver | `qualifying` | one driver in one qualifying session |
| Gold | `fact_result` | one driver in one session, published and engine points |
| Gold | `v_standing`, `v_team_standing` | one driver / team after one round, running total |

### Making six files agree

- **Races.** Results call a race by a short label (`Miami`, `Italy`, `United States`); the calendar uses country and city. Labels are matched by city first, then by country when the country has one race, then by `ops.track_label_override` for the two that stay ambiguous (Italy and the United States).
- **Cancelled round.** The calendar still lists Imola (round 6), with a blank date and no results; it was cancelled after flooding. It is kept and flagged, not deleted.
- **Teams.** Results include the engine supplier (`Red Bull Racing Honda RBPT`). They are matched to the constructor by its leading name, after standardising `Haas F1 Team` to `Haas`.
- **A typo.** The Qatar sprint lists Lance Stroll's team as `Aston Martib`. A team that matches no constructor takes the driver's team from the same weekend's race.
- **A malformed lap time.** One qualifying time is written `1:59:634`. Times shaped `m:ss:fff` are repaired to `m:ss.fff` before conversion.

### Parsing Time/Retired

| Text | Status | Parsed |
|---|---|---|
| `1:33:56.736` | finished | winner's time in seconds, gap 0 |
| `+11.987` | finished | gap 11.987 s |
| `+1 lap` | lapped | 1 lap down |
| `DNF` / `DNS` | DNF / DNS | |
| position `DQ` / `NC` | disqualified / not classified | no numeric position |

| Step | Cleaning rule | Rows |
|---|---|---|
| 1 | Calendar dates converted from DD/MM/YYYY (1 blank, cancelled round) | 22 |
| 2 | Results labels matched to a round (2 through the override table) | 22 |
| 3 | Calendar rounds with no results (cancelled) | 1 |
| 4 | Constructor names with an ` F1 Team` suffix standardised | 1 |
| 4 | Misspelt team names resolved from the same weekend's race | 1 |
| 5 | Statuses parsed: finished 414, lapped 70, DNF 69, DNS 4, disqualified 2 | 559 |
| 6 | Lap time written `m:ss:fff` repaired | 1 |
| 6 | Qualifying lap times converted to seconds | 976 |

## Quality checks

- Every race, sprint and qualifying row is matched to a round and a team; each label matches exactly one round.
- **The points engine reproduces the published points in every row.** Race and sprint points come from `ops.points_rule`; the fastest-lap point is added only for a top-10 finish, as the 2023 rules required.
- One winner and one fastest lap per Grand Prix; no shared finishing positions; gaps grow down the order; no team runs more than two cars.

The rebuilt tables match the official 2023 results: Verstappen 575, Perez 285, Hamilton 234; Red Bull 860, Mercedes 409, Ferrari 406.

## Business parameters

| Parameter | Value | Used by |
|---|---|---|
| `fastest_lap_bonus` / `fastest_lap_max_pos` | 1 / 10 | Points engine |
| `model_train_last_round` | 15 | Model split |

`ops.points_rule` holds the race and sprint scales. Changing it to an older scale (10-8-6-5-4-3-2-1, say) recomputes every standing.

## Analysis

1. Final driver and constructor championships
2. **When the title was decided:** after each round, the leader's margin against the most points still available. After Japan the margin was 177 with 180 still available; after Qatar it was 209 with 120 left, so the title was mathematically settled at Qatar, as it was in reality
3. Teammate qualifying head-to-heads, using the last session both drivers reached
4. Reliability and places gained by team

<!-- <img src="screenshots/02_title_race.png" width="800" height="400" alt="Title race"> -->

## Grid to finish model
`06_ml/01_finish_from_grid.sql` fits a straight line from grid position to finishing position using the least-squares formulas written directly in SQL (slope = covariance ÷ variance). It trains on rounds 1 to 15 and tests on the rest.

| Metric (test rounds, 133 finishes) | Value |
|---|---|
| Slope | 0.67 places per grid place |
| MAE: fitted line | 3.13 places |
| MAE: finish where you start | 3.58 places |
| R²: fitted line | 0.37 |

A slope below 1 is the interesting part: drivers starting near the back tend to gain places and drivers at the front tend to lose a few, partly because retirements shuffle the order. The grid explains a bit over a third of the finishing order.

<!-- <img src="screenshots/03_model.png" width="800" height="400" alt="Model"> -->

## How to run

Copy the folder to a path without spaces, open `run_all.sql` in SSMS, switch on **Query → SQLCMD Mode**, check the `:setvar` paths (no quotes) and press **F5**.

## Git

```bash
git add sports/09_formula1_season
git commit -m "Add Formula 1 2023 season project with points engine and title-race analysis"
```

## Data

[toUpperCase78/formula1-datasets](https://github.com/toUpperCase78/formula1-datasets), 2023 season files. Results are as published by Formula 1.

---

[← Back to Sports projects](../README.md) · [Portfolio home](../../README.md)
