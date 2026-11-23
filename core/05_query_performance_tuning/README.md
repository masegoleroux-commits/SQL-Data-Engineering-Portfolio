<p align="center">
  <img src="../../assets/core.png" alt="Core projects" width="900">
</p>

# Query Performance Tuning: Measured, Not Guessed

Seven slow queries that show up in almost every transactional system, run against 2 million orders and 200,000 customers. Each one is measured before tuning, fixed with the smallest change that works, measured again under the same conditions, and tested: the tuned query must return exactly the same rows, run at least twice as fast, read far fewer pages, and use the index designed for it.

**Skills shown:** benchmark harness with warm-up and median timing, logical reads as the stable measure, result checksums, reading execution plans from the plan cache, SARGable predicates, covering and filtered indexes, keyset pagination, monthly partitioning with partition elimination, control experiments.

<!-- <img src="screenshots/02_results.png" width="800" height="400" alt="Results"> -->

## The seven problems

| Code | Question | Why it is slow | Fix |
|---|---|---|---|
| S1 | Daily revenue for June 2024 | `YEAR(order_ts)` and `MONTH(order_ts)` hide the column inside functions, so no index can be searched | a date range on the bare column, with a covering index |
| S2 | Last 10 orders of one customer | no index on `customer_id`: 2 million rows scanned to find about 10 | index on `(customer_id, order_ts)` |
| S3 | Value of returned orders in March 2024 | a plain index on `order_ts` still needs a key lookup per row for `status` and `amount` | covering index with `INCLUDE` |
| S4 | Oldest 50 pending orders | only 0.5% are pending, but the whole table is scanned and sorted | filtered index `WHERE status = 'PENDING'` |
| S5 | Find a customer by email, ignoring case | `LOWER(email) = ...` blocks the index, and is unnecessary under a case-insensitive collation | plain equality, index on `email` |
| S6 | Page 30,001 of the order list | `OFFSET 1,500,000` reads 1.5 million rows and throws them away | keyset pagination (`WHERE order_id > @last_seen`) |
| S7 | Channel revenue for November 2024 | a one-month report reads two years | monthly partitioning on `order_ts`, so only one partition is read |

Two control experiments run the original S1 and S5 queries after the new indexes exist, to show that the index alone does not help while the predicate still wraps the column in a function.

<!-- <img src="screenshots/01_plan_before.png" width="800" height="400" alt="Plan before"> -->

<!-- <img src="screenshots/03_plan_after.png" width="800" height="400" alt="Plan after"> -->

<!-- <img src="screenshots/04_partitions.png" width="800" height="400" alt="Partitions"> -->

## The harness (`perf.usp_benchmark`)

1. Runs the query once to warm the cache (not recorded).
2. Runs it again a set number of times, recording elapsed time and logical reads (8 KB pages touched, far more stable than time across machines).
3. Stores a checksum of the result rows, so the tuned query can be proven to return what the slow one did.
4. Saves the execution plan from the plan cache, so a test can check which index the optimiser actually used.
5. Keeps the median time, so one slow run does not distort the result.

## Tests (`tests/09_test_tuning_results.sql`)

Every tuned query: same result checksum as the slow one; at least `min_speedup` (a business parameter, default 2) times faster; far fewer logical reads; the expected index appears in the saved plan.

<!-- <img src="screenshots/05_tests.png" width="800" height="400" alt="Tests"> -->

## Results

`reports/08_results_report.sql` produces the before/after table. Times depend on the machine; logical reads do not. Fill this in from your own run:

| Scenario | Reads before | Reads after | Time before (ms) | Time after (ms) |
|---|---:|---:|---:|---:|
| S1 | | | | |
| S2 | | | | |
| S3 | | | | |
| S4 | | | | |
| S5 | | | | |
| S6 | | | | |
| S7 | | | | |

## How to run

Open `run_all.sql` in SSMS with **Query > SQLCMD Mode** on, check `RepoPath`, and execute. It takes a few minutes and needs about 300 MB. Reading plans from the cache needs `VIEW SERVER STATE`, which a local administrator login has. Partitioning works in every edition, including Express, since SQL Server 2016 SP1.

## Data

Synthetic, generated in SQL from a hash of the row number; identical on every run.

---

[← Back to Core projects](../README.md) · [Portfolio home](../../README.md)
