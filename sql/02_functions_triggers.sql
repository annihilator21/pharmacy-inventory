-- =====================================================================
-- 02_functions_triggers.sql
-- Business rules enforced inside the database.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Trigger 1 (BEFORE INSERT on sale_items)
-- Blocks the sale of expired batches or quantities above stock.
-- Locks the batch row so two simultaneous sales cannot both pass the
-- stock check. Fills in the unit price from the medicine if omitted.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_validate_sale_item() RETURNS trigger AS $$
DECLARE
    v_stock   INT;
    v_expiry  DATE;
    v_price   NUMERIC(10,2);
    v_name    TEXT;
BEGIN
    SELECT b.quantity_in_stock, b.expiry_date, m.unit_price, m.name
      INTO v_stock, v_expiry, v_price, v_name
      FROM batches b
      JOIN medicines m ON m.medicine_id = b.medicine_id
     WHERE b.batch_id = NEW.batch_id
       FOR UPDATE OF b;

    IF v_expiry < CURRENT_DATE THEN
        RAISE EXCEPTION 'Cannot sell % (batch %): expired on %', v_name, NEW.batch_id, v_expiry
            USING ERRCODE = 'P0001';
    END IF;

    IF NEW.quantity > v_stock THEN
        RAISE EXCEPTION 'Insufficient stock for % (batch %): requested %, available %',
                        v_name, NEW.batch_id, NEW.quantity, v_stock
            USING ERRCODE = 'P0002';
    END IF;

    IF NEW.unit_price IS NULL THEN
        NEW.unit_price := v_price;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_validate_sale_item
BEFORE INSERT ON sale_items
FOR EACH ROW EXECUTE FUNCTION fn_validate_sale_item();

-- ---------------------------------------------------------------------
-- Trigger 2 (AFTER INSERT on sale_items)
-- Reduces batch stock and keeps sales.total_amount in step.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_apply_sale_item() RETURNS trigger AS $$
BEGIN
    UPDATE batches
       SET quantity_in_stock = quantity_in_stock - NEW.quantity
     WHERE batch_id = NEW.batch_id;

    UPDATE sales
       SET total_amount = total_amount + NEW.quantity * NEW.unit_price
     WHERE sale_id = NEW.sale_id;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_apply_sale_item
AFTER INSERT ON sale_items
FOR EACH ROW EXECUTE FUNCTION fn_apply_sale_item();

-- ---------------------------------------------------------------------
-- Trigger 3 (AFTER UPDATE of stock on batches)
-- Raises a low-stock alert when sellable stock for the medicine drops
-- below its reorder level. Only one open alert per medicine.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_low_stock_alert() RETURNS trigger AS $$
DECLARE
    v_total   BIGINT;
    v_reorder INT;
    v_name    TEXT;
BEGIN
    SELECT COALESCE(SUM(b.quantity_in_stock), 0), m.reorder_level, m.name
      INTO v_total, v_reorder, v_name
      FROM medicines m
      LEFT JOIN batches b
             ON b.medicine_id = m.medicine_id AND b.expiry_date >= CURRENT_DATE
     WHERE m.medicine_id = NEW.medicine_id
     GROUP BY m.reorder_level, m.name;

    IF v_total < v_reorder
       AND NOT EXISTS (SELECT 1 FROM stock_alerts
                        WHERE medicine_id = NEW.medicine_id
                          AND alert_type = 'low_stock'
                          AND NOT resolved) THEN
        INSERT INTO stock_alerts(medicine_id, alert_type, message)
        VALUES (NEW.medicine_id, 'low_stock',
                format('%s is below reorder level: %s in stock, reorder level %s',
                       v_name, v_total, v_reorder));
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_low_stock_alert
AFTER UPDATE OF quantity_in_stock ON batches
FOR EACH ROW
WHEN (NEW.quantity_in_stock < OLD.quantity_in_stock)
EXECUTE FUNCTION fn_low_stock_alert();

-- ---------------------------------------------------------------------
-- Function: scan all batches and create expiry alerts.
-- Called by expiry_alerts.py or manually:  SELECT fn_generate_expiry_alerts();
-- Returns the number of new alerts created.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_generate_expiry_alerts(p_days INT DEFAULT 30) RETURNS INT AS $$
DECLARE
    v_count INT := 0;
    r       RECORD;
BEGIN
    FOR r IN
        SELECT b.medicine_id, m.name, b.batch_no, b.expiry_date, b.quantity_in_stock,
               CASE WHEN b.expiry_date < CURRENT_DATE THEN 'expired' ELSE 'near_expiry' END AS kind
          FROM batches b
          JOIN medicines m ON m.medicine_id = b.medicine_id
         WHERE b.quantity_in_stock > 0
           AND b.expiry_date <= CURRENT_DATE + p_days
    LOOP
        IF NOT EXISTS (SELECT 1 FROM stock_alerts
                        WHERE medicine_id = r.medicine_id
                          AND alert_type = r.kind
                          AND NOT resolved
                          AND message LIKE '% batch ' || r.batch_no || ' (%') THEN
            INSERT INTO stock_alerts(medicine_id, alert_type, message)
            VALUES (r.medicine_id, r.kind,
                    format('%s batch %s (%s units) %s on %s',
                           r.name, r.batch_no, r.quantity_in_stock,
                           CASE r.kind WHEN 'expired' THEN 'expired' ELSE 'expires' END,
                           r.expiry_date));
            v_count := v_count + 1;
        END IF;
    END LOOP;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- Function: receive a purchase order into stock (creates batches).
-- Demonstrates a multi-table write that the transactions file also uses.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_receive_purchase_order(p_po_id INT, p_shelf_life_days INT DEFAULT 730)
RETURNS INT AS $$
DECLARE
    v_supplier INT;
    v_status   TEXT;
    v_rows     INT;
BEGIN
    SELECT supplier_id, status INTO v_supplier, v_status
      FROM purchase_orders WHERE po_id = p_po_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Purchase order % does not exist', p_po_id;
    END IF;
    IF v_status <> 'placed' THEN
        RAISE EXCEPTION 'Purchase order % is already %', p_po_id, v_status;
    END IF;

    INSERT INTO batches(medicine_id, supplier_id, batch_no, quantity_in_stock,
                        purchase_price, received_date, expiry_date)
    SELECT i.medicine_id, v_supplier,
           'PO' || p_po_id || '-' || i.medicine_id,
           i.quantity, i.unit_cost, CURRENT_DATE, CURRENT_DATE + p_shelf_life_days
      FROM purchase_order_items i
     WHERE i.po_id = p_po_id;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    UPDATE purchase_orders SET status = 'received' WHERE po_id = p_po_id;

    RETURN v_rows;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- Function: scan every medicine and create a low-stock alert where sellable
-- stock is under the reorder level and no open alert exists yet.
-- Needed because trg_low_stock_alert only fires when stock goes DOWN, so
-- stock that was loaded already low (seed data) would never get an alert.
-- Returns the number of new alerts created.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_generate_low_stock_alerts() RETURNS INT AS $$
DECLARE
    v_count INT := 0;
    r       RECORD;
BEGIN
    FOR r IN SELECT medicine_id, name, sellable_stock, reorder_level FROM v_low_stock
    LOOP
        IF NOT EXISTS (SELECT 1 FROM stock_alerts
                        WHERE medicine_id = r.medicine_id
                          AND alert_type = 'low_stock'
                          AND NOT resolved) THEN
            INSERT INTO stock_alerts(medicine_id, alert_type, message)
            VALUES (r.medicine_id, 'low_stock',
                    format('%s is below reorder level: %s in stock, reorder level %s',
                           r.name, r.sellable_stock, r.reorder_level));
            v_count := v_count + 1;
        END IF;
    END LOOP;
    RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------------
-- Triggers 4 and 5 (AFTER INSERT on batches / AFTER UPDATE of stock on batches)
-- Resolve an open low-stock alert once new stock brings the medicine back
-- to or above its reorder level (new batch received, or stock increased).
-- Without this, an alert stayed open forever and blocked any new alert.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_resolve_low_stock_alert() RETURNS trigger AS $$
DECLARE
    v_total   BIGINT;
    v_reorder INT;
BEGIN
    SELECT COALESCE(SUM(b.quantity_in_stock), 0), m.reorder_level
      INTO v_total, v_reorder
      FROM medicines m
      LEFT JOIN batches b
             ON b.medicine_id = m.medicine_id AND b.expiry_date >= CURRENT_DATE
     WHERE m.medicine_id = NEW.medicine_id
     GROUP BY m.reorder_level;

    IF v_total >= v_reorder THEN
        UPDATE stock_alerts
           SET resolved = TRUE
         WHERE medicine_id = NEW.medicine_id
           AND alert_type = 'low_stock'
           AND NOT resolved;
    END IF;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_resolve_alert_on_new_batch
AFTER INSERT ON batches
FOR EACH ROW EXECUTE FUNCTION fn_resolve_low_stock_alert();

CREATE TRIGGER trg_resolve_alert_on_restock
AFTER UPDATE OF quantity_in_stock ON batches
FOR EACH ROW
WHEN (NEW.quantity_in_stock > OLD.quantity_in_stock)
EXECUTE FUNCTION fn_resolve_low_stock_alert();
