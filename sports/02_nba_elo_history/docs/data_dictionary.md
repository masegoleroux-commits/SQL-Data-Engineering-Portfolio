# Data dictionary

Source: FiveThirtyEight `nbaallelo.csv` (CC BY 4.0). One row per team per game; `_iscopy = 1` marks the mirror row.

| Source column | Silver column | Notes |
|---|---|---|
| `game_id` | `game_id` | Date + home team code, e.g. `194611010TRH` |
| `_iscopy` | `is_copy` | 1 on the second row of each game |
| `year_id` | `season` | The year the season ended (1947 = 1946-47) |
| `date_game` | `game_date` | `M/D/YYYY` text in the source |
| `team_id` / `fran_id` | `team_id` / `franchise_id` | Team code changes when a franchise moves; franchise name does not |
| `elo_i` / `elo_n` | `elo_before` / `elo_after` | Rating before and after the game |
| `forecast` | `forecast` | Pre-game win probability for this row's team |
| `game_location` | `game_location` | H, A or N (neutral) |
| `notes` | `notes`, `is_forfeit`, `site_name` | Free text; `NULL` written as text in the source |

## Gold grain

| Table | Grain | Rows |
|---|---|---|
| `dim_franchise` | one franchise | 53 |
| `dim_team` | one franchise, one code, one unbroken run of seasons (SCD2) | 107 |
| `dim_season` | one season | 69 |
| `fact_game` | one game | 63,157 |
| `fact_team_game` | one team in one game | 126,314 |
