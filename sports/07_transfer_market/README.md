<p align="center">
  <img src="../../assets/sports.png" alt="Sports projects" width="900">
</p>

# Premier League Transfer Market

A compact SQL Server project on 30 years of Premier League transfers (1992-93 to 2022-23): 23,675 rows recorded from each club's side. Two problems make the raw file unsafe to sum: the fee column mixes six kinds of value in one text field, and moves between two Premier League clubs are recorded twice under different club names. The project parses the first and resolves the second by learning club aliases from the data.

**Skills shown:** pattern-based text parsing, reconciliation against the source's own derived column, exact-duplicate removal, alias learning from evidence, mirror-row de-duplication, two fact tables at two different grains, an inflation index.

<!-- <img src="screenshots/01_run_all.png" width="800" height="400" alt="Run all"> -->

## The fee column

| Text in the source | fee_type | Parsed value (EUR m) |
|---|---|---|
| `€5.4m` | permanent | 5.4 |
| `€910Th.` / `€500k` | permanent | 0.91 / 0.5 |
| `Loan fee:€1.2m` | loan with fee | 1.2 |
| `loan transfer` | loan | |
| `free transfer` | free | |
| `End of loanMay 31, 2019` | loan return | date parsed to 2019-05-31 |
| `?`, `-`, blank | unknown | |

The parser in `02_silver/01_parse_transfers.sql` is checked against `fee_cleaned`, a number the source already provides: every one of the 5,758 parsed fees matches it.

## Two names for one club

When Leicester buy a player from Tottenham, Leicester's record says "in, from **Spurs**" and Tottenham's says "out, to **Leicester**". The other club is written in a short form ("Spurs", "Man Utd", "Sheff Wed") that never matches the full names ("Tottenham Hotspur").

`02_silver/02_learn_club_aliases.sql` learns the mapping from those mirrored pairs. Every pair with the same player, season, window and fee text is one vote that Leicester's short name for the other club is that club's full name. A short name is linked when it has at least 3 votes and the winner holds at least 90% of them.

| Short name | Learned full name | Votes | Share |
|---|---|---|---|
| Spurs | Tottenham Hotspur | 216 | 1.00 |
| Man Utd | Manchester United | 162 | 1.00 |
| Man City | Manchester City | 155 | 1.00 |
| Aston Villa | Aston Villa | 194 | 0.99 |

48 aliases learned. The stray votes (a player who passed through a third club in the same window, or values like "Without Club") are filtered out by the two thresholds and a non-club list. A mapping that would normally be typed by hand is inferred, scored and explained.

<!-- <img src="screenshots/02_aliases.png" width="800" height="400" alt="Aliases"> -->

## Data stages

| Layer | Table | Grain |
|---|---|---|
| Bronze | `premier_league_transfers` | CSV as delivered |
| Silver | `transfer_row` | one club's record of one move |
| Silver | `club_alias_vote`, `club_alias` | votes; one short name → one full name |
| Gold | `fact_club_transfer` | one club's side of one move (for spending) |
| Gold | `fact_transfer` | one move, mirrors removed (for totals and counts) |

Choosing the right grain is the point of having both. "How much did Chelsea spend?" needs every Chelsea row. "How much money moved in 2019?" must count a Chelsea-Arsenal fee once, not twice. 1,758 mirror rows separate the two answers.

| Step | Cleaning rule | Rows |
|---|---|---|
| 1 | Exact duplicate rows removed | 13 |
| 2 | Fee type assigned (permanent 5,304, loan 5,610, loan return 5,933, free 3,282, loan with fee 454, unknown 3,079) | 23,662 |
| 3 | Fees parsed to EUR millions | 5,758 |
| 4 | Loan end dates parsed | 5,933 |
| 5 | Age `NA` → NULL | 15 |
| 6 | Broad positions (`defence`, `midfield`, `attack`) mapped to a group | 887 |
| 7 | Short club names linked to a full name | 48 |
| 8 | Short names with votes that were not linked | 4 |

## Quality checks

- Every distinct bronze row reaches silver; every fee text matches a known pattern; every paid fee parses to a number.
- **Parsed fee = the source's cleaned fee** for every row.
- Every position maps to a group; every learned alias points to a real Premier League club.
- `fact_transfer` = club rows minus mirrors, and every mirror pairs with exactly one buying-club row. The pairing includes fee type and amount, because a player can join on loan and sign permanently in the same window (Chris Kirkland, Liverpool to Wigan, 2006).

## Business parameters

| Parameter | Value | Used by |
|---|---|---|
| `alias_min_evidence` | 3 | Alias learning |
| `alias_min_share` | 0.90 | Alias learning |
| `fee_tolerance` | 0.001 | Fee reconciliation |
| `big_fee_millions` | 50 | Major signings report |
| `base_year` | 1993 | Fee inflation index |

Reference tables: `ops.non_club_value`, `ops.position_group`.

## Analysis

1. Net spend by club, all seasons and per season
2. Fee inflation index: the average known permanent fee went from €0.86m in 1993-94 to €19.2m in 2022-23, an index of about 2,200
3. Major signings (the record is Philippe Coutinho, Liverpool to Barcelona, €135m)
4. How moves are done over time: loans, free transfers, fees and unknown fees
5. Average fee and age by position since 2015

<!-- <img src="screenshots/03_inflation.png" width="800" height="400" alt="Inflation"> -->

## How to run

Copy the folder to a path without spaces, open `run_all.sql` in SSMS, switch on **Query → SQLCMD Mode**, check the `:setvar` paths (no quotes) and press **F5**.

## Git

```bash
git add sports/07_transfer_market
git commit -m "Add transfer market project with fee parsing and learned club aliases"
```

## Data

Transfer records scraped from Transfermarkt by [ewenme/transfers](https://github.com/ewenme/transfers). Fees are as reported by Transfermarkt and are estimates where clubs did not disclose them.

---

[← Back to Sports projects](../README.md) · [Portfolio home](../../README.md)
