# Data dictionary

| Column | Meaning |
|---|---|
| `player_id` | FPL element ID |
| `fixture_id` | FPL fixture ID; with player_id, the grain of every fact |
| `gameweek` | Round of the game; a player can have 0, 1 or 2 fixtures in one gameweek |
| `official_points` | Points published by the game |
| `engine_points` | Points calculated from `ops.scoring_rule`, rule set 1 |
| `scenario_points` | Points under rule set 2 |
| `expected_points` | The game's pre-match forecast (xP) |
| `price_millions` | Player price at the time of the fixture |
