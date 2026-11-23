<p align="center">
  <img src="../../assets/sports.png" alt="Sports projects" width="900">
</p>

# Match Tracking Data

A compact SQL Server project on optical tracking data from a full professional football match: the position of all 22 players and the ball, sampled 5 times a second, plus the hand-coded event log. 29,000 samples, 638,022 player positions, 1,745 events. The data engineering here is about awkward file layouts, physics-based cleaning and joining two independent sources that describe the same match.

**Skills shown:** multi-row header files, metadata-driven unpivot, unit conversion, LAG-based speed with gap handling, physical plausibility rules, gaps and islands for sprint detection, set-based nearest-neighbour search, cross-source validation.

<!-- <img src="screenshots/01_run_all.png" width="800" height="400" alt="Run all"> -->

## The file layout problem

Each tracking file has three header rows, and every player has two columns with **no name** (x, then y):

```
,,,Home,,Home,,Home,, ...
,,,11,,1,,2,, ...
Period,Frame,Time [s],Player11,,Player1,,Player2,, ... ,Ball,
1,5,0.2,0.00082,0.48238,0.32648,0.65322, ...
```

Loading by header name is impossible. `01_bronze/01_load_bronze.sql` loads the data rows from row 4 into generic slot columns (`slot01_x`, `slot01_y` ...) and loads rows 1 to 3 separately with `FIRSTROW = 1, LASTROW = 3`. Silver then reads row 3 to find which player is in which slot. Nothing about the squad is hard-coded, so a different match file loads the same way.

## Data stages

| Layer | Table | Grain |
|---|---|---|
| Bronze | `tracking_home`, `tracking_away` (+ header tables), `match_events` | files as delivered |
| Silver | `player_slot` | one team slot → one player |
| Silver | `player_position` | one player at one sample, metres |
| Silver | `ball_frame` | one sample |
| Silver | `match_event` | one event, snapped to a stored sample |
| Gold | `fact_player_sample` | one player at one sample, with step distance and speed |
| Gold | `fact_sprint` | one sprint |
| Gold | `dim_player` | one player with totals |
| ML | `inferred_possession` | one sample, with the team in possession |

| Step | Cleaning rule | Rows |
|---|---|---|
| 1 | Player slots read from header row 3 | 28 |
| 2 | Wide x / y pairs unpivoted to rows | 812,028 |
| 3 | `NaN` positions removed (substitutes not yet on, players replaced) | 174,006 |
| 3 | Samples with no ball position | 11,346 |
| 4 | Coordinates converted from 0-1 to metres on a 105 × 68 pitch | 638,022 |
| 5 | Event frames snapped to the nearest stored sample | 1,384 |

**Speed and glitches.** Speed is distance since the previous sample ÷ 0.2 s, calculated only when the previous sample is exactly 5 frames earlier, so a player coming on as a substitute does not start with a teleport. Any speed above 10.5 m/s (37.8 km/h, faster than any recorded footballer) is a tracking glitch: 107 samples are flagged and kept out of distances and sprints.

**Sprints** are found with gaps and islands: for samples above 7 m/s, `frame / 5 − ROW_NUMBER()` is constant along an unbroken run, so it labels each sprint. Runs shorter than one second are dropped.

<!-- <img src="screenshots/02_sprints.png" width="800" height="400" alt="Sprints"> -->

## Quality checks

- Home and away files cover the same samples and frame numbers.
- The ball appears in both files and is in exactly the same place in every sample.
- 14 player slots per team; never more than 11 players from one team on the pitch at once.
- Every player named in an event exists in the tracking data; every event's sample frame exists.
- Sprints never overlap for one player.

## Business parameters

| Parameter | Value | Used by |
|---|---|---|
| `pitch_length_m` / `pitch_width_m` | 105 / 68 | Conversion to metres |
| `frame_step` / `seconds_per_sample` | 5 / 0.2 | Speed |
| `max_human_speed` | 10.5 m/s | Glitch rule |
| `high_speed_ms` | 5.5 m/s | High-speed distance |
| `sprint_speed_ms` / `min_sprint_samples` | 7.0 m/s / 5 | Sprint detection |
| `control_distance_m` | 2.0 | Possession inference |
| `event_match_distance_m` | 5.0 | Event vs tracking agreement |

## Analysis

1. Distance, high-speed distance, sprints and top speed per player. The busiest players cover about 11.2 km, in line with published figures for professional midfielders
2. Team distance and sprints, first half against second
3. Team shape: average width, depth and area of the outfield players
4. Most frequent passing pairs
5. **Event log vs tracking:** at the moment each pass is logged, the passer should be next to the ball. For 775 passes, 99% have the passer within 5 m, which shows the two sources line up and points to the few passes worth reviewing

<!-- <img src="screenshots/03_physical.png" width="800" height="400" alt="Physical"> -->

## Possession inference
`06_ml/01_possession_inference.sql` works out who has the ball from positions alone:

1. For every sample, the distance from the ball to all 22 players is calculated and `ROW_NUMBER` picks the nearest.
2. If that player is within 2 m, his team is in control; otherwise the ball is loose.
3. Possession carries forward through loose samples until the other team touches the ball, using a running `MAX` of the last frame anyone was in control.

| Result | Value |
|---|---|
| Samples with the ball visible | 17,655 |
| Samples with a player in control | 66% |
| Home possession from tracking | 51.1% |
| Home share of the event log | 52.6% |
| Passes where tracking agrees with the event's team | 96% |

Tracking alone reproduces the coded possession picture to within about 1.5 points and agrees with the passing team 96% of the time, with no manual coding.

<!-- <img src="screenshots/04_possession.png" width="800" height="400" alt="Possession"> -->

## How to run

Copy the folder to a path without spaces, open `run_all.sql` in SSMS, switch on **Query → SQLCMD Mode**, check the `:setvar` paths (no quotes) and press **F5**.

## Git

```bash
git add sports/08_match_tracking_data
git commit -m "Add match tracking project with sprint detection and possession inference"
```

## Data

[Metrica Sports sample data](https://github.com/metrica-sports/sample-data), Sample Game 1 (anonymised teams and players), reduced from 25 to 5 samples per second.

---

[← Back to Sports projects](../README.md) · [Portfolio home](../../README.md)
