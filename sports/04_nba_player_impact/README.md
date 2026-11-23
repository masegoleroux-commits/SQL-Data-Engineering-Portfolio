<p align="center">
  <img src="../../assets/sports.png" alt="Sports projects" width="900">
</p>

# NBA Player Impact (RAPTOR)

A compact SQL Server project over FiveThirtyEight's RAPTOR player ratings for 2013-14 to 2021-22: 4,685 player seasons. It shows how to make wide statistical data trustworthy and comparable: small samples flagged, rating arithmetic checked, a name history kept with a Type 2 dimension, metrics unpivoted and standardised, and a nearest-neighbour search that finds the most similar past seasons for every current player.

**Skills shown:** sample-size rules as business parameters, SCD Type 2 with gaps and islands, unpivot with `CROSS APPLY (VALUES ...)`, z-scores and `PERCENT_RANK`, self-join similarity search, `LAG` for year-on-year change.

<!-- <img src="screenshots/01_run_all.png" width="800" height="400" alt="Run all"> -->

## Data stages

| Layer | Table | Grain |
|---|---|---|
| Bronze | `bronze.raptor_player_seasons` | the CSV as delivered, text |
| Silver | `silver.player_season` | one player in one season |
| Gold | `gold.dim_player` | one name a player was listed under (SCD2) |
| Gold | `gold.fact_player_season` | one player in one season |
| Gold | `gold.fact_player_metric` | one player, season and metric, with z-score and percentile |
| ML | `ml.similar_player` | one player in the comparison season and one of his closest matches |

### Cleaning log

| Step | Rule | Rows |
|---|---|---|
| 1 | Rows typed, ratings rounded to 4 decimals | 4,684 |
| 2 | Seasons under 1,000 minutes flagged as small samples | 2,205 |
| 3 | Row with blank box and on/off ratings → quarantine (4 minutes played) | 1 |
| 4 | Players whose listed name changes between seasons | 8 |

Step 2 matters more than it looks. The raw file contains ratings from +72 to −67 for players who barely played. Nearly half of all rows are under the threshold. Every ranking, z-score and comparison in the project uses qualified seasons only.

Step 4 found real name changes: Enes Kanter became Enes Freedom in 2021, and several players appear both with and without full stops (P.J. Tucker / PJ Tucker). The player ID is the key; `dim_player` keeps each name with the seasons it covers, built with the same gaps-and-islands method as a franchise history.

<!-- <img src="screenshots/02_name_history.png" width="800" height="400" alt="Name history"> -->

## Quality checks

- Every bronze row is in silver or quarantine; every silver row gets a name key.
- RAPTOR offense + defense = total, box offense + defense = box total, regular-season WAR + playoff WAR = total WAR (within 0.01).
- Exactly one current name per player and no overlapping name spells.
- Long format has exactly 8 rows per qualified season; z-scores average zero in every season and metric.

## Business parameters

| Parameter | Value | Used by |
|---|---|---|
| `min_minutes` | 1,000 | Which seasons count as qualified |
| `sum_tolerance` | 0.01 | Rating arithmetic checks |
| `comparison_season` | 2022 | Players who get similar-player lists |
| `similar_players` | 5 | Matches listed per player |

## Analysis

`05_analysis/01_analysis.sql`: top five players by wins above replacement each season; biggest year-on-year improvers (both seasons qualified, consecutive years only); how many players are two-way, offence-first or defence-first each season; and the name history from the Type 2 dimension.

## Similar players
`06_ml/01_similar_players.sql` answers "which past seasons look most like this one?", the nearest-neighbour method behind player-comparison tools.

1. Each qualified season becomes a point in six dimensions: z-scores for box offense, box defense, on/off offense, on/off defense, predator total and pace impact. Z-scores put every metric on the same scale.
2. For every 2021-22 player, the Euclidean distance to every other player's seasons is calculated with one self-join.
3. The five closest are kept; similarity = 1 / (1 + distance).

The output is easy to sense-check. Stephen Curry's closest match is Kevin Durant in 2015-16 (similarity 0.53). Nikola Jokic's best match scores only 0.25: his MVP season had no close equivalent in the data, which is what a similarity search should say about an outlier.

<!-- <img src="screenshots/03_similar_players.png" width="800" height="400" alt="Similar players"> -->

## How to run

Copy the folder to a path without spaces, open `run_all.sql` in SSMS, switch on **Query → SQLCMD Mode**, check the `:setvar` paths (no quotes) and press **F5**.

## Git

```bash
git add sports/04_nba_player_impact
git commit -m "Add NBA player impact project with SCD2 names and similarity search"
```

## Data licence

FiveThirtyEight [NBA RAPTOR](https://github.com/fivethirtyeight/data/tree/master/nba-raptor), CC BY 4.0.

---

[← Back to Sports projects](../README.md) · [Portfolio home](../../README.md)
