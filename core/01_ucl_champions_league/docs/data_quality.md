# Data Quality Notes

Problems found while profiling the source files and how each is handled. The checks behind these numbers are in [`tests/03_reconciliation.sql`](../tests/03_reconciliation.sql).

## 1. Red and yellow cards are swapped in `disciplinary.csv`

| Source column | Season total | Max for one player |
|---|---|---|
| `red` | 492 | 4 |
| `yellow` | 25 | 2 |

Red cards are roughly 20 times rarer than yellows, and a player sent off four times in 13 games would be a record. The labels are the wrong way round.

**Handling:** staging keeps the columns as labelled so the file loads unchanged. `transformations/03_load_facts.sql` maps source `red` → `yellow_cards` and source `yellow` → `red_cards`. The reconciliation test checks each target column against the opposite source column.

## 2. `pass_accuracy` does not match the pass counts

For 311 of 608 rows, `pass_accuracy` differs from `pass_completed / pass_attempted` by more than one point. For 82 rows the gap is more than five points, and the largest gap is about 45 points.

Example: Erokhin (Zenit) has 26 completed from 27 attempted (96.3%), but the file says 98%.

The likely cause is that the source averages a per-match percentage instead of dividing season totals. That would explain why the gap is largest for players with few appearances.

**Handling:** the counts are treated as the truth. Completion rates in the views and analysis queries are calculated from `passes_completed / passes_attempted`. The source value is kept as `fact_distribution.pass_accuracy_src` for reference only. The test reports this as **WARN**, not FAIL.

`cross_accuracy` has no such problem: every row matches its counts to within one point.

## 3. `serial` is a rank, not a key

`defending.csv` has `serial = 01` twice (Casemiro and Éder Militão, both on 76 balls recovered). `serial` is the source's sort position, with ties sharing a value. It is kept in staging and not used anywhere else.

## 4. Column name typos

| Source | Model |
|---|---|
| `balls_recoverd` | `balls_recovered` |
| `cross_complted` | `crosses_completed` |
| `distributon.csv` (file name) | `distribution.csv` |

Staging keeps the source spelling, and the model uses the corrected names.

## 5. Checks that passed

- No duplicate player + club in any file.
- Position and matches played are consistent for the same player + club across all four files.
- `tackles = t_won + t_lost` on every row.
- Completed passes and crosses never exceed attempts.
- No negative values. No zero minutes or zero matches.
- No leading or trailing whitespace in names (trimming is still applied on load).
