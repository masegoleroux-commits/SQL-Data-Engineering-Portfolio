# Data dictionary

| Source column | Silver / gold | Notes |
|---|---|---|
| Bib | `bib` | text; elite women have an F prefix |
| Age, M/F | `age`, `gender` | age group from `ops.age_group` |
| 5K ... 40K, Half | `split.elapsed_seconds` | `-` when the mat missed the runner |
| Official Time | checkpoint 10 (Finish) | |
| Pace, Proj Time | not used | derivable from the finish time |
| Overall, Gender, Division | `*_place` | decided on tenths of a second |
| (blank header) | `bronze.unnamed_column` | mostly empty, not used |
