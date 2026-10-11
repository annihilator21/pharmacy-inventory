"""Load realistic sales history so the forecast has something to learn from.

What it does
  * Creates about --per-day sales per day for the last --months months
    (default 6 per day for 12 months), ending yesterday.
  * Demand per medicine follows its reorder_level (busy medicines sell more)
    and a seasonal pattern per category (monsoon fevers, winter respiratory
    illness, allergy season, ...), so the forecast finds a real pattern.
  * Uses a fixed random seed, so the same data is produced every time.

Why it switches two triggers off
  trg_validate_sale_item and trg_apply_sale_item are meant for LIVE sales:
  they block sales from expired or short batches and reduce current stock.
  Historical sales must not drain today's stock, so both are disabled on
  sale_items for the load and enabled again before the commit. sales.total_amount
  is filled in afterwards from the lines, and every other constraint still
  applies. If anything fails, the whole load is rolled back.

Also, a batch cannot be sold before it was received, so a batch's received_date
is moved back to the day before its first historical sale where needed.

Run it ONCE on a freshly rebuilt database (after 01, 02 and 03):
    python ai/generate_sales_data.py
Run it before forecast_demand.py.
"""
import argparse
import math
import random
from datetime import date, datetime, time, timedelta

from psycopg2.extras import execute_values

from db import get_connection

# Demand multiplier by calendar month (index 0 = January) for each category.
SEASON = {
    "Analgesic & Antipyretic": [1.1, 1.0, 0.9, 0.9, 0.9, 1.0, 1.4, 1.4, 1.3, 1.1, 1.0, 1.1],
    "Antibiotic":              [1.2, 1.0, 0.9, 0.9, 0.9, 1.0, 1.3, 1.3, 1.2, 1.1, 1.1, 1.2],
    "Antacid & Gastro":        [1.0, 0.9, 0.9, 0.9, 1.0, 1.0, 1.0, 1.0, 1.1, 1.3, 1.3, 1.2],
    "Antidiabetic":            [1.0] * 12,
    "Cardiovascular":          [1.1, 1.1, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.1],
    "Respiratory":             [1.5, 1.3, 1.0, 0.8, 0.7, 0.7, 0.8, 0.8, 1.0, 1.4, 1.6, 1.6],
    "Antihistamine":           [1.2, 1.3, 1.4, 1.1, 0.9, 0.8, 0.8, 0.9, 1.1, 1.4, 1.4, 1.2],
    "Vitamins & Supplements":  [1.2, 1.1, 1.0, 0.9, 0.9, 0.9, 1.0, 1.0, 1.0, 1.1, 1.2, 1.3],
}
WEEKDAY_FACTOR = [1.0, 1.0, 1.0, 1.0, 1.1, 1.3, 0.8]       # Monday .. Sunday
QUANTITIES = ([1, 2, 3, 4, 5, 6, 10], [30, 25, 15, 10, 8, 6, 6])
PAYMENT_MODES = (["cash", "upi", "card"], [35, 45, 20])
MAX_EXISTING_SALES = 60          # more than this means history is probably loaded


def weighted_sample(rng, items, weights, k):
    """Pick k different items, with probability proportional to weights."""
    items, weights, chosen = list(items), list(weights), []
    for _ in range(min(k, len(items))):
        i = rng.choices(range(len(items)), weights=weights)[0]
        chosen.append(items.pop(i))
        weights.pop(i)
    return chosen


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--months", type=int, default=12, help="months of history (default 12)")
    ap.add_argument("--per-day", type=float, default=6.0, help="average sales per day (default 6)")
    ap.add_argument("--seed", type=int, default=42, help="random seed (default 42)")
    ap.add_argument("--force", action="store_true", help="load even if history seems to exist")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT count(*) FROM sales")
    existing = cur.fetchone()[0]
    if existing > MAX_EXISTING_SALES and not args.force:
        print(f"The database already has {existing} sales, so history looks loaded.\n"
              "Rebuild the database (rebuild.sh) first, or pass --force to add more anyway.")
        return

    cur.execute("""SELECT m.medicine_id, c.name, m.reorder_level, m.unit_price
                     FROM medicines m JOIN categories c ON c.category_id = m.category_id
                    ORDER BY m.medicine_id""")
    medicines = cur.fetchall()
    cur.execute("SELECT batch_id, medicine_id, expiry_date FROM batches ORDER BY expiry_date, batch_id")
    batches_by_med = {}
    for batch_id, med_id, expiry in cur.fetchall():
        batches_by_med.setdefault(med_id, []).append((batch_id, expiry))
    cur.execute("SELECT staff_id FROM staff ORDER BY staff_id")
    staff_ids = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT customer_id FROM customers ORDER BY customer_id")
    customer_ids = [r[0] for r in cur.fetchall()]
    cur.execute("SELECT COALESCE(MAX(sale_id), 0) FROM sales")
    last_sale_id = cur.fetchone()[0]

    end = date.today() - timedelta(days=1)
    start = end - timedelta(days=round(args.months * 30.4))

    sales, items = [], []
    next_id = last_sale_id + 1
    day = start
    while day <= end:
        mu = args.per_day * WEEKDAY_FACTOR[day.weekday()]
        n_sales = max(0, round(rng.gauss(mu, math.sqrt(mu))))
        weights = [rl * SEASON[cat][day.month - 1] for _, cat, rl, _ in medicines]
        for _ in range(n_sales):
            lines = []
            for med_id, _, _, price in weighted_sample(
                    rng, medicines, weights, rng.choices([1, 2, 3], weights=[60, 30, 10])[0]):
                valid = [b for b, expiry in batches_by_med.get(med_id, []) if expiry >= day]
                if valid:                       # batches are ordered soonest expiry first (FEFO)
                    lines.append((valid[0], rng.choices(*QUANTITIES)[0], price))
            if not lines:
                continue
            when = datetime.combine(day, time(rng.randint(9, 20), rng.randint(0, 59)))
            sales.append((next_id,
                          rng.choice(customer_ids) if rng.random() < 0.55 else None,
                          rng.choice(staff_ids), when, rng.choices(*PAYMENT_MODES)[0]))
            items.extend((next_id, b, q, p) for b, q, p in lines)
            next_id += 1
        day += timedelta(days=1)

    try:
        cur.execute("ALTER TABLE sale_items DISABLE TRIGGER USER")
        execute_values(cur, "INSERT INTO sales (sale_id, customer_id, staff_id, sale_date, payment_mode) VALUES %s",
                       sales, page_size=1000)
        execute_values(cur, "INSERT INTO sale_items (sale_id, batch_id, quantity, unit_price) VALUES %s",
                       items, page_size=1000)
        cur.execute("ALTER TABLE sale_items ENABLE TRIGGER USER")

        cur.execute("""UPDATE sales s SET total_amount = t.total
                         FROM (SELECT sale_id, SUM(quantity * unit_price) AS total
                                 FROM sale_items WHERE sale_id > %s GROUP BY sale_id) t
                        WHERE s.sale_id = t.sale_id""", (last_sale_id,))
        cur.execute("""UPDATE batches b SET received_date = f.first_sale::date - 1
                         FROM (SELECT si.batch_id, MIN(s.sale_date) AS first_sale
                                 FROM sale_items si JOIN sales s ON s.sale_id = si.sale_id
                                WHERE s.sale_id > %s GROUP BY si.batch_id) f
                        WHERE f.batch_id = b.batch_id AND f.first_sale::date < b.received_date""",
                    (last_sale_id,))
        moved = cur.rowcount
        cur.execute("SELECT setval(pg_get_serial_sequence('sales', 'sale_id'), (SELECT MAX(sale_id) FROM sales))")
        conn.commit()
    except Exception:
        conn.rollback()
        raise

    print(f"Loaded {len(sales)} sales with {len(items)} lines, {start} to {end}.")
    print(f"Moved received_date back on {moved} batches so no batch is sold before it was received.")
    print("Current stock was not changed. Next: python ai/forecast_demand.py")
    conn.close()


if __name__ == "__main__":
    main()
