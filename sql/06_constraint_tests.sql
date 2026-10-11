-- =====================================================================
-- 06_constraint_tests.sql
-- Every statement below MUST be rejected by the database. Each test runs
-- inside a sub-transaction, so nothing is left behind whether it passes
-- or fails. Output is a PASS/FAIL line per test, ready to screenshot.
-- Run with:  psql -d pharmacy -f 06_constraint_tests.sql
-- =====================================================================

CREATE OR REPLACE FUNCTION pg_temp.expect_error(p_label TEXT, p_sql TEXT) RETURNS VOID AS $$
BEGIN
    EXECUTE p_sql;
    -- Reaching this line means the statement was accepted: undo it and report.
    RAISE EXCEPTION 'statement was accepted' USING ERRCODE = 'XX999';
EXCEPTION
    WHEN SQLSTATE 'XX999' THEN
        RAISE NOTICE 'FAIL | % | the statement was accepted but should have been rejected', p_label;
    WHEN OTHERS THEN
        RAISE NOTICE 'PASS | % | rejected: %', p_label, SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ---- CHECK constraints ------------------------------------------------
SELECT pg_temp.expect_error('negative stock (CHECK quantity_in_stock >= 0)',
  $$UPDATE batches SET quantity_in_stock = -1 WHERE batch_id = 1$$);

SELECT pg_temp.expect_error('zero medicine price (CHECK unit_price > 0)',
  $$INSERT INTO medicines(name, generic_name, category_id, manufacturer, unit_price)
    VALUES ('Test Drug', 'Test', 1, 'Test Co', 0)$$);

SELECT pg_temp.expect_error('expiry not after received date (CHECK chk_batch_dates)',
  $$INSERT INTO batches(medicine_id, supplier_id, batch_no, quantity_in_stock, purchase_price, received_date, expiry_date)
    VALUES (1, 1, 'BAD-DATES', 10, 5, CURRENT_DATE, CURRENT_DATE - 1)$$);

SELECT pg_temp.expect_error('invalid payment mode (CHECK payment_mode)',
  $$INSERT INTO sales(customer_id, staff_id, payment_mode) VALUES (1, 2, 'bitcoin')$$);

SELECT pg_temp.expect_error('malformed supplier phone (CHECK phone regex)',
  $$INSERT INTO suppliers(name, phone, city) VALUES ('Bad Phone Co', 'abc', 'Pune')$$);

SELECT pg_temp.expect_error('invalid staff role (CHECK role)',
  $$INSERT INTO staff(full_name, role) VALUES ('Test Person', 'janitor')$$);

SELECT pg_temp.expect_error('sale quantity of zero (CHECK quantity > 0)',
  $$INSERT INTO sale_items(sale_id, batch_id, quantity, unit_price) VALUES (1, 1, 0, 10)$$);

SELECT pg_temp.expect_error('forecast month not the 1st (CHECK chk_forecast_month)',
  $$INSERT INTO demand_forecasts(medicine_id, forecast_month, predicted_qty)
    VALUES (1, DATE '2027-01-15', 10)$$);

SELECT pg_temp.expect_error('invalid alert type (CHECK alert_type)',
  $$INSERT INTO stock_alerts(medicine_id, alert_type, message) VALUES (1, 'weird', 'x')$$);

-- ---- UNIQUE constraints -----------------------------------------------
SELECT pg_temp.expect_error('duplicate batch number for a medicine (UNIQUE)',
  $$INSERT INTO batches(medicine_id, supplier_id, batch_no, quantity_in_stock, purchase_price, expiry_date)
    VALUES (1, 1, 'DL650-A1', 10, 5, CURRENT_DATE + 100)$$);

SELECT pg_temp.expect_error('duplicate customer phone (UNIQUE)',
  $$INSERT INTO customers(full_name, phone) VALUES ('Clone', '9700000001')$$);

SELECT pg_temp.expect_error('second forecast for same medicine and month (UNIQUE)',
  $$INSERT INTO demand_forecasts(medicine_id, forecast_month, predicted_qty)
    SELECT medicine_id, forecast_month, 5 FROM demand_forecasts LIMIT 1$$);

-- ---- Foreign keys -----------------------------------------------------
SELECT pg_temp.expect_error('sale line pointing to a non-existent batch (FOREIGN KEY)',
  $$INSERT INTO sale_items(sale_id, batch_id, quantity, unit_price) VALUES (1, 99999, 1, 10)$$);

SELECT pg_temp.expect_error('deleting a medicine that still has batches (ON DELETE RESTRICT)',
  $$DELETE FROM medicines WHERE medicine_id = 1$$);

-- ---- Business-rule triggers -------------------------------------------
SELECT pg_temp.expect_error('selling an expired batch (trigger trg_validate_sale_item)',
  $$WITH s AS (INSERT INTO sales(staff_id) VALUES (2) RETURNING sale_id)
    INSERT INTO sale_items(sale_id, batch_id, quantity) SELECT sale_id, 19, 1 FROM s$$);

SELECT pg_temp.expect_error('selling more than the stock (trigger trg_validate_sale_item)',
  $$WITH s AS (INSERT INTO sales(staff_id) VALUES (2) RETURNING sale_id)
    INSERT INTO sale_items(sale_id, batch_id, quantity) SELECT sale_id, 23, 1000 FROM s$$);

-- ---- One positive test: a valid sale is accepted and reduces stock ------
DO $$
DECLARE
    v_before INT;
    v_after  INT;
BEGIN
    SELECT quantity_in_stock INTO v_before FROM batches WHERE batch_id = 1;
    BEGIN
        WITH s AS (INSERT INTO sales(staff_id) VALUES (2) RETURNING sale_id)
        INSERT INTO sale_items(sale_id, batch_id, quantity) SELECT sale_id, 1, 2 FROM s;
        SELECT quantity_in_stock INTO v_after FROM batches WHERE batch_id = 1;
        IF v_after = v_before - 2 THEN
            RAISE NOTICE 'PASS | valid sale accepted and stock reduced from % to %', v_before, v_after;
        ELSE
            RAISE NOTICE 'FAIL | stock is % after the sale, expected %', v_after, v_before - 2;
        END IF;
        RAISE EXCEPTION 'undo' USING ERRCODE = 'XX998';   -- roll the test sale back
    EXCEPTION WHEN SQLSTATE 'XX998' THEN NULL;
    END;
END $$;

-- ---- One more positive test: new stock resolves an open low-stock alert ----
DO $$
DECLARE
    v_open_before INT;
    v_open_after  INT;
BEGIN
    SELECT count(*) INTO v_open_before FROM stock_alerts
     WHERE medicine_id = 11 AND alert_type = 'low_stock' AND NOT resolved;
    BEGIN
        INSERT INTO batches(medicine_id, supplier_id, batch_no, quantity_in_stock, purchase_price, received_date, expiry_date)
        VALUES (11, 2, 'TEST-RESTOCK', 50, 480, CURRENT_DATE, CURRENT_DATE + 365);
        SELECT count(*) INTO v_open_after FROM stock_alerts
         WHERE medicine_id = 11 AND alert_type = 'low_stock' AND NOT resolved;
        IF v_open_before = 1 AND v_open_after = 0 THEN
            RAISE NOTICE 'PASS | restocking resolves the open low-stock alert (open alerts % -> %)', v_open_before, v_open_after;
        ELSE
            RAISE NOTICE 'FAIL | open low-stock alerts went from % to %', v_open_before, v_open_after;
        END IF;
        RAISE EXCEPTION 'undo' USING ERRCODE = 'XX998';   -- roll the test batch back
    EXCEPTION WHEN SQLSTATE 'XX998' THEN NULL;
    END;
END $$;
