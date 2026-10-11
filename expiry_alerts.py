"""Create and show expiry and low-stock alerts.

  * Calls fn_generate_expiry_alerts(days) to create 'near_expiry' and 'expired' alerts.
  * Calls fn_generate_low_stock_alerts() if the database has it (added in the reviewed
    version of the schema files); skipped otherwise.
  * Prints the open alerts and the batches that need action.

Run:
    python ai/expiry_alerts.py            # batches expiring within 30 days
    python ai/expiry_alerts.py --days 60
"""
import argparse

import pandas as pd
import psycopg2

from db import get_connection


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--days", type=int, default=30, help="alert on batches expiring within this many days")
    args = ap.parse_args()

    conn = get_connection()
    cur = conn.cursor()

    cur.execute("SELECT fn_generate_expiry_alerts(%s)", (args.days,))
    new_expiry = cur.fetchone()[0]
    conn.commit()          # keep the expiry alerts even if the next call fails
    try:
        cur.execute("SELECT fn_generate_low_stock_alerts()")
        new_low = cur.fetchone()[0]
    except psycopg2.errors.UndefinedFunction:
        conn.rollback()
        new_low = None
    conn.commit()
    print(f"New expiry alerts: {new_expiry}"
          + (f" | new low-stock alerts: {new_low}" if new_low is not None else ""))

    cur.execute("""SELECT m.name AS medicine, a.alert_type, a.message, a.created_at::date AS raised_on
                     FROM stock_alerts a JOIN medicines m ON m.medicine_id = a.medicine_id
                    WHERE NOT a.resolved
                    ORDER BY a.alert_type, m.name""")
    alerts = pd.DataFrame(cur.fetchall(), columns=["medicine", "type", "message", "raised_on"])
    print(f"\nOpen alerts ({len(alerts)}):")
    print(alerts.to_string(index=False) if len(alerts) else "none")

    cur.execute("""SELECT medicine, batch_no, quantity_in_stock AS qty, expiry_date, days_left,
                          CASE WHEN days_left < 0 THEN 'remove from shelf / return to supplier'
                               ELSE 'discount or sell first' END AS action
                     FROM v_expiry_status
                    WHERE days_left <= %s
                    ORDER BY days_left""", (args.days,))
    batches = pd.DataFrame(cur.fetchall(), columns=["medicine", "batch_no", "qty", "expiry_date",
                                                    "days_left", "action"])
    print(f"\nBatches expired or expiring within {args.days} days ({len(batches)}):")
    print(batches.to_string(index=False) if len(batches) else "none")
    conn.close()


if __name__ == "__main__":
    main()
