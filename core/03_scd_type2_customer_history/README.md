<p align="center">
  <img src="../../assets/core.png" alt="Core projects" width="900">
</p>

# Slowly Changing Customer Dimension (Type 0, 1 and 2)

Four monthly CRM snapshots loaded into a customer dimension that keeps history: when a customer moves city or changes loyalty tier, the old version is closed and a new one opens; when a name or email is corrected, every version is overwritten; when a customer disappears from the extract, a closing version records it. Orders are then linked to the version that was valid on the order date.

**Skills shown:** SCD Type 0 / 1 / 2 decided per column and stored as data, `MERGE` with `OUTPUT $action`, change detection with hashes, cleaning before comparing, guard rails, one transaction per batch, load audit, point-in-time joins, structural and behavioural tests.

<!-- <img src="screenshots/01_customer_versions.png" width="800" height="400" alt="Customer versions"> -->

## Column policy (`dbo.scd_column_policy`)

| Type | Columns | Behaviour |
|---|---|---|
| 0 | `customer_id`, `date_of_birth` | never change |
| 1 | `full_name`, `email` | corrections: overwrite on every version, no history |
| 2 | `city`, `province`, `loyalty_tier` | a change closes the current version and opens a new one |

## The load (`dbo.usp_load_dim_customer @batch_date`)

All steps run in one transaction, so a failure leaves nothing half-loaded:

0. **Guard rails**: an empty batch or one older than the last load is rejected.
1. **Stage**: values are trimmed and cased, then the Type 2 columns are hashed. `' cape town '` and `'Cape Town'` hash the same, so formatting noise never creates a false version.
2. **Profile**: new, changed, unchanged and Type 1 counts are taken before anything changes.
3. **Type 1** overwrite on all versions.
4. **Type 2** `MERGE`: inserts new customers and closes changed versions; `OUTPUT $action` captures who was closed, and a second insert adds their new versions. The old row is closed before the new one arrives, so the "one current row per customer" unique index is never violated.
5. **Deletions**: customers missing from the snapshot get a closing version flagged `is_deleted`.
6. **Audit**: one row per batch in `dbo.load_audit`.

`dbo.usp_resolve_order_keys` gives every order the customer version valid on the order date.

<!-- <img src="screenshots/02_load_audit.png" width="800" height="400" alt="Load audit"> -->

<!-- <img src="screenshots/03_point_in_time.png" width="800" height="400" alt="Point in time"> -->

## Test data with known answers

The four batches are generated with arithmetic on the customer id, so every expected number can be worked out by hand:

| Batch | Changes | Expected effect |
|---|---|---|
| 2024-01-01 | 300 customers | 300 version-1 rows |
| 2024-02-01 | `id % 17 = 0` moved city, `id % 11 = 0` tier upgrade, `id % 13 = 0` email corrected, `id % 50 = 0` missing, ids 301-325 new | Type 2 versions, Type 1 overwrites, 6 closing versions, 25 new rows |
| 2024-03-01 | tier upgrades again, customer 50 returns, `id % 7 = 0` city sent with stray spaces and case, ids 326-335 new | new versions, a re-activation, **no** change for the formatting noise |
| 2024-04-01 | identical to March | zero changes |

## Tests (`tests/04_scd_tests.sql`)

16 checks in two groups. Structural rules that must hold for any data: one current row per customer, no gaps or overlaps between versions, contiguous version numbers. Behaviour for these batches: the expected counts are derived from the change rules, not copied from the output. A rejected out-of-order batch is also tested.

<!-- <img src="screenshots/04_tests.png" width="800" height="400" alt="Tests"> -->

## How to run

Open `run_all.sql` in SSMS with **Query > SQLCMD Mode** on, check `RepoPath`, and execute. The data is generated in SQL, so no files are needed.

## Data

Synthetic, generated in `data/03_generate_monthly_snapshots.sql`; identical on every run.

---

[← Back to Core projects](../README.md) · [Portfolio home](../../README.md)
