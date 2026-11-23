<p align="center">
  <img src="../../assets/sports.png" alt="Sports projects" width="900">
</p>

# Boston Marathon 2016 Results

A compact SQL Server project on the full results of the 2016 Boston Marathon: 26,630 finishers and ten timing mats each. The data is mostly time stored as text, which makes it a good case for parsing, long-format modelling, checks that times add up, and anomaly detection that has to be designed carefully to work at all.

**Skills shown:** text-to-duration parsing, wide-to-long unpivot, LAG over recorded values only (bridging missing mats), reconciliation of segments to totals, ordering checks where ranks cannot be recomputed, median without `PERCENTILE_CONT`, field-relative z-scores for anomaly detection.

<!-- <img src="screenshots/01_run_all.png" width="800" height="400" alt="Run all"> -->

## Data stages

| Layer | Table | Grain |
|---|---|---|
| Bronze | `boston_marathon_2016` | the CSV as delivered |
| Silver | `runner` | one finisher (bib) |
| Silver | `split` | one finisher at one mat, text and seconds |
| Gold | `dim_runner` | one finisher with age group |
| Gold | `fact_result` | one finisher: finish, halves, negative split flag, places |
| Gold | `fact_segment` | one finisher between two consecutive recorded mats |
| ML | `split_anomaly`, `runner_pacing_profile` | flagged segments, one profile per flagged runner |

Times are converted from `H:MM:SS` text to seconds once, on the long-format split table, so the parsing expression is written once instead of ten times.

| Step | Cleaning rule | Rows |
|---|---|---|
| 1 | Missing split (`-`) set to NULL | 195 |
| 2 | Times converted to seconds | 266,105 |
| 3 | Elite bibs with a letter prefix (`F1`) kept as text | 39 |
| 4 | Runners sharing a name with another runner (bib is the key) | 139 |
| 5 | Values in a column with a blank header (not used) | 83 |
| 6 | Runners sharing an overall place (dead heat, kept as published) | 2 |

**Missing mats.** When a mat did not record a runner, the next segment runs from the last mat that did. `LAG` is applied over recorded times only, so no time is lost and every runner's segments still add up to the finish.

<!-- <img src="screenshots/02_segments.png" width="800" height="400" alt="Segments"> -->

## Quality checks

- Every finisher has 10 split rows, a finish time and an age group.
- Times always increase from mat to mat.
- Each runner's segments add up exactly to the finish time, and segment distances add up to 42.195 km.
- **Places are in finish-time order.** The obvious check, "published place = rank of finish time", fails for 19,816 runners. The reason is precision: places were decided on tenths of a second, the file gives whole seconds, and many runners finish in the same second. The check that the data can support is ordering: walking down the places, the time never goes down. That passes for overall and gender places.

## Business parameters

| Parameter | Value | Used by |
|---|---|---|
| `fastest_plausible_km_seconds` | 165 | Timing-error guard |
| `anomaly_z` | 4.0 | Pacing anomaly threshold |
| `wall_slowdown_pct` | 20 | "Hitting the wall" analysis |
| `min_country_runners` | 50 | Country report |

Reference tables `ops.age_group` (Boston qualifying bands) and `ops.checkpoint` (mat distances) can be changed the same way.

## Analysis

1. Fastest and median finish by age group and gender (median found with `ROW_NUMBER` and `COUNT`)
2. Negative splits and hitting the wall. Only 2.1% of men and 3.1% of women ran the second half faster than the first, consistent with a warm race day
3. Finishers and average time by country
4. Average pace at each mat for sub-3-hour, 3-4 hour and 4+ hour finishers

## Pacing anomaly detection
`06_ml/01_split_anomalies.sql` looks for runners who ran a stage in a way almost nobody else did.

The first design compared each segment with the runner's own average and flagged anything 3 standard deviations away. It flagged nothing, and the README keeps that finding because it is a real trap: with only 10 values per runner, no single value can be more than about 2.85 standard deviations from that runner's mean. The baseline has to be the whole field.

So each segment becomes a **relative pace** (segment pace ÷ the runner's whole-race pace). For each stage the 26,630 relative paces give a field average and spread, and a segment more than 4 standard deviations away is flagged.

| Profile | Runners |
|---|---|
| Sudden slowdown or stop | 750 |
| Fast start, then slowdown or stop | 110 |
| Fast start, heavy fade | 28 |
| Implausibly fast segment (timing error) | 0 |

Slowdowns become more common as the race goes on and peak at the 35K mat, which matches where the Newton hills end and fatigue sets in. No segment was faster than the plausibility guard, which is a useful result in itself: the timing data shows no missed-mat errors of that kind.

<!-- <img src="screenshots/03_anomalies.png" width="800" height="400" alt="Anomalies"> -->

## How to run

Copy the folder to a path without spaces, open `run_all.sql` in SSMS, switch on **Query → SQLCMD Mode**, check the `:setvar` paths (no quotes) and press **F5**.

## Git

```bash
git add sports/06_marathon_results
git commit -m "Add Boston Marathon results project with split reconciliation and anomaly detection"
```

## Data

Boston Marathon 2016 results as published by the Boston Athletic Association, collected in [rojour/boston_results](https://github.com/rojour/boston_results). Runner names are public race results; the project only uses them as labels.

---

[← Back to Sports projects](../README.md) · [Portfolio home](../../README.md)
