# Pharmacy Inventory, Expiry and Demand Forecasting Database

PostgreSQL 14+ (tested on 16).

## Rebuild from scratch

```bash
chmod +x rebuild.sh
./rebuild.sh            # creates database "pharmacy"; pass another name as the first argument
```

Or by hand, in this order:

```bash
createdb pharmacy
psql -d pharmacy -v ON_ERROR_STOP=1 -f 01_schema.sql
psql -d pharmacy -v ON_ERROR_STOP=1 -f 02_functions_triggers.sql
psql -d pharmacy -v ON_ERROR_STOP=1 -f 03_sample_data.sql
```

`01_schema.sql` begins with `DROP SCHEMA public CASCADE`, so only run it on a database you are happy to wipe.

## Files

| File | What it is |
|---|---|
| `01_schema.sql` | 12 tables, constraints, indexes, 3 views |
| `02_functions_triggers.sql` | 5 triggers, `fn_generate_expiry_alerts()`, `fn_generate_low_stock_alerts()`, `fn_receive_purchase_order()` |
| `03_sample_data.sql` | Seed data with expired, near-expiry and low-stock rows (dates relative to today) |
| `04_queries.sql` | 16 labelled queries (joins, subqueries, windows, CTEs) |
| `05_transactions.sql` | COMMIT, ROLLBACK, SAVEPOINT and multi-table transaction demos. Run once per rebuild |
| `06_constraint_tests.sql` | 18 PASS/FAIL tests proving the constraints and triggers reject bad data |
| `07_normalization.md` | UNF to 1NF to 2NF to 3NF to BCNF write-up |
| `er_diagram.png` / `.dot` / `.mmd` | ER diagram (image, Graphviz source, Mermaid source) |

## Business rules enforced in the database

- A sale line is rejected if its batch is expired or the quantity exceeds the batch stock (`trg_validate_sale_item`).
- A successful sale line reduces batch stock and adds to `sales.total_amount` (`trg_apply_sale_item`).
- A low-stock alert is created when sellable stock drops below `reorder_level` (`trg_low_stock_alert`).
- A low-stock alert is resolved automatically when new stock arrives (a batch is inserted or its quantity goes up) and sellable stock is back at or above `reorder_level` (`trg_resolve_alert_on_new_batch`, `trg_resolve_alert_on_restock`).
- `SELECT fn_generate_expiry_alerts(30);` creates `near_expiry` and `expired` alerts, and `SELECT fn_generate_low_stock_alerts();` creates low-stock alerts for medicines that are already below their reorder level. The sample data runs both at the end.

## Contracts for the Python scripts

- `demand_forecasts` has `UNIQUE (medicine_id, forecast_month)` and `forecast_month` must be the 1st of a month, so the forecast script can upsert with
  `INSERT ... ON CONFLICT (medicine_id, forecast_month) DO UPDATE SET predicted_qty = EXCLUDED.predicted_qty, method = EXCLUDED.method, generated_at = now()`.
- Insert sales only through `sales` plus `sale_items`; never write `batches.quantity_in_stock` or `sales.total_amount` directly. Leave `sale_items.unit_price` out and the trigger fills it.
- Views for the app: `v_medicine_stock`, `v_low_stock`, `v_expiry_status`.
