# Q9 – Farmer Cooperative Maize Deliveries (schema `q9`)

**Purpose:** price deliveries consistently (A = K5/kg, B = K4/kg, C = K3/kg), including for direct SQL inserts.

## Objects
| Part | Object | What it does |
|---|---|---|
| (a) | `farmers`, `deliveries`, `daily_purchases` | numeric weight/money, grade CHECK (A/B/C); 3 farmers, 6 deliveries across all grades and both paid states, loaded after the trigger exists |
| (b) | `fn_maize_rate(grade)` | returns the rate; rejects NULL or unsupported grade |
| (c) | `pr_receive_delivery(farmer, grade, weight, date)` | validates inputs, inserts basic fields with `is_paid = FALSE`; the trigger sets rate and total |
| (d) | `trg_deliveries_price` | BEFORE INSERT OR UPDATE; rejects weight ≤ 0, sets `unit_rate` and `total_value` |
| (e) | `v_farmer_amount_due` | LEFT JOIN + `SUM(...) FILTER (WHERE NOT is_paid)` with `COALESCE` → 0 for no unpaid |
| (f) | `idx_deliveries_farmer_date (farmer_id, delivered_on)` | farmer + date-range queries |
| (g) | `pr_refresh_purchases(day)` + job `q9_refresh_purchases` | upsert; cron `30 1 * * *` for yesterday |

## Note
Rate/total columns are `NOT NULL`; the procedure and seed rows pass `0` placeholders that the BEFORE trigger overwrites.
