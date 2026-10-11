"""Forecast next month's demand for every medicine and save it to the database.

How it works
  1. Reads the units sold per medicine per calendar month (sale_items joined to
     batches and sales). The current month is skipped because it is not finished.
  2. Months with no sales are counted as 0, so a quiet month pulls the average down.
  3. Predicts the next month with a simple model:
       moving average  (default): the mean of the last 3 complete months
       linear          (--method linear): a straight-line trend over the last 6 months
  4. Writes the result to demand_forecasts with an upsert, so re-running replaces
     the old forecast instead of creating duplicates.
  5. Prints a reorder suggestion: predicted demand minus sellable stock.

Run after generate_sales_data.py:
    python ai/forecast_demand.py
    python ai/forecast_demand.py --method linear
"""
import argparse
from datetime import date

import pandas as pd
from sklearn.linear_model import LinearRegression

from db import get_connection

MONTHLY_SQL = """
    SELECT b.medicine_id,
           date_trunc('month', s.sale_date)::date AS month,
           SUM(si.quantity)::int AS units
      FROM sale_items si
      JOIN sales s   ON s.sale_id  = si.sale_id
      JOIN batches b ON b.batch_id = si.batch_id
     WHERE s.sale_date < date_trunc('month', now())
     GROUP BY b.medicine_id, date_trunc('month', s.sale_date)
"""

UPSERT_SQL = """
    INSERT INTO demand_forecasts (medicine_id, forecast_month, predicted_qty, method)
    VALUES (%s, %s, %s, %s)
    ON CONFLICT (medicine_id, forecast_month) DO UPDATE
       SET predicted_qty = EXCLUDED.predicted_qty,
           method        = EXCLUDED.method,
           generated_at  = now()
"""


def next_month_start(today: date) -> date:
    return date(today.year + (today.month == 12), today.month % 12 + 1, 1)


def predict(units: pd.Series, method: str) -> int:
    """units: complete months in order, zeros included."""
    if method == "linear":
        recent = units.tail(6)
        if len(recent) < 3:
            return max(0, round(recent.mean()))
        model = LinearRegression().fit([[i] for i in range(len(recent))], recent.values)
        return max(0, round(float(model.predict([[len(recent)]])[0])))
    return max(0, round(units.tail(3).mean()))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--method", choices=["moving_average", "linear"], default="moving_average")
    args = ap.parse_args()
    method_label = "moving_average_3m" if args.method == "moving_average" else "linear_regression_6m"

    conn = get_connection()
    cur = conn.cursor()
    cur.execute(MONTHLY_SQL)
    sales = pd.DataFrame(cur.fetchall(), columns=["medicine_id", "month", "units"])
    if sales.empty:
        print("No sales history yet. Run: python ai/generate_sales_data.py")
        return
    sales["month"] = pd.to_datetime(sales["month"])

    months = pd.date_range(sales["month"].min(), sales["month"].max(), freq="MS")
    cur.execute("SELECT medicine_id, name, sellable_stock FROM v_medicine_stock ORDER BY medicine_id")
    meds = cur.fetchall()
    target = next_month_start(date.today())

    rows, report = [], []
    for med_id, name, stock in meds:
        series = (sales[sales["medicine_id"] == med_id].set_index("month")["units"]
                  .reindex(months, fill_value=0))
        if series.sum() == 0:
            report.append((name, 0, int(stock), 0, "no sales history, forecast not changed"))
            continue
        qty = predict(series, args.method)
        rows.append((med_id, target, qty, method_label))
        report.append((name, qty, int(stock), max(0, qty - int(stock)), ""))

    cur.executemany(UPSERT_SQL, rows)
    conn.commit()

    df = pd.DataFrame(report, columns=["medicine", "predicted_qty", "sellable_stock",
                                       "suggested_order_qty", "note"])
    df = df.sort_values(["suggested_order_qty", "predicted_qty"], ascending=False)
    print(f"Forecast for {target:%B %Y} ({method_label}), based on {len(months)} complete months "
          f"({months[0]:%b %Y} to {months[-1]:%b %Y}):\n")
    print(df.drop(columns="note" if not df["note"].any() else []).to_string(index=False))
    print(f"\nSaved {len(rows)} forecasts to demand_forecasts.")
    conn.close()


if __name__ == "__main__":
    main()
