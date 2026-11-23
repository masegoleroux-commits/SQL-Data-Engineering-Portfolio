# Data Dictionary

Source: [UCL 2021/22 Matches & Players Data](https://www.kaggle.com/datasets/azminetoushikwasi/ucl-202122-uefa-champions-league) (Kaggle). The four player-level files are in `data/raw/`.

## dim_club

| Column | Type | Description |
|---|---|---|
| `club_key` | INT | Surrogate key |
| `club_name` | NVARCHAR(100) | Club name as it appears in the source, e.g. `Man. City`, `Atlético` |

## dim_player

| Column | Type | Description |
|---|---|---|
| `player_key` | INT | Surrogate key |
| `player_name` | NVARCHAR(100) | Display name from the source (often the surname only) |
| `club_name` | NVARCHAR(100) | Club for this stint. Part of the natural key |
| `position` | NVARCHAR(20) | `Goalkeeper`, `Defender`, `Midfielder` or `Forward` |

## fact_attacking

Players with at least one assist.

| Column | Source column | Description |
|---|---|---|
| `matches_played` | `match_played` | Appearances |
| `assists` | `assists` | Assists |
| `corners_taken` | `corner_taken` | Corners taken |
| `offsides` | `offsides` | Times caught offside |
| `dribbles` | `dribbles` | Dribbles |

## fact_defending

| Column | Source column | Description |
|---|---|---|
| `matches_played` | `match_played` | Appearances |
| `balls_recovered` | `balls_recoverd` | Balls recovered |
| `tackles` | `tackles` | Tackles attempted |
| `tackles_won` | `t_won` | Tackles won |
| `tackles_lost` | `t_lost` | Tackles lost |
| `clearances_attempted` | `clearance_attempted` | Clearances |

## fact_distribution

| Column | Source column | Description |
|---|---|---|
| `matches_played` | `match_played` | Appearances |
| `passes_attempted` | `pass_attempted` | Passes attempted |
| `passes_completed` | `pass_completed` | Passes completed |
| `crosses_attempted` | `cross_attempted` | Crosses attempted |
| `crosses_completed` | `cross_complted` | Crosses completed |
| `free_kicks_taken` | `freekicks_taken` | Free kicks taken |
| `pass_accuracy_src` | `pass_accuracy` | Source pass accuracy %. Does not reconcile to the counts, so it is kept for reference only (see [data_quality.md](data_quality.md)) |

## fact_discipline

| Column | Source column | Description |
|---|---|---|
| `matches_played` | `match_played` | Appearances |
| `minutes_played` | `minutes_played` | Minutes played |
| `fouls_committed` | `fouls_committed` | Fouls committed |
| `fouls_suffered` | `fouls_suffered` | Fouls suffered |
| `yellow_cards` | `red` | Yellow cards. **Source columns are swapped** |
| `red_cards` | `yellow` | Red cards. **Source columns are swapped** |

## Derived measures (views)

| Measure | Formula |
|---|---|
| `tackle_success_pct` | `100 × tackles_won / tackles` |
| `pass_completion_pct` | `100 × passes_completed / passes_attempted` |
| `cross_completion_pct` | `100 × crosses_completed / crosses_attempted` |
| `fouls_committed_per_90` | `90 × fouls_committed / minutes_played` |

Ratios are always calculated from summed counts (`SUM(a) / SUM(b)`), never by averaging per-player ratios. This keeps club and position roll-ups weighted by volume.
