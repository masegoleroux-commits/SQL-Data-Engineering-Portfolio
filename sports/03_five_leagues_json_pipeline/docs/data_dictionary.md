# Data dictionary

## Source document shape

```json
{
  "name": "English Premier League 2023/24",
  "matches": [
    { "round": "Matchday 1", "date": "2023-08-11", "time": "20:00",
      "team1": "Burnley FC", "team2": "Manchester City FC",
      "score": { "ht": [0, 2], "ft": [0, 3] } },
    { "round": "Matchday 28", "date": "2020-03-07",
      "team1": "RC Strasbourg", "team2": "Paris Saint-Germain",
      "score": {}, "status": "cancelled" }
  ]
}
```

| JSON path | Silver column | Notes |
|---|---|---|
| `$.round` | `matchday` | `Matchday 12` → 12 |
| `$.date` | `match_date` | ISO date |
| `$.time` | `kickoff_time` | missing for cancelled matches |
| `$.team1` / `$.team2` | `home_team` / `away_team` | replaced by the canonical name |
| `$.score.ht[0]`, `[1]` | `ht_home`, `ht_away` | missing in 680 played matches |
| `$.score.ft[0]`, `[1]` | `ft_home`, `ft_away` | empty object when not played |
| `$.status` | `match_status` | only present for `cancelled` and `awarded` |

## Gold grain

| Table | Grain | Rows |
|---|---|---|
| `dim_league` | one league | 5 |
| `dim_season` | one season | 6 |
| `dim_team` | one club in one league | 137 |
| `fact_match` | one scheduled match | 10,808 |
| `fact_team_match` | one team in one counted match | 21,374 |

## Known gaps in the source

- Ligue 1 2019-20: 101 matches cancelled when the season was stopped.
- La Liga and Serie A 2024-25: the files end before the last round (10 matches each), so those final tables are one game short.
