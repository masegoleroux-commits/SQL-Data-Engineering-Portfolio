# Data dictionary

| Column | Meaning |
|---|---|
| `possessions`, `minutes` | Playing time in the season (regular season and playoffs) |
| `box_*` | Rating from box-score statistics, points per 100 possessions above average |
| `onoff_*` | Rating from team performance with the player on and off the court |
| `raptor_*` | Combined rating; offense + defense = total |
| `war_*` | Wins above replacement; regular season + playoffs = total |
| `predator_total` | Version of the rating built to predict future performance |
| `pace_impact` | Effect on team possessions per 48 minutes |

Qualified season: at least `min_minutes` minutes (1,000 by default).
