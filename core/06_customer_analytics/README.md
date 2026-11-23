<p align="center">
  <img src="../../assets/core.png" alt="Core projects" width="900">
</p>

# Customer Analytics for an Online Shop

Two years of orders for an online coffee and kitchen shop, analysed the way a marketing or e-commerce team would ask: who are our best customers, do new customers come back, which channel brings customers worth keeping, what sells together, and who is about to stop buying. Every answer is SQL, and every analysis is backed by a test that would fail if a join or window frame were wrong.

**Skills shown:** RFM segmentation with `NTILE`, cohort retention grids, `LAG`, running totals, moving averages, `PERCENTILE_CONT`, Pareto analysis, market basket support / confidence / lift, `GROUPING SETS`, a churn model with a train and test snapshot, business parameters, analytical tests.

<!-- <img src="screenshots/02_cohort_grid.png" width="800" height="400" alt="Cohort grid"> -->

## Analyses

| File | Question |
|---|---|
| `analysis/02_rfm_segmentation.sql` | Score every customer 1 to 5 on recency, frequency and monetary value, and name the segments (Champions, Loyal, Needs attention, At risk, Hibernating) |
| `analysis/03_cohort_retention.sql` | Of the customers who first bought in a given month, what share bought again one, two, three months later? |
| `analysis/04_purchase_behaviour.sql` | Month-on-month change, running totals, three-month moving averages, median days between orders |
| `analysis/05_pareto_and_value.sql` | What share of revenue comes from the top 20% of customers, and which acquisition channel brings the most valuable ones |
| `analysis/06_market_basket.sql` | Which products are bought together more than chance would suggest |
| `analysis/07_executive_summary.sql` | Revenue by year and province with subtotals and a grand total in one pass |
| `ml/08_churn_model.sql` | Which customers are about to stop buying |

<!-- <img src="screenshots/01_rfm_segments.png" width="800" height="400" alt="Rfm segments"> -->

<!-- <img src="screenshots/03_market_basket.png" width="800" height="400" alt="Market basket"> -->

## The churn model

Features are built only from orders on or before a snapshot date, and the label is whether the customer ordered in the following `churn_days` (180). The model learns churn rates per recency band and frequency band on the 31 December 2023 snapshot and is tested on the 30 June 2024 snapshot against what really happened. It is deliberately simple and explainable to a marketing manager, and it sets the baseline a more complex model would have to beat. The top `high_risk_share` (20%) of customers by predicted risk form the retention campaign list.

<!-- <img src="screenshots/04_churn_evaluation.png" width="800" height="400" alt="Churn evaluation"> -->

## Business parameters (`analytics.business_parameter`)

Analysis date (fixed, so results are reproducible), churn window (180 days), minimum orders before a product pair is reported (30), cohort cut-off for channel comparisons, the two churn snapshots, and the high-risk share.

## Behaviour built into the data

So the analyses have something real to find: every customer has an active lifetime after which they stop buying; referral customers tend to stay longer and social-ads customers shorter; December has extra gift orders; some products are usually bought together.

## Tests (`tests/09_test_analytics.sql`)

20 checks on things that must be true if the logic is right: every buyer appears in exactly one RFM group and `NTILE` groups differ in size by at most one; cohort sizes add up to all buyers and retention never exceeds 100%; the Pareto curve never goes down and ends at exactly 100%; running spend ends at lifetime spend; `GROUPING SETS` subtotals add up to the grand total; the four product pairs built into the data are the top four by lift; churn features use no orders after the snapshot; the model beats the base rate on Brier score and its high-risk list finds churners better than random.

<!-- <img src="screenshots/05_tests.png" width="800" height="400" alt="Tests"> -->

## How to run

Open `run_all.sql` in SSMS with **Query > SQLCMD Mode** on, check `RepoPath`, and execute. The data is generated in SQL.

## Data

Synthetic, generated with a deterministic hash function (`dbo.fn_rand`), so every run on every machine produces the same orders.

---

[← Back to Core projects](../README.md) · [Portfolio home](../../README.md)
