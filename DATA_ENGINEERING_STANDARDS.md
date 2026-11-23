# Data Engineering Standards

The rules every project in this repository follows. They exist so that any number in any report can be traced back to a source row, explained, and reproduced.

## 1. Layers

| Layer | SQL Server schema | Cloud equivalent | Holds | Rule |
|---|---|---|---|---|
| Configuration | `ops` / `cfg` | parameter tables, CloudFormation parameters | business parameters, reference data, logs | numbers the business may change live in a table, never in code |
| Bronze / raw | `bronze` / `raw` | `raw/` prefix in S3, external tables | data exactly as delivered, every column as text | never updated or deleted, so it can be replayed |
| Silver / staging and clean | `silver` / `stg` / `cln` | `curated/` Parquet, Iceberg | typed, standardised, de-duplicated rows | every cleaning step is logged with a row count |
| Gold / model | `gold` / `dw` | Redshift, curated Parquet tables | star schemas and marts | every table has a documented grain |
| ML | `ml` | the same, or exported | features, model output, evaluation | features use only information available at the time |

## 2. Loading

- Load to text first. A bad value must never stop a load; it is converted later with `TRY_CAST` / `TRY_CONVERT` / `try_cast` and counted.
- File paths come from SQLCMD variables (`:setvar DataPath ...`) or script parameters, never from dynamic SQL built from strings.
- Record every delivery: file name, row count, load id, time. A re-sent file is detected, not loaded twice.
- Data files keep their exact bytes (`.gitattributes`), because row terminators, fixed-width record lengths and checksums depend on them.

## 3. Cleaning

- Each rule has a code, a description and a count in a cleaning log (`step_no, table_name, step_name, rows_affected`).
- Rows that break a rule move to a quarantine table with the rule code and the source key. Nothing disappears silently.
- Rows that are incomplete but still valid (a match without statistics, an email that is malformed) are kept and flagged.
- Standardisation (team names, merchant names, country codes) uses mapping tables a data steward can edit, not `CASE` statements in code.

## 4. Modelling

- State the grain of every fact table in a comment and enforce it with a unique constraint or a test.
- Surrogate keys in dimensions; natural keys kept as attributes.
- An unknown member (`-1`) instead of NULL foreign keys.
- Type 2 history where the business needs to see the past as it was; Type 1 for corrections; the choice is recorded per column.
- Role-playing dimensions (one date dimension for several dates) through aliases or views, not copies.

## 5. Measures

- A measure (a business number such as book balance or fraud rate) is defined once, in `ops.measure_catalog`, with its description, unit and its SQL, DAX and Excel definitions side by side.
- Reports read small additive base views, not the facts directly. Ratios are calculated from summed parts (sum of numerators over sum of denominators), never by averaging ratios.
- Semi-additive measures (balances, positions) take the last period in the filter and are never summed over time. Distinct counts are never summed across groups.
- Every measure is checked by recomputing it from the fact tables by a different route.

## 6. Testing

Every project ends with tests that return `expected`, `actual` and `PASS` / `FAIL`, and the run stops on a failure (`THROW` in SQL Server, a non-zero exit code in Python validators).

- **Reconciliation**: row counts and control totals from source to target, layer by layer.
- **Integrity**: no orphan foreign keys; one current row per key in Type 2 dimensions; no gaps or overlaps in validity ranges.
- **Grain**: no duplicates at the declared grain.
- **Business rules**: points add up, balances roll forward, debits equal credits.
- **Model safety**: no feature uses information from after the prediction date; the model beats a simple baseline.

## 7. Naming and formatting

- `snake_case` for tables and columns in new work; schemas name the layer.
- Prefixes where a schema does not already say it: `stg_`, `dim_`, `fact_`, `v_` for views, `fn_` for functions, `usp_` for procedures.
- Keywords in upper case, one clause per line in long queries, explicit column lists in every `INSERT`.
- Comments explain why, not what. Every script opens with a header that says what it does and what it expects.
- Line endings: CRLF for `.sql` and `.ps1`, LF for everything else.

## 8. Portability

Projects target SQL Server 2019 or later, including Express. 2022-only features are avoided. Within the sports and banking projects:

- one `DECLARE` per variable, set from a literal or a scalar subquery;
- no cursors, `WHILE` loops, temporary tables or table variables: set-based SQL and work tables in a schema;
- `CONCAT` for strings, `CROSS APPLY (VALUES ...)` for unpivots, `1.0 *` to force decimal division;
- recursive CTEs always with `OPTION (MAXRECURSION n)`.

These rules let the scripts be checked automatically by translating them to PostgreSQL and running them.

## 9. Cloud projects

- Infrastructure as code (CloudFormation), checked with `cfn-lint`.
- Credentials in Secrets Manager or generated by the service; never in a script or the repository.
- Least privilege: one IAM role per service, scoped to the bucket prefixes it needs.
- Cost controls in every stack: workgroup scan limits, usage limits, budgets, and a clean-up script.
- Every project can be validated locally (DuckDB, PostgreSQL or Spark) before any AWS resource exists.

## 10. Data honesty

- Real public datasets are credited with their licence.
- Synthetic data is labelled as synthetic, generated with a fixed seed, and the problems built into it are listed.
- READMEs state what was tested, how, and what was not.
