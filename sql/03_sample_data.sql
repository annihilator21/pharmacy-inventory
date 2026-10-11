-- =====================================================================
-- 03_sample_data.sql
-- Run AFTER 01_schema.sql and 02_functions_triggers.sql.
-- All dates are relative to CURRENT_DATE so the near-expiry and expired
-- rows stay near-expiry and expired whenever you rebuild the database.
-- =====================================================================

INSERT INTO categories (category_id, name, description) VALUES
 (1, 'Analgesic & Antipyretic', 'Pain and fever relief'),
 (2, 'Antibiotic',              'Bacterial infections'),
 (3, 'Antacid & Gastro',        'Acidity and digestive care'),
 (4, 'Antidiabetic',            'Blood sugar control'),
 (5, 'Cardiovascular',          'Blood pressure, cholesterol, heart'),
 (6, 'Respiratory',             'Asthma and breathing support'),
 (7, 'Antihistamine',           'Allergy relief'),
 (8, 'Vitamins & Supplements',  'Nutritional supplements');

INSERT INTO suppliers (supplier_id, name, phone, email, city) VALUES
 (1,  'Sunrise Pharma Distributors', '9825012345', 'orders@sunrisepharma.example', 'Ahmedabad'),
 (2,  'MedLine Wholesale',           '9820123456', 'sales@medline.example',        'Mumbai'),
 (3,  'Apex Healthcare Supplies',    '9822234567', 'apex@apexhealth.example',      'Pune'),
 (4,  'Gujarat Drug House',          '9824345678', 'info@gujaratdrug.example',     'Surat'),
 (5,  'Bharat Medico',               '9811456789', 'bharat@medico.example',        'Delhi'),
 (6,  'Southern Meds Pvt Ltd',       '9840567890', 'orders@southernmeds.example',  'Chennai'),
 (7,  'Lifeline Distributors',       '9830678901', 'lifeline@dist.example',        'Kolkata'),
 (8,  'Rajkot Pharma Traders',       '9825789012', 'rpt@rajkotpharma.example',     'Rajkot'),
 (9,  'CareFirst Agencies',          '9845890123', 'care@carefirst.example',       'Bengaluru'),
 (10, 'Vadodara Medical Stores',     '9825901234', 'vms@vadmed.example',           'Vadodara');

INSERT INTO staff (staff_id, full_name, role, phone, hired_on) VALUES
 (1, 'Meera Joshi',    'manager',    '9898000001', CURRENT_DATE - 1500),
 (2, 'Rohan Patel',    'pharmacist', '9898000002', CURRENT_DATE - 900),
 (3, 'Sneha Kulkarni', 'pharmacist', '9898000003', CURRENT_DATE - 700),
 (4, 'Imran Shaikh',   'cashier',    '9898000004', CURRENT_DATE - 400),
 (5, 'Kavya Nair',     'cashier',    '9898000005', CURRENT_DATE - 250),
 (6, 'Arjun Mehta',    'pharmacist', '9898000006', CURRENT_DATE - 120);

INSERT INTO customers (customer_id, full_name, phone, email, registered_on) VALUES
 (1,  'Aarav Shah',      '9700000001', 'aarav.shah@example.com',    CURRENT_DATE - 600),
 (2,  'Diya Desai',      '9700000002', 'diya.desai@example.com',    CURRENT_DATE - 580),
 (3,  'Vivaan Trivedi',  '9700000003', NULL,                        CURRENT_DATE - 540),
 (4,  'Ananya Iyer',     '9700000004', 'ananya.iyer@example.com',   CURRENT_DATE - 500),
 (5,  'Kabir Singh',     '9700000005', 'kabir.singh@example.com',   CURRENT_DATE - 470),
 (6,  'Ishita Rao',      '9700000006', NULL,                        CURRENT_DATE - 430),
 (7,  'Reyansh Gupta',   '9700000007', 'reyansh.g@example.com',     CURRENT_DATE - 400),
 (8,  'Saanvi Pillai',   '9700000008', 'saanvi.p@example.com',      CURRENT_DATE - 360),
 (9,  'Arnav Joshi',     '9700000009', NULL,                        CURRENT_DATE - 330),
 (10, 'Myra Kapoor',     '9700000010', 'myra.kapoor@example.com',   CURRENT_DATE - 300),
 (11, 'Vihaan Bhatt',    '9700000011', 'vihaan.bhatt@example.com',  CURRENT_DATE - 270),
 (12, 'Navya Menon',     '9700000012', NULL,                        CURRENT_DATE - 240),
 (13, 'Advait Kulkarni', '9700000013', 'advait.k@example.com',      CURRENT_DATE - 210),
 (14, 'Pari Chauhan',    '9700000014', 'pari.chauhan@example.com',  CURRENT_DATE - 180),
 (15, 'Krish Agarwal',   '9700000015', NULL,                        CURRENT_DATE - 150),
 (16, 'Tara Banerjee',   '9700000016', 'tara.b@example.com',        CURRENT_DATE - 120),
 (17, 'Dhruv Nambiar',   '9700000017', 'dhruv.n@example.com',       CURRENT_DATE - 90),
 (18, 'Zoya Khan',       '9700000018', 'zoya.khan@example.com',     CURRENT_DATE - 60),
 (19, 'Yash Parmar',     '9700000019', NULL,                        CURRENT_DATE - 30),
 (20, 'Rhea Fernandes',  '9700000020', 'rhea.f@example.com',        CURRENT_DATE - 10);

INSERT INTO medicines (medicine_id, name, generic_name, category_id, manufacturer, unit_price, reorder_level, requires_prescription) VALUES
 (1,  'Dolo 650',         'Paracetamol 650mg',               1, 'Micro Labs',  30.00, 100, FALSE),
 (2,  'Crocin Advance',   'Paracetamol 500mg',               1, 'GSK',         22.50,  80, FALSE),
 (3,  'Brufen 400',       'Ibuprofen 400mg',                 1, 'Abbott',      28.00,  60, FALSE),
 (4,  'Azithral 500',     'Azithromycin 500mg',              2, 'Alembic',    118.50,  40, TRUE),
 (5,  'Augmentin 625',    'Amoxicillin + Clavulanic acid',   2, 'GSK',        201.00,  40, TRUE),
 (6,  'Cifran 500',       'Ciprofloxacin 500mg',             2, 'Sun Pharma',  92.00,  30, TRUE),
 (7,  'Pan 40',           'Pantoprazole 40mg',               3, 'Alkem',      155.00,  60, FALSE),
 (8,  'Digene Gel',       'Antacid suspension',              3, 'Abbott',     110.00,  30, FALSE),
 (9,  'Glycomet 500',     'Metformin 500mg',                 4, 'USV',         42.00,  80, TRUE),
 (10, 'Amaryl 2mg',       'Glimepiride 2mg',                 4, 'Sanofi',     235.00,  40, TRUE),
 (11, 'Lantus Solostar',  'Insulin glargine',                4, 'Sanofi',     650.00,  15, TRUE),
 (12, 'Telma 40',         'Telmisartan 40mg',                5, 'Glenmark',   188.00,  50, TRUE),
 (13, 'Atorva 10',        'Atorvastatin 10mg',               5, 'Zydus',      125.00,  50, TRUE),
 (14, 'Ecosprin 75',      'Aspirin 75mg',                    5, 'USV',          6.80, 100, FALSE),
 (15, 'Asthalin Inhaler', 'Salbutamol 100mcg',               6, 'Cipla',      168.00,  25, FALSE),
 (16, 'Benadryl Syrup',   'Diphenhydramine syrup',           7, 'J&J',        115.00,  30, FALSE),
 (17, 'Cetzine 10',       'Cetirizine 10mg',                 7, 'GSK',         49.00,  60, FALSE),
 (18, 'Allegra 120',      'Fexofenadine 120mg',              7, 'Sanofi',     215.00,  30, FALSE),
 (19, 'Shelcal 500',      'Calcium + Vitamin D3',            8, 'Torrent',    118.00,  50, FALSE),
 (20, 'Becosules',        'Vitamin B-complex',               8, 'Pfizer',      46.00,  60, FALSE);

-- Batches: a mix of healthy, near-expiry, expired and low-stock rows
INSERT INTO batches (batch_id, medicine_id, supplier_id, batch_no, quantity_in_stock, purchase_price, received_date, expiry_date) VALUES
 -- healthy stock
 (1,  1,  1, 'DL650-A1', 300, 21.00, CURRENT_DATE - 120, CURRENT_DATE + 600),
 (2,  1,  2, 'DL650-B2', 150, 21.50, CURRENT_DATE -  40, CURRENT_DATE + 700),
 (3,  3,  1, 'BR400-A1', 120, 19.00, CURRENT_DATE -  90, CURRENT_DATE + 500),
 (4,  4,  3, 'AZ500-A1', 100, 82.00, CURRENT_DATE -  60, CURRENT_DATE + 450),
 (5,  6,  3, 'CF500-A1',  80, 63.00, CURRENT_DATE -  80, CURRENT_DATE + 380),
 (6,  9,  4, 'GL500-A1', 200, 28.00, CURRENT_DATE -  70, CURRENT_DATE + 550),
 (7,  12, 5, 'TL040-A1', 110, 130.00, CURRENT_DATE - 50, CURRENT_DATE + 520),
 (8,  14, 4, 'EC075-A1', 400,  4.20, CURRENT_DATE -  30, CURRENT_DATE + 800),
 (9,  18, 6, 'AG120-A1',  70, 150.00, CURRENT_DATE - 45, CURRENT_DATE + 420),
 (10, 20, 7, 'BC000-A1', 160, 31.00, CURRENT_DATE -  25, CURRENT_DATE + 640),
 (11, 17, 8, 'CZ010-B2', 120, 33.00, CURRENT_DATE -  20, CURRENT_DATE + 560),
 (12, 7,  9, 'PN040-B2', 140, 108.00, CURRENT_DATE - 15, CURRENT_DATE + 900),
 -- expiring within 30 days
 (13, 2,  1, 'CR500-A1', 150, 15.00, CURRENT_DATE - 330, CURRENT_DATE + 12),
 (14, 5,  3, 'AU625-A1',  60, 140.00, CURRENT_DATE - 340, CURRENT_DATE + 25),
 (15, 19, 10,'SH500-A1',  90, 82.00, CURRENT_DATE - 350, CURRENT_DATE + 28),
 -- expiring within 31-90 days
 (16, 7,  9, 'PN040-A1',  75, 108.00, CURRENT_DATE - 300, CURRENT_DATE + 70),
 (17, 13, 5, 'AT010-A1',  85, 88.00, CURRENT_DATE - 280, CURRENT_DATE + 85),
 (18, 9,  4, 'GL500-OLD', 60, 28.00, CURRENT_DATE - 400, CURRENT_DATE + 55),
 -- already expired (should be blocked from sale and flagged)
 (19, 8,  2, 'DG000-A1',  25, 74.00, CURRENT_DATE - 500, CURRENT_DATE - 20),
 (20, 17, 8, 'CZ010-A1',  40, 33.00, CURRENT_DATE - 450, CURRENT_DATE -  5),
 (21, 16, 6, 'BN000-A1',  12, 80.00, CURRENT_DATE - 600, CURRENT_DATE - 60),
 (22, 4,  3, 'AZ500-OLD', 30, 82.00, CURRENT_DATE - 700, CURRENT_DATE - 100),
 -- low stock (below reorder level)
 (23, 11, 2, 'LN000-A1',   8, 480.00, CURRENT_DATE - 60, CURRENT_DATE + 200),
 (24, 15, 2, 'AS100-A1',  10, 120.00, CURRENT_DATE - 90, CURRENT_DATE + 300),
 (25, 10, 5, 'AM002-A1',  20, 170.00, CURRENT_DATE - 100, CURRENT_DATE + 350),
 (26, 3,  1, 'BR400-B2',   0, 19.00, CURRENT_DATE - 200, CURRENT_DATE + 150),
 -- a few more healthy batches so every medicine except the seeded gaps has stock
 (27, 16, 6, 'BN000-B2',  45, 80.00, CURRENT_DATE -  30, CURRENT_DATE + 480),
 (28, 8,  2, 'DG000-B2',  60, 74.00, CURRENT_DATE -  30, CURRENT_DATE + 520),
 (29, 19, 10,'SH500-B2', 100, 82.00, CURRENT_DATE -  10, CURRENT_DATE + 600),
 (30, 13, 5, 'AT010-B2', 120, 88.00, CURRENT_DATE -  12, CURRENT_DATE + 640);

-- 20 sales spread over the last ~80 days. Items are picked from healthy
-- batches only (stock >= 30, not expired). Prices are filled by the trigger.
INSERT INTO sales (sale_id, customer_id, staff_id, sale_date, payment_mode)
SELECT i,
       CASE WHEN i % 5 = 0 THEN NULL ELSE ((i - 1) % 20) + 1 END,
       CASE WHEN i % 3 = 0 THEN 4 WHEN i % 3 = 1 THEN 5 ELSE 2 END,
       now() - (i * 4 || ' days')::interval - ((i * 37 % 600) || ' minutes')::interval,
       (ARRAY['cash','upi','card'])[(i % 3) + 1]
  FROM generate_series(1, 20) AS i;

WITH pool AS (
    SELECT array_agg(batch_id ORDER BY batch_id) AS ids
      FROM batches
     WHERE expiry_date >= CURRENT_DATE AND quantity_in_stock >= 30
), picks AS (
    SELECT s.sale_id AS sale_id,
           p.ids[(s.sale_id * 3) % array_length(p.ids, 1) + 1] AS b1,
           p.ids[(s.sale_id * 7 + 2) % array_length(p.ids, 1) + 1] AS b2,
           (s.sale_id % 4) + 1 AS q1,
           ((s.sale_id + 1) % 3) + 1 AS q2
      FROM sales s, pool p
)
INSERT INTO sale_items (sale_id, batch_id, quantity)
SELECT sale_id, b1, q1 FROM picks
UNION ALL
SELECT sale_id, b2, q2 FROM picks WHERE b2 <> b1;

-- Two explicit sales on the low-stock medicines. These also fire the
-- low-stock trigger, so the demo already has alerts in the table.
INSERT INTO sales (sale_id, customer_id, staff_id, sale_date, payment_mode)
VALUES (21, 6, 2, now() - INTERVAL '2 days', 'upi'),
       (22, 12, 3, now() - INTERVAL '1 day',  'cash');
INSERT INTO sale_items (sale_id, batch_id, quantity) VALUES
 (21, 23, 2),   -- Lantus, leaves 6
 (22, 24, 3);   -- Asthalin, leaves 7

-- A batch cannot be sold before it was received: move each batch's received
-- date back to the day before its first sale if the first sale is earlier.
UPDATE batches b
   SET received_date = f.first_sale::date - 1
  FROM (SELECT si.batch_id, MIN(s.sale_date) AS first_sale
          FROM sale_items si
          JOIN sales s ON s.sale_id = si.sale_id
         GROUP BY si.batch_id) f
 WHERE f.batch_id = b.batch_id
   AND f.first_sale::date < b.received_date;

INSERT INTO purchase_orders (po_id, supplier_id, order_date, status)
SELECT i,
       ((i - 1) % 10) + 1,
       CURRENT_DATE - (i * 6),
       CASE WHEN i <= 3 THEN 'placed' WHEN i <= 10 THEN 'received' ELSE 'cancelled' END
  FROM generate_series(1, 12) AS i;

INSERT INTO purchase_order_items (po_id, medicine_id, quantity, unit_cost)
SELECT i, ((i * 3) % 20) + 1, 100 + i * 10,
       round((SELECT unit_price FROM medicines WHERE medicine_id = ((i * 3) % 20) + 1) * 0.70, 2)
  FROM generate_series(1, 12) AS i
UNION ALL
SELECT 1, 11, 20, 455.00      -- PO 1 also reorders insulin
UNION ALL
SELECT 2, 15, 30, 117.60      -- PO 2 also reorders inhalers
UNION ALL
SELECT 3, 15, 25, 117.60;     -- PO 3 (already has glimepiride) also reorders inhalers

-- Placeholder forecasts so the app has something to show before
-- forecast_demand.py runs (the script overwrites these via upsert).
INSERT INTO demand_forecasts (medicine_id, forecast_month, predicted_qty, method)
SELECT medicine_id,
       date_trunc('month', CURRENT_DATE + INTERVAL '1 month')::date,
       reorder_level + (medicine_id * 7 % 40),
       'seed_estimate'
  FROM medicines;

-- Create the alerts the seed data should already have: low stock loaded
-- directly (the trigger only fires when stock goes down) and expiry alerts.
SELECT fn_generate_low_stock_alerts();
SELECT fn_generate_expiry_alerts(30);

-- Keep identity sequences ahead of the explicit ids used above
DO $$
DECLARE r RECORD;
BEGIN
    FOR r IN SELECT c.relname AS tbl, a.attname AS col
               FROM pg_class c
               JOIN pg_attribute a ON a.attrelid = c.oid
              WHERE c.relnamespace = 'public'::regnamespace
                AND c.relkind = 'r' AND a.attidentity <> ''
    LOOP
        EXECUTE format('SELECT setval(pg_get_serial_sequence(%L, %L), COALESCE(MAX(%I), 1)) FROM %I',
                       'public.' || r.tbl, r.col, r.col, r.tbl);
    END LOOP;
END $$;
