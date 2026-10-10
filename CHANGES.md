# Changes made after review

All changes were tested on a clean PostgreSQL 16 database: rebuild runs with no errors, all 16 queries run, and all 18 tests in `06_constraint_tests.sql` pass.

| File | Change | Why |
|---|---|---|
| `02_functions_triggers.sql` | New trigger function `fn_resolve_low_stock_alert()` with two triggers on `batches` (`trg_resolve_alert_on_new_batch`, `trg_resolve_alert_on_restock`) | Low-stock alerts were never resolved, so one open alert blocked every later alert for that medicine. They now close when stock is back at or above the reorder level. |
| `02_functions_triggers.sql` | New function `fn_generate_low_stock_alerts()` | The low-stock trigger only fires when stock goes down, so a medicine loaded already low (Amaryl 2mg) had no alert. |
| `02_functions_triggers.sql` | Expiry-alert de-duplication now matches `% batch <no> (%` | The old pattern could confuse batch numbers like PO2-1 and PO2-10. |
| `03_sample_data.sql` | After the sales are inserted, each batch's `received_date` is moved to the day before its first sale if the sale was earlier | 13 sale lines were dated before their batch was received. |
| `03_sample_data.sql` | Runs `fn_generate_low_stock_alerts()` and `fn_generate_expiry_alerts(30)` at the end | The demo now starts with 3 low-stock, 3 near-expiry and 4 expired alerts, matching the views. |
| `04_queries.sql` | Q12 fills months with no sales with 0 before averaging; Q7 comment corrected | The moving average skipped quiet months. |
| `06_constraint_tests.sql` | One new test: restocking resolves the open low-stock alert (now 18 tests) | Covers the new trigger. |
| `07_normalization.md` | Added `category_description` and dependency F8 (category determines category_description) | Splitting out `categories` is now a real 3NF step, not just a design choice. |
| `README.md` | Updated file table, test count and business rules | Matches the changes above. |

Not changed on purpose: purchase orders 4 to 10 are marked `received` without matching batches. Receiving them would add insulin stock and remove the low-stock demo.
