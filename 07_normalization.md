# Normalization: from the paper sales register to BCNF

The pharmacy currently records every sale in one wide register. This document starts from that register and normalizes it step by step. The final tables match `01_schema.sql`.

## 0. Unnormalized form (UNF)

One register row per sale, with the medicines of that sale repeated inside the row:

```
SALE_REGISTER(
  sale_id, sale_date, payment_mode, total_amount,
  customer_name, customer_phone,
  staff_name, staff_role,
  { medicine_name, generic_name, category, manufacturer, medicine_price, reorder_level,
    requires_prescription,
    batch_no, received_date, expiry_date, stock_left, purchase_price,
    supplier_name, supplier_phone, supplier_city,
    quantity, sold_price }          <-- repeating group
)
```

Problems: the repeating group cannot be stored in a relational column, and the medicine, supplier and customer details are retyped on every sale (update, insert and delete anomalies).

## 1NF: remove the repeating group

Give every medicine line its own row and repeat the sale columns on each. Atomic values only, no repeating groups.

```
SALE_LINE(sale_id, medicine_name, manufacturer, batch_no, sale_date, payment_mode, total_amount,
          customer_name, customer_phone, staff_name, staff_role,
          generic_name, category, medicine_price, reorder_level, requires_prescription,
          received_date, expiry_date, stock_left, purchase_price,
          supplier_name, supplier_phone, supplier_city,
          quantity, sold_price)
```

Candidate key: `(sale_id, medicine_name, manufacturer, batch_no)`.

Functional dependencies (FDs) that hold:

| # | Determinant | Determines |
|---|---|---|
| F1 | sale_id | sale_date, payment_mode, total_amount, customer_phone, staff_name |
| F2 | customer_phone | customer_name |
| F3 | staff_name | staff_role |
| F4 | (medicine_name, manufacturer) | generic_name, category, medicine_price, reorder_level, requires_prescription |
| F5 | (medicine_name, manufacturer, batch_no) | received_date, expiry_date, stock_left, purchase_price, supplier_phone |
| F6 | supplier_phone | supplier_name, supplier_city |
| F7 | (sale_id, medicine_name, manufacturer, batch_no) | quantity, sold_price |

## 2NF: remove partial dependencies

A table is in 2NF when no non-key column depends on only part of the key. In `SALE_LINE`, F1 and F4 and F5 are partial dependencies (they depend on part of the 4-column key). Split along them:

```
SALE(sale_id PK, sale_date, payment_mode, total_amount, customer_phone, customer_name, staff_name, staff_role)   -- from F1
MEDICINE(medicine_name, manufacturer PK, generic_name, category, medicine_price, reorder_level, requires_prescription) -- from F4
BATCH(medicine_name, manufacturer, batch_no PK, received_date, expiry_date, stock_left, purchase_price,
      supplier_phone, supplier_name, supplier_city)                                                                  -- from F5
SALE_ITEM(sale_id, medicine_name, manufacturer, batch_no PK, quantity, sold_price)                                    -- from F7
```

Now every non-key column in each table depends on that table's whole key.

## 3NF: remove transitive dependencies

3NF removes non-key columns that depend on another non-key column.

| Table | Transitive dependency | Fix |
|---|---|---|
| SALE | sale_id → customer_phone → customer_name (F2) | New table `customers` |
| SALE | sale_id → staff_name → staff_role (F3) | New table `staff` |
| MEDICINE | key → category (a free-text value that repeats across medicines) | New table `categories` |
| BATCH | key → supplier_phone → supplier_name, supplier_city (F6) | New table `suppliers` |

Natural keys such as `customer_phone` and the long composite medicine key are replaced by surrogate integer keys (`customer_id`, `medicine_id`, `batch_id`, ...). The natural keys stay as `UNIQUE` constraints:

- `customers.phone`
- `medicines (name, manufacturer)`
- `batches (medicine_id, batch_no)`

## 4. BCNF check

A table is in BCNF when every determinant is a candidate key. Checking each final table:

| Table | Candidate keys | Other determinants? | BCNF |
|---|---|---|---|
| categories | category_id, name | none | Yes |
| suppliers | supplier_id, phone, email | none | Yes |
| staff | staff_id, phone | none | Yes |
| customers | customer_id, phone, email | none | Yes |
| medicines | medicine_id, (name, manufacturer) | none | Yes |
| batches | batch_id, (medicine_id, batch_no) | none | Yes |
| sales | sale_id | none | Yes |
| sale_items | sale_item_id, (sale_id, batch_id) | none | Yes |
| purchase_orders | po_id | none | Yes |
| purchase_order_items | po_item_id, (po_id, medicine_id) | none | Yes |
| demand_forecasts | forecast_id, (medicine_id, forecast_month) | none | Yes |
| stock_alerts | alert_id | none | Yes |

`sale_items` stores only `batch_id`, not `medicine_id`: the medicine is reachable through `batches`. Storing both would create the dependency `batch_id → medicine_id` inside `sale_items`, which is not on a key and would break 3NF.

## 5. Deliberate, controlled redundancy

Three columns are not strictly normalized. Each one is a design choice with a mechanism that keeps it correct.

| Column | Why it is kept | What keeps it correct |
|---|---|---|
| `sale_items.unit_price` | It is a snapshot of the price at the time of sale. `medicines.unit_price` changes over time, so this is history, not duplicate data. | Filled from `medicines.unit_price` by trigger `trg_validate_sale_item` when not supplied. |
| `sales.total_amount` | Derived from the sale lines. Stored so receipts and revenue reports do not re-sum every time. | `trg_apply_sale_item` adds each line's value in the same transaction. Query Q7 and Q10 rely on it. |
| `batches.quantity_in_stock` | A running balance. It could be derived from purchases minus sales, but the live check "can I sell 5 of this batch?" must be fast and lockable. | `CHECK (quantity_in_stock >= 0)`, a row lock in `trg_validate_sale_item` (`FOR UPDATE`), and the decrement in `trg_apply_sale_item`, all inside the sale's transaction. |

## 6. Summary of the decomposition

```
SALE_REGISTER (UNF)
   |  1NF: one row per medicine line
   v
SALE_LINE
   |  2NF: split by partial dependencies
   v
SALE, MEDICINE, BATCH, SALE_ITEM
   |  3NF: split by transitive dependencies
   v
customers, staff, categories, suppliers  (+ the four above)
   |  BCNF check: every determinant is a candidate key
   v
12 tables in 01_schema.sql
   (the 4 purchasing and AI tables - purchase_orders, purchase_order_items,
    demand_forecasts, stock_alerts - are new entities, not splits of the register)
```
