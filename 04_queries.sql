-- =====================================================================
-- 04_queries.sql  |  16 sample queries for the report (all read-only)
-- Each query is labelled with the SQL concept it demonstrates.
-- =====================================================================

-- Q1. Sellable stock per medicine (view over JOIN + GROUP BY + FILTER)
SELECT medicine_id, name, category, sellable_stock, expired_stock
FROM v_medicine_stock
ORDER BY name;

-- Q2. Medicines below reorder level and how many units short they are
SELECT name, category, sellable_stock, reorder_level,
       reorder_level - sellable_stock AS shortfall
FROM v_low_stock
ORDER BY shortfall DESC;

-- Q3. Expired stock still on the shelf and the purchase value written off
SELECT m.name, b.batch_no, b.expiry_date, b.quantity_in_stock,
       b.quantity_in_stock * b.purchase_price AS loss_at_cost
FROM batches b
JOIN medicines m ON m.medicine_id = b.medicine_id
WHERE b.expiry_date < CURRENT_DATE AND b.quantity_in_stock > 0
ORDER BY loss_at_cost DESC;

-- Q4. Batches expiring within 30 days, soonest first (uses the expiry view)
SELECT medicine, batch_no, quantity_in_stock, expiry_date, days_left
FROM v_expiry_status
WHERE status = 'expires within 30 days'
ORDER BY days_left;

-- Q5. Top 5 best sellers in the last 30 days by units (4-table JOIN, LIMIT)
SELECT m.name, SUM(si.quantity) AS units_sold,
       SUM(si.quantity * si.unit_price) AS revenue
FROM sale_items si
JOIN sales s     ON s.sale_id = si.sale_id
JOIN batches b   ON b.batch_id = si.batch_id
JOIN medicines m ON m.medicine_id = b.medicine_id
WHERE s.sale_date >= now() - INTERVAL '30 days'
GROUP BY m.name
ORDER BY units_sold DESC
LIMIT 5;

-- Q6. Monthly revenue by category (date_trunc + GROUP BY on two keys)
SELECT date_trunc('month', s.sale_date)::date AS month,
       c.name AS category,
       SUM(si.quantity * si.unit_price)       AS revenue
FROM sales s
JOIN sale_items si ON si.sale_id = s.sale_id
JOIN batches b     ON b.batch_id = si.batch_id
JOIN medicines m   ON m.medicine_id = b.medicine_id
JOIN categories c  ON c.category_id = m.category_id
GROUP BY 1, 2
ORDER BY 1, revenue DESC;

-- Q7. Customers who spent more than 500 in total (HAVING, LEFT-side filter)
SELECT c.full_name, COUNT(DISTINCT s.sale_id) AS visits, SUM(s.total_amount) AS total_spent
FROM customers c
JOIN sales s ON s.customer_id = c.customer_id
GROUP BY c.customer_id, c.full_name
HAVING SUM(s.total_amount) > 500
ORDER BY total_spent DESC;

-- Q8. Medicines with no sale in the last 60 days (correlated NOT EXISTS)
SELECT m.medicine_id, m.name
FROM medicines m
WHERE NOT EXISTS (
    SELECT 1
    FROM sale_items si
    JOIN sales s   ON s.sale_id = si.sale_id
    JOIN batches b ON b.batch_id = si.batch_id
    WHERE b.medicine_id = m.medicine_id
      AND s.sale_date >= now() - INTERVAL '60 days'
)
ORDER BY m.name;

-- Q9. Inventory value at cost by supplier (aggregate over a join)
SELECT sp.name AS supplier, sp.city,
       SUM(b.quantity_in_stock * b.purchase_price) AS stock_value
FROM suppliers sp
JOIN batches b ON b.supplier_id = sp.supplier_id
WHERE b.expiry_date >= CURRENT_DATE
GROUP BY sp.supplier_id, sp.name, sp.city
ORDER BY stock_value DESC;

-- Q10. Daily revenue with a running total (window function SUM OVER)
SELECT sale_day, daily_revenue,
       SUM(daily_revenue) OVER (ORDER BY sale_day) AS running_total
FROM (
    SELECT s.sale_date::date AS sale_day, SUM(s.total_amount) AS daily_revenue
    FROM sales s
    GROUP BY s.sale_date::date
) d
ORDER BY sale_day;

-- Q11. Rank medicines inside each category by units sold (RANK OVER PARTITION)
SELECT category, name, units_sold,
       RANK() OVER (PARTITION BY category ORDER BY units_sold DESC) AS rank_in_category
FROM (
    SELECT c.name AS category, m.name, COALESCE(SUM(si.quantity), 0) AS units_sold
    FROM medicines m
    JOIN categories c      ON c.category_id = m.category_id
    LEFT JOIN batches b    ON b.medicine_id = m.medicine_id
    LEFT JOIN sale_items si ON si.batch_id = b.batch_id
    GROUP BY c.name, m.name
) t
ORDER BY category, rank_in_category;

-- Q12. Monthly units per medicine with a 3-month moving average
--      (CTE + window frame; this is the same idea forecast_demand.py uses)
WITH monthly AS (
    SELECT b.medicine_id,
           date_trunc('month', s.sale_date)::date AS month,
           SUM(si.quantity) AS units
    FROM sale_items si
    JOIN sales s   ON s.sale_id = si.sale_id
    JOIN batches b ON b.batch_id = si.batch_id
    GROUP BY b.medicine_id, date_trunc('month', s.sale_date)
)
SELECT m.name, mo.month, mo.units,
       round(AVG(mo.units) OVER (PARTITION BY mo.medicine_id
                                 ORDER BY mo.month
                                 ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 1) AS moving_avg_3m
FROM monthly mo
JOIN medicines m ON m.medicine_id = mo.medicine_id
ORDER BY m.name, mo.month;

-- Q13. Reorder suggestions: forecast demand not covered by sellable stock
SELECT m.name, f.forecast_month, f.predicted_qty, v.sellable_stock,
       f.predicted_qty - v.sellable_stock AS suggested_order_qty
FROM demand_forecasts f
JOIN medicines m        ON m.medicine_id = f.medicine_id
JOIN v_medicine_stock v ON v.medicine_id = f.medicine_id
WHERE f.predicted_qty > v.sellable_stock
ORDER BY suggested_order_qty DESC;

-- Q14. Share of revenue from prescription medicines (FILTER on aggregates)
SELECT round(100.0 * SUM(si.quantity * si.unit_price)
                    FILTER (WHERE m.requires_prescription)
             / SUM(si.quantity * si.unit_price), 1) AS pct_revenue_prescription,
       SUM(si.quantity * si.unit_price)             AS total_revenue
FROM sale_items si
JOIN batches b   ON b.batch_id = si.batch_id
JOIN medicines m ON m.medicine_id = b.medicine_id;

-- Q15. FEFO picking list (First-Expired-First-Out) for one medicine
--      Dolo 650 has two batches; this shows which one to sell from first.
SELECT b.batch_id, b.batch_no, b.quantity_in_stock, b.expiry_date
FROM batches b
JOIN medicines m ON m.medicine_id = b.medicine_id
WHERE m.name = 'Dolo 650'
  AND b.expiry_date >= CURRENT_DATE
  AND b.quantity_in_stock > 0
ORDER BY b.expiry_date ASC;

-- Q16. Days of stock cover = sellable stock / average daily sales (last 30 days)
SELECT v.name, v.sellable_stock,
       COALESCE(u.units_30d, 0) AS units_last_30_days,
       CASE WHEN COALESCE(u.units_30d, 0) = 0 THEN NULL
            ELSE round(v.sellable_stock / (u.units_30d / 30.0), 1) END AS days_of_cover
FROM v_medicine_stock v
LEFT JOIN (
    SELECT b.medicine_id, SUM(si.quantity) AS units_30d
    FROM sale_items si
    JOIN sales s   ON s.sale_id = si.sale_id
    JOIN batches b ON b.batch_id = si.batch_id
    WHERE s.sale_date >= now() - INTERVAL '30 days'
    GROUP BY b.medicine_id
) u ON u.medicine_id = v.medicine_id
ORDER BY days_of_cover NULLS LAST;
