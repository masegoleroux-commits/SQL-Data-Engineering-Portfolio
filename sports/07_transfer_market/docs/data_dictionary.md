# Data dictionary

| Source column | Silver column | Notes |
|---|---|---|
| club_name | club_name | the Premier League club whose record this is |
| club_involved_name | club_involved | the other club, often a short name |
| fee | fee_text, fee_type, fee_eur_m, loan_end_date | six kinds of value in one field |
| fee_cleaned | source_fee_eur_m | the source's own numeric fee, used to check the parser |
| transfer_movement | movement | in / out |
| transfer_period | window_name | Summer / Winter |
| year | season_start | 2019 = the 2019-20 season |
| position | source_position, position_group | mixed detail levels |
