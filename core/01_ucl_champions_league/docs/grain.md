# Grain Definitions

Every table has one stated grain. If a query returns more rows than the grain allows, something upstream is wrong. The checks in [`tests/01_grain_checks.sql`](../tests/01_grain_checks.sql) enforce each of these.

| Table | Grain (one row per…) | Enforced by | Rows |
|---|---|---|---|
| `stg_attacking` | player + club, players with ≥ 1 assist | duplicate check | 176 |
| `stg_defending` | player + club | duplicate check | 627 |
| `stg_distribution` | player + club | duplicate check | 608 |
| `stg_disciplinary` | player + club | duplicate check | 584 |
| `dim_club` | club | `uq_dim_club_name` | 32 |
| `dim_player` | player + club | `uq_dim_player_nk` | 704 |
| `fact_attacking` | player + club (season 2021/22) | `pk_fact_attacking` on `player_key` | 176 |
| `fact_defending` | player + club (season 2021/22) | `pk_fact_defending` on `player_key` | 627 |
| `fact_distribution` | player + club (season 2021/22) | `pk_fact_distribution` on `player_key` | 608 |
| `fact_discipline` | player + club (season 2021/22) | `pk_fact_discipline` on `player_key` | 584 |
| `vw_player_season` | `dim_player` row | row-count test vs `dim_player` | 704 |
| `vw_club_season` | `dim_club` row | row-count test vs `dim_club` | 32 |

## Why "player + club" and not "player"

The source files identify players by display name only, with no player ID.

- **Same name, different people.** `Martínez` appears at Ajax, Inter and Leipzig. `Mendy` appears at Chelsea and Real Madrid.
- **Same person, two clubs.** Luis Díaz (Porto → Liverpool) and Reinildo (LOSC → Atlético) moved in January 2022 and appear once for each club.

Keying on name alone would merge different players into one row and inflate their totals. Name + club is the narrowest key the data supports, and it is unique in all four files.

The trade-off: a player who changed clubs mid-season shows up as two `dim_player` rows. To see one combined line for that player, aggregate by `player_name` and accept that it also merges any genuine namesakes.

## Why four facts and not one wide fact

Coverage differs by file. Only 176 players have attacking rows (the source lists players with at least one assist), while 627 have defending rows. A single wide fact would need hundreds of NULL measures, and NULL would mean two things: "zero" and "not in the file". Separate facts sharing conformed dimensions keep the meaning clear. The views join them back together when a question needs more than one area.
