# Data dictionary and grain

Source: [The Fjelstul World Cup Database](https://github.com/jfjelstul/worldcup) by Joshua C. Fjelstul, licensed CC-BY-SA 4.0. Covers every men's World Cup from 1930 to 2022 and every women's World Cup from 1991 to 2019.

## Layers

| Layer | Schema | What it holds | Rule |
|---|---|---|---|
| Bronze | `bronze` | The CSV files exactly as delivered, every column as text | Never edited, so any result can be traced back to the file |
| Silver | `silver` | Typed, cleaned tables with primary keys | Every change is counted in `ops.cleaning_log`; rows that fail a rule go to `ops.quarantine` |
| Gold | `gold` | Star schema and the `v_team_tournament` mart | Surrogate keys, foreign keys, one documented grain per table |
| ML | `ml` | Features, model search, predictions and metrics | Uses only information available before each tournament |
| Ops | `ops` | Load log, cleaning log, quarantine, business parameters, test results | Run metadata |

## Gold tables

| Table | Grain | Key | Rows |
|---|---|---|---|
| `dim_tournament` | one tournament | `tournament_key` | 30 |
| `dim_team` | one national team | `team_key` | 88 |
| `dim_player` | one player | `player_key` | 10,401 |
| `dim_stage` | one stage name | `stage_key` | 8 |
| `fact_match` | one match | `match_key` | 1,248 |
| `fact_team_match` | one team in one match | `match_key, team_key` | 2,496 |
| `fact_goal` | one goal | `goal_id` | 3,637 |
| `fact_booking` | one yellow or red card | `booking_id` | 3,178 |

## Columns worth knowing

| Column | Meaning |
|---|---|
| `fact_match.final_result` | H / A / D including penalty shootouts |
| `fact_match.regulation_result` | H / A / D on the score only. A shootout match is D here |
| `fact_match.host_team_key` | The host nation, when it played in the match; otherwise NULL |
| `fact_team_match.outcome` | W / D / L on the score |
| `fact_team_match.went_through` | 1 if the team won outright or on penalties |
| `fact_goal.is_extra_time` | 1 for goals after the 90th minute of regulation |
| `dim_stage.stage_order` | Lets "furthest stage reached" be calculated with MAX() |

## Data findings

| Finding | Rows | How it is handled |
|---|---|---|
| Stage names written two ways (`quarter-final` and `quarter-finals`) | 48 | Standardised to the plural form |
| Player birth date written as the text `not available` | 77 | Set to NULL |
| Score text uses an en dash (`2–1`) except for one match that uses a hyphen | 1 | Separator standardised before the score text is checked |
| Penalty shootouts | 43 | Two results kept: with and without the shootout |
| Drawn knockout matches in 1934 and 1938 | 4 | Not errors. These matches were replayed, so the quality check allows them |
| Players known by one name (`given_name = 'not applicable'`) | several | Display name built from the family name only |
