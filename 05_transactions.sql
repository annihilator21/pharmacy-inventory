-- =====================================================================
-- 05_transactions.sql  |  Transaction demos for the report
-- Run with:  psql -d pharmacy -f 05_transactions.sql
-- Do NOT use ON_ERROR_STOP for this file: Demo 2 contains one error on
-- purpose and recovers from it with a savepoint.
-- Run once on a freshly built database (Demo 4 uses purchase order 2).
-- =====================================================================

\echo '--- Demo 1: successful sale, COMMIT ---'
\echo 'Stock before:'
SELECT batch_id, quantity_in_stock FROM batches WHERE batch_id IN (1, 12);

BEGIN;
    INSERT INTO sales (customer_id, staff_id, payment_mode)
    VALUES (1, 2, 'upi')
    RETURNING sale_id \gset
    INSERT INTO sale_items (sale_id, batch_id, quantity) VALUES (:sale_id, 1, 3);    -- Dolo 650 x3
    INSERT INTO sale_items (sale_id, batch_id, quantity) VALUES (:sale_id, 12, 1);   -- Pan 40 x1
COMMIT;

\echo 'Stock after (reduced by the trigger) and the sale total:'
SELECT batch_id, quantity_in_stock FROM batches WHERE batch_id IN (1, 12);
SELECT sale_id, total_amount FROM sales WHERE sale_id = :sale_id;


\echo
\echo '--- Demo 2: one bad line inside a sale, SAVEPOINT + partial ROLLBACK ---'
BEGIN;
    INSERT INTO sales (customer_id, staff_id, payment_mode)
    VALUES (2, 3, 'cash')
    RETURNING sale_id \gset
    INSERT INTO sale_items (sale_id, batch_id, quantity) VALUES (:sale_id, 6, 2);    -- valid: Glycomet

    SAVEPOINT before_expired_line;
    -- Batch 19 (Digene Gel) is expired: the trigger raises an error here.
    INSERT INTO sale_items (sale_id, batch_id, quantity) VALUES (:sale_id, 19, 1);
    ROLLBACK TO SAVEPOINT before_expired_line;

    -- Replace it with the in-date Digene batch and carry on.
    INSERT INTO sale_items (sale_id, batch_id, quantity) VALUES (:sale_id, 28, 1);
COMMIT;

\echo 'Sale kept with the 2 valid lines only (batch 6 and batch 28):'
SELECT si.batch_id, si.quantity, si.unit_price FROM sale_items si WHERE si.sale_id = :sale_id ORDER BY 1;


\echo
\echo '--- Demo 3: full ROLLBACK, nothing changes ---'
\echo 'Stock before:'
SELECT batch_id, quantity_in_stock FROM batches WHERE batch_id = 8;
BEGIN;
    INSERT INTO sales (customer_id, staff_id, payment_mode)
    VALUES (3, 2, 'card')
    RETURNING sale_id \gset
    INSERT INTO sale_items (sale_id, batch_id, quantity) VALUES (:sale_id, 8, 50);  -- Ecosprin x50
    \echo 'Inside the transaction (stock already reduced):'
    SELECT batch_id, quantity_in_stock FROM batches WHERE batch_id = 8;
ROLLBACK;
\echo 'After ROLLBACK (stock restored, sale row gone):'
SELECT batch_id, quantity_in_stock FROM batches WHERE batch_id = 8;
SELECT count(*) AS sale_rows_left FROM sales WHERE sale_id = :sale_id;


\echo
\echo '--- Demo 4: receive a purchase order (multi-table write), COMMIT ---'
\echo 'PO 2 before:'
SELECT po_id, status FROM purchase_orders WHERE po_id = 2;
BEGIN;
    SELECT fn_receive_purchase_order(2) AS batches_created;
COMMIT;
\echo 'PO 2 after, and the batches it created:'
SELECT po_id, status FROM purchase_orders WHERE po_id = 2;
SELECT batch_id, medicine_id, batch_no, quantity_in_stock, expiry_date
FROM batches WHERE batch_no LIKE 'PO2-%';


\echo
\echo '--- Demo 5: receiving the same PO again fails and rolls back ---'
BEGIN;
    SELECT fn_receive_purchase_order(2);
ROLLBACK;
