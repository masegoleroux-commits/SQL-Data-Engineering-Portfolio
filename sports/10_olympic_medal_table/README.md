<p align="center">
  <img src="../../assets/sports.png" alt="Sports projects" width="900">
</p>

# Olympic Medal Table

A compact SQL Server project on every Summer and Winter Olympics from 1992 to 2016: 122,216 athlete entries, 14 Games, 231 national committees. It is built around the most common way aggregate numbers go wrong: counting at the wrong grain. The source has one row per athlete, so a relay win appears four times. The project fixes that in the model, proves the fix against published medal tables, and adds a medal forecast.

**Skills shown:** grain definition and enforcement, deriving a fact at a coarser grain, reconciliation against an external reference, unusual line endings, reference-data overrides, host-effect analysis, a two-input forecast in SQL.

<!-- <img src="screenshots/01_run_all.png" width="800" height="400" alt="Run all"> -->

## The grain problem

| Question | Wrong answer (sum of medal rows) | Right answer (one row per medal) |
|---|---|---|
| Medal rows in the data | 16,781 | 7,986 medals |
| USA, 1992-2016 | 1,285 more medals than it really won | counted once per medal |

Team sports, relays and crews make the gap huge: one basketball gold is twelve rows. `gold.fact_medal` stores one row per medal (Games + event + NOC + medal) with the number of athletes behind it, and every medal table comes from there. Analysis query 1 shows the overcount per country so the mistake is visible, not just avoided.

## Data stages

| Layer | Table | Grain |
|---|---|---|
| Bronze | `athlete_events_1992_2016`, `noc_regions` | files as delivered |
| Silver | `entry` | one athlete in one event at one Games |
| Silver | `noc` | one National Olympic Committee |
| Gold | `fact_entry` | one athlete in one event at one Games |
| Gold | `fact_medal` | one medal awarded |
| Gold | `dim_event` | one event at one Games, with `is_team_event` (676 of 2,571) |
| Gold | `v_medal_table` | one country at one Games |

| Step | Cleaning rule | Rows |
|---|---|---|
| 1 | `NA` medal → NULL (no medal) | 105,435 |
| 1 | `NA` age / height → NULL | 59 / 6,028 |
| 2 | Heights outside 120-230 cm → NULL | 0 |
| 3 | Crew numbers removed from team names (`United States-2`) | 2,777 |
| 4 | NOC codes missing from the region file added from an override (`SGP`) | 1 |

Two loading details are worth knowing. The region file ends its lines with a carriage return only (old Mac format), so it loads with `ROWTERMINATOR = '0x0d'`; with the usual line feed every row would land in one. And historic teams are kept as they competed: EUN, the Unified Team of 1992, is not merged into Russia.

## Quality checks

- Every bronze row reaches silver and gold; every NOC has a region.
- Medal athletes add back up to the medal rows, so nothing is lost when the grain changes.
- **The medal table matches published totals** for five reference country-Games in `ops.reference_medal_count` (USA 2016: 46-37-38; GB 2012: 29-17-19; China 2008: 51-21-28; GB 2016; Norway 2014).
- No event gives the same country two golds; no athlete is entered twice in one event.

## Business parameters

| Parameter | Value | Used by |
|---|---|---|
| `min_medals_ranking` | 10 | Efficiency ranking |
| `test_from_year` | 2012 | Model split |
| `min_height_cm` / `max_height_cm` | 120 / 230 | Height cleaning |

Reference tables: `ops.host_city`, `ops.noc_region_override`, `ops.reference_medal_count`.

## Analysis

1. The grain mistake, measured: naive medal rows against real medals per country
2. Top 10 of every medal table
3. Host effect: medals at home against the same country's average at other Games of the same season
4. Medals per 100 athletes sent

<!-- <img src="screenshots/02_medal_table.png" width="800" height="400" alt="Medal table"> -->

## Medal forecast
`06_ml/01_medal_forecast.sql` forecasts each country's medals from its previous Games of the same season, plus a host bonus: `medals = a + b × previous + c × is_host`. The host bonus is estimated first (hosts won 9.5 more medals than at their previous Games in the training years), then `a` and `b` are fitted by least squares on the rest. Trained on 1992-2010, tested on 2012-2016.

| Metric (482 country-Games) | Value |
|---|---|
| Slope b | 0.98 |
| MAE: model, all countries | 1.39 medals |
| MAE: same as last time, all countries | 1.31 |
| MAE: model, countries with 10+ medals | 5.35 |
| MAE: same as last time, countries with 10+ medals | 5.68 |

Over all countries the model is slightly worse than "same as last time", because most countries win zero or one medal and a small intercept nudges them the wrong way. For the countries that matter most to a medal table, the model is better, and the host term is the reason: Great Britain went from 48 medals to 65 at London 2012, and Russia from 15 to 33 at Sochi 2014. The model predicted 57 and 24; "same as last time" predicted 48 and 15. Brazil, which the bonus over-predicted (26 against 19), shows that a single average host effect is a simplification.

<!-- <img src="screenshots/03_forecast.png" width="800" height="400" alt="Forecast"> -->

## How to run

Copy the folder to a path without spaces, open `run_all.sql` in SSMS, switch on **Query → SQLCMD Mode**, check the `:setvar` paths (no quotes) and press **F5**.

## Git

```bash
git add sports/10_olympic_medal_table
git commit -m "Add Olympic medal table project with grain fix and medal forecast"
```

## Data

[rgriff23/Olympic_history](https://github.com/rgriff23/Olympic_history) (athlete_events.csv and noc_regions.csv, compiled from sports-reference.com), filtered to 1992-2016. Medal counts reflect results at the time of each Games, before later doping reallocations.

---

[← Back to Sports projects](../README.md) · [Portfolio home](../../README.md)
