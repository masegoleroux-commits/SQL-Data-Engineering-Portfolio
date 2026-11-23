<p align="center">
  <img src="../../assets/sports.png" alt="Sports projects" width="900">
</p>

# Fantasy Football Points Engine

A compact SQL Server project that rebuilds the 2023-24 Fantasy Premier League scoring from raw match statistics. 29,725 player-fixture rows, 865 players. The scoring rules live in a table rather than in code, the engine reproduces every published score exactly, and a second rule set shows how the same engine answers "what if the rules changed?".

**Skills shown:** table-driven business rules, unpivoting to an event model, a rules engine as one join, row-level reconciliation against a published figure, double-gameweek grain, rolling-window forecasting, forecast evaluation.

<!-- <img src="screenshots/01_run_all.png" width="800" height="400" alt="Run all"> -->

## Why rules in a table

Hard-coding scoring in CASE expressions works until the rules change, and then every query has to be found and edited. Here a rule is a row:

| event | position | points | unit_size | min_minutes |
|---|---|---|---|---|
| goal | MID | 5 | 1 | 0 |
| clean_sheet | DEF | 4 | 1 | 60 |
| saves | GK | 1 | 3 | 0 |
| goals_conceded | DEF | −1 | 2 | 0 |

The engine in `03_gold/01_points_engine.sql` is one join between player events and rules:

```sql
(e.quantity / r.unit_size) * r.points          -- 5 saves / 3 = 1 unit = 1 point
... ON r.event = e.event
   AND r.position IN (p.position, 'ALL')
   AND p.minutes >= r.min_minutes
```

A rule change becomes a new rule set. Nothing else moves.

## Data stages

| Layer | Table | Grain |
|---|---|---|
| Bronze | `fpl_player_gameweeks`, `fpl_teams` | CSV as delivered |
| Silver | `player_fixture` | one player in one fixture |
| Silver | `player_fixture_event` | one player, fixture and event (long format) |
| Gold | `fact_points_breakdown` | one rule set, player, fixture and event |
| Gold | `fact_player_fixture` | one player in one fixture, with official, engine and scenario points |

The key is player + fixture, not player + gameweek. In double gameweeks a player has two fixtures in the same gameweek; 1,966 rows would collide on a gameweek key.

| Step | Cleaning rule | Rows |
|---|---|---|
| 1 | ISO kick-off text `2023-08-12T14:00:00Z` converted to `DATETIME2` | 29,725 |
| 2 | `True` / `False` text converted to 1 / 0 | 29,725 |
| 3 | Price in tenths (55) converted to millions (5.5) | 29,725 |
| 4 | Opponent team ID resolved to a club name | 29,725 |
| 5 | Players who changed club mid-season (club kept per fixture) | 23 |
| 6 | Rows in double gameweeks | 1,966 |

## Quality checks

- The engine reproduces the published points in **every** row (0 differences) and in the season total.
- Every event in the data has a rule in every rule set, so no event is silently scored as zero.
- Clean sheets only appear for 60+ minutes with no goals conceded.
- No player has two fixtures at the same kick-off.

<!-- <img src="screenshots/02_reconciliation.png" width="800" height="400" alt="Reconciliation"> -->

## Business parameters

| Parameter | Value | Used by |
|---|---|---|
| `official_rule_set` | 1 | Rules that must match the published points |
| `scenario_rule_set` | 2 | What-if rules |
| `form_window` | 4 | Matches averaged in the form forecast |
| `min_matches_value` | 10 | Value ranking |

## Analysis

1. Season leaders with points broken down by source (Cole Palmer tops the season with 244)
2. Points per million
3. What-if: rule set 2 makes keeper goals worth 10 and scores every 2 saves instead of 3. Goalkeepers gain up to 29 points and move up the overall ranking, with no change to the engine
4. Points per 90 minutes by position

<!-- <img src="screenshots/03_what_if.png" width="800" height="400" alt="What if"> -->

## Form forecast
`06_ml/01_form_forecast.sql` asks whether a player's recent form predicts his next score better than the game's own published forecast (xP). For 9,265 fixtures where the player had at least four previous appearances:

| Forecast | Mean absolute error (points) |
|---|---|
| Game forecast (xP) | 1.84 |
| Blend of xP and form | 1.94 |
| Rolling 4-match form average | 2.24 |
| Always the overall average | 2.24 |

The honest result is that recent form on its own is no better than guessing the average: fantasy scores are noisy enough that four matches tell you very little. The published forecast, which uses fixture difficulty and underlying statistics, is clearly better. This is a useful finding for anyone picking a team on form.

<!-- <img src="screenshots/04_forecast.png" width="800" height="400" alt="Forecast"> -->

## How to run

Copy the folder to a path without spaces, open `run_all.sql` in SSMS, switch on **Query → SQLCMD Mode**, check the `:setvar` paths (no quotes) and press **F5**.

## Git

```bash
git add sports/05_fantasy_points_engine
git commit -m "Add table-driven fantasy points engine with reconciliation and forecast"
```

## Data

Fantasy Premier League 2023-24 gameweek data collected by [vaastav/Fantasy-Premier-League](https://github.com/vaastav/Fantasy-Premier-League) (MIT licence). Points and statistics belong to the Premier League's official game.

---

[← Back to Sports projects](../README.md) · [Portfolio home](../../README.md)
