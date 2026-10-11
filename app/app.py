"""Pharmacy Inventory, Expiry and Demand Forecasting - Streamlit app.

Pages
  Dashboard      KPIs and charts
  Inventory      stock per medicine, batches with expiry status
  Alerts         open alerts, run the expiry / low-stock scans, resolve alerts
  New sale       point of sale: FEFO batch picking, all rules enforced by the triggers
  Purchasing     purchase orders, receive a PO, create a PO (can start from forecast suggestions)
  Forecast       saved demand forecasts, history chart, run forecast_demand.py
  Sales history  past sales and their lines

Run from the repo root:
    streamlit run app/app.py

Expected layout:  <repo>/ai/db.py (+ the other scripts), <repo>/app/app.py, <repo>/.env
Business rules live in the database (triggers). The app only inserts into sales and
sale_items and never writes batches.quantity_in_stock or sales.total_amount.
"""
import subprocess
import sys
from contextlib import closing
from datetime import date, timedelta
from decimal import Decimal
from pathlib import Path

import pandas as pd
import psycopg2
import streamlit as st

ROOT = Path(__file__).resolve().parent.parent
AI_DIR = ROOT / "ai"
for p in (AI_DIR, Path(__file__).resolve().parent):
    sys.path.insert(0, str(p))

from db import get_connection  # noqa: E402

st.set_page_config(page_title="Pharmacy", page_icon="💊", layout="wide")


# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------
def _clean(df: pd.DataFrame) -> pd.DataFrame:
    """Turn Decimal columns into floats so charts and formatting work."""
    for c in df.columns:
        if df[c].map(lambda x: isinstance(x, Decimal)).any():
            df[c] = df[c].astype(float)
    return df


def q(sql, params=None) -> pd.DataFrame:
    """Run a read query and return a DataFrame (fresh connection each time)."""
    with closing(get_connection()) as conn, conn.cursor() as cur:
        cur.execute(sql, params)
        cols = [d[0] for d in cur.description]
        return _clean(pd.DataFrame(cur.fetchall(), columns=cols))


def execute(sql, params=None):
    """Run one write statement in its own transaction. Returns the first row, if any."""
    with closing(get_connection()) as conn:
        try:
            with conn.cursor() as cur:
                cur.execute(sql, params)
                row = cur.fetchone() if cur.description else None
            conn.commit()
            return row
        except Exception:
            conn.rollback()
            raise


def pg_message(e: Exception) -> str:
    diag = getattr(e, "diag", None)
    msg = diag.message_primary if diag is not None and diag.message_primary else str(e)
    return msg.strip()


def flash(msg: str, kind: str = "success"):
    """Show a message after the next rerun."""
    st.session_state["_flash"] = (kind, msg)


def show_flash():
    item = st.session_state.pop("_flash", None)
    if item:
        getattr(st, item[0])(item[1])


def expiry_status(days_left: int) -> str:
    if days_left < 0:
        return "🔴 expired"
    if days_left <= 30:
        return "🟠 within 30 days"
    if days_left <= 90:
        return "🟡 within 90 days"
    return "🟢 ok"


def money(x) -> str:
    return f"₹{float(x):,.2f}"


# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------
def page_dashboard():
    st.title("Dashboard")
    k = q("""
        SELECT
          (SELECT COALESCE(SUM(sellable_stock), 0) FROM v_medicine_stock)            AS sellable_units,
          (SELECT count(*) FROM v_low_stock)                                         AS low_stock,
          (SELECT count(*) FROM batches
            WHERE quantity_in_stock > 0
              AND expiry_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 30)            AS near_expiry,
          (SELECT COALESCE(SUM(quantity_in_stock * purchase_price), 0) FROM batches
            WHERE quantity_in_stock > 0 AND expiry_date < CURRENT_DATE)              AS expired_loss,
          (SELECT COALESCE(SUM(total_amount), 0) FROM sales
            WHERE sale_date >= now() - INTERVAL '30 days')                           AS revenue_30d,
          (SELECT count(*) FROM stock_alerts WHERE NOT resolved)                     AS open_alerts
    """).iloc[0]

    c = st.columns(6)
    c[0].metric("Sellable units", f"{int(k.sellable_units):,}")
    c[1].metric("Low-stock medicines", int(k.low_stock))
    c[2].metric("Batches expiring ≤ 30d", int(k.near_expiry))
    c[3].metric("Expired stock (at cost)", money(k.expired_loss))
    c[4].metric("Revenue, last 30 days", money(k.revenue_30d))
    c[5].metric("Open alerts", int(k.open_alerts))

    left, right = st.columns(2)
    with left:
        st.subheader("Daily revenue, last 30 days")
        daily = q("""SELECT sale_date::date AS day, SUM(total_amount)::float AS revenue
                       FROM sales WHERE sale_date >= now() - INTERVAL '30 days'
                      GROUP BY 1 ORDER BY 1""")
        if daily.empty:
            st.info("No sales in the last 30 days.")
        else:
            st.line_chart(daily.set_index("day")["revenue"])
    with right:
        st.subheader("Top 5 sellers, last 30 days")
        top = q("""SELECT m.name AS medicine, SUM(si.quantity)::int AS units_sold,
                          SUM(si.quantity * si.unit_price)::float AS revenue
                     FROM sale_items si
                     JOIN sales s     ON s.sale_id = si.sale_id
                     JOIN batches b   ON b.batch_id = si.batch_id
                     JOIN medicines m ON m.medicine_id = b.medicine_id
                    WHERE s.sale_date >= now() - INTERVAL '30 days'
                    GROUP BY m.name ORDER BY units_sold DESC LIMIT 5""")
        if top.empty:
            st.info("No sales in the last 30 days.")
        else:
            st.bar_chart(top.set_index("medicine")["units_sold"])
            st.dataframe(top, hide_index=True)

    st.subheader("Monthly revenue by category")
    monthly = q("""SELECT date_trunc('month', s.sale_date)::date AS month, c.name AS category,
                          SUM(si.quantity * si.unit_price)::float AS revenue
                     FROM sales s
                     JOIN sale_items si ON si.sale_id = s.sale_id
                     JOIN batches b     ON b.batch_id = si.batch_id
                     JOIN medicines m   ON m.medicine_id = b.medicine_id
                     JOIN categories c  ON c.category_id = m.category_id
                    GROUP BY 1, 2 ORDER BY 1""")
    if monthly.empty:
        st.info("No sales yet.")
    else:
        pivot = monthly.pivot(index="month", columns="category", values="revenue").fillna(0)
        st.bar_chart(pivot)


# ---------------------------------------------------------------------------
# Inventory
# ---------------------------------------------------------------------------
def page_inventory():
    st.title("Inventory")
    tab_stock, tab_batches = st.tabs(["Stock per medicine", "Batches and expiry"])

    with tab_stock:
        df = q("""SELECT v.medicine_id, v.name AS medicine, v.category, v.sellable_stock,
                         v.reorder_level, v.expired_stock, m.requires_prescription AS rx
                    FROM v_medicine_stock v JOIN medicines m ON m.medicine_id = v.medicine_id
                   ORDER BY v.name""")
        df["status"] = df.apply(
            lambda r: "🔴 out of stock" if r.sellable_stock == 0
            else ("🟠 low" if r.sellable_stock < r.reorder_level else "🟢 ok"), axis=1)
        c1, c2, c3 = st.columns([2, 3, 1])
        search = c1.text_input("Search medicine")
        cats = c2.multiselect("Category", sorted(df["category"].unique()))
        low_only = c3.checkbox("Low / out only")
        if search:
            df = df[df["medicine"].str.contains(search, case=False)]
        if cats:
            df = df[df["category"].isin(cats)]
        if low_only:
            df = df[df["status"] != "🟢 ok"]
        st.dataframe(df.drop(columns="medicine_id"), hide_index=True)
        st.caption(f"{len(df)} medicines. Sellable stock excludes expired batches.")

    with tab_batches:
        b = q("""SELECT b.batch_id, m.name AS medicine, b.batch_no, sp.name AS supplier,
                        b.quantity_in_stock AS qty, b.purchase_price, b.received_date,
                        b.expiry_date, (b.expiry_date - CURRENT_DATE) AS days_left
                   FROM batches b
                   JOIN medicines m  ON m.medicine_id = b.medicine_id
                   JOIN suppliers sp ON sp.supplier_id = b.supplier_id
                  ORDER BY b.expiry_date""")
        b["status"] = b["days_left"].map(expiry_status)
        c1, c2 = st.columns([2, 1])
        status = c1.selectbox("Expiry status", ["All", "🔴 expired", "🟠 within 30 days",
                                                "🟡 within 90 days", "🟢 ok"])
        hide_empty = c2.checkbox("Hide empty batches", value=True)
        if status != "All":
            b = b[b["status"] == status]
        if hide_empty:
            b = b[b["qty"] > 0]
        st.dataframe(b, hide_index=True)
        st.caption("Sorted soonest expiry first (FEFO). Expired batches cannot be sold: "
                   "the database rejects them.")


# ---------------------------------------------------------------------------
# Alerts
# ---------------------------------------------------------------------------
def page_alerts():
    st.title("Alerts")
    c1, c2, c3 = st.columns([1, 1, 2])
    days = c3.number_input("Expiry window (days)", min_value=1, max_value=365, value=30)
    if c1.button("Scan for expiry alerts"):
        try:
            n = execute("SELECT fn_generate_expiry_alerts(%s)", (int(days),))[0]
        except psycopg2.Error as e:
            st.error(pg_message(e))
        else:
            flash(f"{n} new expiry alert(s) created.")
            st.rerun()
    if c2.button("Scan for low stock"):
        try:
            n = execute("SELECT fn_generate_low_stock_alerts()")[0]
        except psycopg2.Error as e:
            st.error(pg_message(e))
        else:
            flash(f"{n} new low-stock alert(s) created.")
            st.rerun()

    show_flash()
    alerts = q("""SELECT a.alert_id, a.alert_type, m.name AS medicine, a.message,
                         a.created_at::date AS raised_on
                    FROM stock_alerts a JOIN medicines m ON m.medicine_id = a.medicine_id
                   WHERE NOT a.resolved ORDER BY a.alert_type, m.name""")
    st.subheader(f"Open alerts ({len(alerts)})")
    if alerts.empty:
        st.success("No open alerts.")
        return
    types = st.multiselect("Type", sorted(alerts["alert_type"].unique()),
                           default=sorted(alerts["alert_type"].unique()))
    view = alerts[alerts["alert_type"].isin(types)].reset_index(drop=True)
    event = st.dataframe(view, hide_index=True, on_select="rerun",
                         selection_mode="multi-row", key="alerts_table")
    ids = [int(view.iloc[i]["alert_id"]) for i in event.selection.rows]
    if st.button(f"Mark {len(ids)} selected as resolved", disabled=not ids):
        execute("UPDATE stock_alerts SET resolved = TRUE WHERE alert_id = ANY(%s)", (ids,))
        flash(f"{len(ids)} alert(s) resolved.")
        st.rerun()
    st.caption("Low-stock alerts resolve themselves when stock is back at the reorder level. "
               "Expiry alerts are raised again at the next scan while the batch is still "
               "expired or near expiry, so act on the batch (discount, return) rather than "
               "just closing the alert.")


# ---------------------------------------------------------------------------
# New sale
# ---------------------------------------------------------------------------
def complete_sale(customer_id, staff_id, mode, cart, names):
    """Insert the sale and its lines in ONE transaction, picking batches FEFO.

    unit_price is left out so trg_validate_sale_item fills it; the triggers also
    check expiry and stock, reduce stock and keep sales.total_amount in step.
    """
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("""INSERT INTO sales (customer_id, staff_id, payment_mode)
                           VALUES (%s, %s, %s) RETURNING sale_id""",
                        (customer_id, staff_id, mode))
            sale_id = cur.fetchone()[0]
            for med_id, qty in cart.items():
                cur.execute("""SELECT b.batch_id, b.quantity_in_stock
                                 FROM batches b
                                WHERE b.medicine_id = %s AND b.expiry_date >= CURRENT_DATE
                                  AND b.quantity_in_stock > 0
                                ORDER BY b.expiry_date, b.batch_id
                                  FOR UPDATE OF b""", (med_id,))
                remaining = qty
                for batch_id, stock in cur.fetchall():
                    take = min(remaining, stock)
                    cur.execute("""INSERT INTO sale_items (sale_id, batch_id, quantity)
                                   VALUES (%s, %s, %s)""", (sale_id, batch_id, take))
                    remaining -= take
                    if remaining == 0:
                        break
                if remaining:
                    raise ValueError(f"Not enough sellable stock for {names[med_id]}: "
                                     f"short by {remaining}")
            cur.execute("SELECT total_amount FROM sales WHERE sale_id = %s", (sale_id,))
            total = cur.fetchone()[0]
        conn.commit()
        return sale_id, total
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def page_new_sale():
    st.title("New sale")
    st.session_state.setdefault("cart", {})
    cart: dict = st.session_state["cart"]
    show_flash()

    meds = q("""SELECT m.medicine_id, m.name, m.unit_price, m.requires_prescription AS rx,
                       v.sellable_stock
                  FROM medicines m JOIN v_medicine_stock v ON v.medicine_id = m.medicine_id
                 ORDER BY m.name""")
    info = {int(r.medicine_id): r for r in meds.itertuples()}

    def label(mid):
        r = info[mid]
        return (f"{r.name}{' (Rx)' if r.rx else ''} - {money(r.unit_price)} "
                f"- {int(r.sellable_stock)} in stock")

    left, right = st.columns([3, 2])

    with left:
        st.subheader("Add medicine")
        mid = st.selectbox("Medicine", list(info), format_func=label)
        stock = int(info[mid].sellable_stock)
        qty = st.number_input("Quantity", min_value=1, max_value=max(stock, 1), value=1, step=1)
        if st.button("Add to cart", disabled=stock == 0):
            new_qty = cart.get(mid, 0) + int(qty)
            if new_qty > stock:
                st.warning(f"Only {stock} units of {info[mid].name} are sellable "
                           f"({cart.get(mid, 0)} already in the cart).")
            else:
                cart[mid] = new_qty
                st.rerun()
        if stock == 0:
            st.warning("No sellable stock for this medicine.")

    with right:
        st.subheader("Cart")
        if not cart:
            st.info("The cart is empty.")
        total = 0.0
        for cid, cq in list(cart.items()):
            r = info[cid]
            line = cq * float(r.unit_price)
            total += line
            c1, c2 = st.columns([5, 1])
            c1.write(f"**{r.name}** × {cq} = {money(line)}")
            if c2.button("✕", key=f"rm_{cid}"):
                del cart[cid]
                st.rerun()
        if cart:
            st.markdown(f"### Total: {money(total)}")

    if cart:
        st.divider()
        st.subheader("Complete the sale")
        customers = q("SELECT customer_id, full_name, phone FROM customers ORDER BY full_name")
        staff = q("SELECT staff_id, full_name, role FROM staff ORDER BY full_name")
        cust_map = {None: "Walk-in customer"}
        cust_map.update({int(r.customer_id): f"{r.full_name} ({r.phone})" for r in customers.itertuples()})
        staff_map = {int(r.staff_id): f"{r.full_name} ({r.role})" for r in staff.itertuples()}

        c1, c2, c3 = st.columns(3)
        customer = c1.selectbox("Customer", list(cust_map), format_func=cust_map.get)
        staff_id = c2.selectbox("Served by", list(staff_map), format_func=staff_map.get)
        mode = c3.selectbox("Payment", ["cash", "upi", "card"])

        rx_items = [info[c].name for c in cart if info[c].rx]
        rx_ok = True
        if rx_items:
            rx_ok = st.checkbox("I have checked a valid prescription for: " + ", ".join(rx_items))

        if st.button("Complete sale", type="primary", disabled=not rx_ok):
            names = {c: info[c].name for c in cart}
            try:
                sale_id, tot = complete_sale(customer, staff_id, mode, cart, names)
            except psycopg2.Error as e:
                st.error(f"Sale rejected by the database, nothing was saved: {pg_message(e)}")
            except ValueError as e:
                st.error(f"Sale cancelled, nothing was saved: {e}")
            else:
                st.session_state["cart"] = {}
                flash(f"Sale #{sale_id} saved. Total {money(tot)}. Stock updated.")
                st.session_state["last_sale"] = sale_id
                st.rerun()

    last = st.session_state.get("last_sale")
    if last:
        with st.expander(f"Receipt for sale #{last}", expanded=True):
            lines = q("""SELECT m.name AS medicine, b.batch_no, si.quantity,
                                si.unit_price, si.quantity * si.unit_price AS line_total
                           FROM sale_items si
                           JOIN batches b   ON b.batch_id = si.batch_id
                           JOIN medicines m ON m.medicine_id = b.medicine_id
                          WHERE si.sale_id = %s ORDER BY m.name""", (int(last),))
            st.dataframe(lines, hide_index=True)
            st.write(f"**Total: {money(lines['line_total'].sum())}**")


# ---------------------------------------------------------------------------
# Purchasing
# ---------------------------------------------------------------------------
SUGGESTION_SQL = """
    SELECT m.medicine_id, m.name AS medicine,
           (f.predicted_qty - v.sellable_stock)::int AS quantity,
           COALESCE((SELECT b.purchase_price FROM batches b
                      WHERE b.medicine_id = m.medicine_id
                      ORDER BY b.received_date DESC, b.batch_id DESC LIMIT 1),
                    round(m.unit_price * 0.7, 2)) AS unit_cost
      FROM demand_forecasts f
      JOIN medicines m        ON m.medicine_id = f.medicine_id
      JOIN v_medicine_stock v ON v.medicine_id = f.medicine_id
     WHERE f.forecast_month = date_trunc('month', CURRENT_DATE + INTERVAL '1 month')::date
       AND f.predicted_qty > v.sellable_stock
     ORDER BY quantity DESC
"""


def _empty_po_draft() -> pd.DataFrame:
    return pd.DataFrame({"medicine": pd.Series(dtype="object"),
                         "quantity": pd.Series(dtype="int64"),
                         "unit_cost": pd.Series(dtype="float64")})


def page_purchasing():
    st.title("Purchasing")
    show_flash()
    tab_po, tab_new = st.tabs(["Purchase orders", "New purchase order"])

    with tab_po:
        pos = q("""SELECT po.po_id, sp.name AS supplier, po.order_date, po.status,
                          COUNT(i.po_item_id) AS items,
                          COALESCE(SUM(i.quantity * i.unit_cost), 0) AS value
                     FROM purchase_orders po
                     JOIN suppliers sp ON sp.supplier_id = po.supplier_id
                     LEFT JOIN purchase_order_items i ON i.po_id = po.po_id
                    GROUP BY po.po_id, sp.name
                    ORDER BY po.po_id DESC""")
        st.dataframe(pos, hide_index=True)
        if pos.empty:
            st.info("No purchase orders yet.")
        else:
            po_id = st.selectbox("Open a purchase order", pos["po_id"].tolist())
            po_id = int(po_id)
            items = q("""SELECT m.name AS medicine, i.quantity, i.unit_cost,
                                i.quantity * i.unit_cost AS line_total
                           FROM purchase_order_items i
                           JOIN medicines m ON m.medicine_id = i.medicine_id
                          WHERE i.po_id = %s ORDER BY m.name""", (po_id,))
            st.dataframe(items, hide_index=True)
            status = pos.loc[pos["po_id"] == po_id, "status"].iloc[0]
            if status == "placed":
                c1, c2, c3 = st.columns([1, 1, 2])
                shelf = c3.number_input("Shelf life of the new batches (days)", min_value=30,
                                        max_value=3650, value=730, step=30)
                if c1.button("Receive into stock", type="primary"):
                    try:
                        n = execute("SELECT fn_receive_purchase_order(%s, %s)",
                                    (po_id, int(shelf)))[0]
                    except psycopg2.Error as e:
                        st.error(pg_message(e))
                    else:
                        flash(f"PO {po_id} received: {n} batch(es) created.")
                        st.rerun()
                if c2.button("Cancel order"):
                    execute("UPDATE purchase_orders SET status = 'cancelled' "
                            "WHERE po_id = %s AND status = 'placed'", (po_id,))
                    flash(f"PO {po_id} cancelled.", "info")
                    st.rerun()
                st.caption("Receiving creates one batch per line (batch no. PO<id>-<medicine id>) "
                           "with expiry = today + shelf life. Edit the real expiry date from the "
                           "supplier's pack if it differs.")
            else:
                st.caption(f"This order is {status}; no further action.")

    with tab_new:
        sugg = q(SUGGESTION_SQL)
        st.subheader("Suggested from the forecast")
        if sugg.empty:
            st.info("No suggestions: forecast demand is covered by sellable stock "
                    "(or no forecast exists for next month).")
        else:
            st.dataframe(sugg.drop(columns="medicine_id"), hide_index=True)
            if st.button("Load suggestions into the order below"):
                st.session_state["po_draft"] = sugg[["medicine", "quantity", "unit_cost"]].copy()
                st.session_state["po_rev"] = st.session_state.get("po_rev", 0) + 1
                st.rerun()

        st.subheader("Order")
        suppliers = q("SELECT supplier_id, name, city FROM suppliers ORDER BY name")
        sup_map = {int(r.supplier_id): f"{r.name} ({r.city})" for r in suppliers.itertuples()}
        supplier = st.selectbox("Supplier", list(sup_map), format_func=sup_map.get)

        meds = q("SELECT medicine_id, name FROM medicines ORDER BY name")
        med_id_by_name = dict(zip(meds["name"], meds["medicine_id"].astype(int)))
        draft = st.session_state.get("po_draft", _empty_po_draft())
        rev = st.session_state.get("po_rev", 0)
        edited = st.data_editor(
            draft, num_rows="dynamic", key=f"po_editor_{rev}",
            column_config={
                "medicine": st.column_config.SelectboxColumn(options=list(med_id_by_name), required=True),
                "quantity": st.column_config.NumberColumn(min_value=1, step=1, required=True),
                "unit_cost": st.column_config.NumberColumn(min_value=0.01, format="%.2f", required=True),
            })

        if st.button("Place purchase order", type="primary"):
            rows = edited.dropna(subset=["medicine", "quantity", "unit_cost"])
            if rows.empty:
                st.error("Add at least one line.")
            elif rows["medicine"].duplicated().any():
                st.error("Each medicine can appear only once per order.")
            elif (rows["quantity"] <= 0).any() or (rows["unit_cost"] <= 0).any():
                st.error("Quantity and unit cost must be greater than zero.")
            else:
                conn = get_connection()
                try:
                    with conn.cursor() as cur:
                        cur.execute("INSERT INTO purchase_orders (supplier_id) VALUES (%s) "
                                    "RETURNING po_id", (supplier,))
                        new_po = cur.fetchone()[0]
                        for r in rows.itertuples():
                            cur.execute("""INSERT INTO purchase_order_items
                                               (po_id, medicine_id, quantity, unit_cost)
                                           VALUES (%s, %s, %s, %s)""",
                                        (new_po, med_id_by_name[r.medicine],
                                         int(r.quantity), float(r.unit_cost)))
                    conn.commit()
                except psycopg2.Error as e:
                    conn.rollback()
                    st.error(pg_message(e))
                else:
                    st.session_state.pop("po_draft", None)
                    st.session_state["po_rev"] = rev + 1
                    flash(f"Purchase order #{new_po} placed with {len(rows)} line(s).")
                    st.rerun()
                finally:
                    conn.close()


# ---------------------------------------------------------------------------
# Forecast
# ---------------------------------------------------------------------------
def page_forecast():
    st.title("Demand forecast")
    show_flash()

    with st.expander("Run the forecast script", expanded=False):
        method = st.radio("Method", ["moving_average", "linear"], horizontal=True,
                          format_func={"moving_average": "3-month moving average",
                                       "linear": "linear trend (6 months)"}.get)
        if st.button("Run forecast_demand.py"):
            script = AI_DIR / "forecast_demand.py"
            if not script.exists():
                st.error(f"{script} not found.")
            else:
                with st.spinner("Forecasting..."):
                    res = subprocess.run([sys.executable, str(script), "--method", method],
                                         cwd=AI_DIR, capture_output=True, text=True)
                st.code(res.stdout or "(no output)")
                if res.returncode != 0:
                    st.error(res.stderr or "The script failed.")
                else:
                    st.success("Done. Forecasts were saved to demand_forecasts.")

    fc = q("""SELECT m.medicine_id, m.name AS medicine, f.forecast_month, f.predicted_qty,
                     v.sellable_stock, GREATEST(f.predicted_qty - v.sellable_stock, 0) AS suggested_order,
                     f.method, f.generated_at::date AS generated_on
                FROM demand_forecasts f
                JOIN medicines m        ON m.medicine_id = f.medicine_id
                JOIN v_medicine_stock v ON v.medicine_id = f.medicine_id
               ORDER BY f.forecast_month DESC, suggested_order DESC, m.name""")
    if fc.empty:
        st.info("No forecasts yet. Run the script above.")
        return
    if (fc["method"] == "seed_estimate").any():
        st.warning("Some rows are placeholder 'seed_estimate' values. Run generate_sales_data.py "
                   "(once) and then the forecast script to replace them with real forecasts.")

    months = sorted(fc["forecast_month"].unique(), reverse=True)
    month = st.selectbox("Forecast month", months, format_func=lambda d: f"{d:%B %Y}")
    view = fc[fc["forecast_month"] == month]
    st.dataframe(view.drop(columns=["medicine_id", "forecast_month"]), hide_index=True)

    st.subheader("History and forecast for one medicine")
    med_names = dict(zip(view["medicine_id"].astype(int), view["medicine"]))
    mid = st.selectbox("Medicine", list(med_names), format_func=med_names.get)
    hist = q("""SELECT date_trunc('month', s.sale_date)::date AS month, SUM(si.quantity)::int AS units
                  FROM sale_items si
                  JOIN sales s   ON s.sale_id = si.sale_id
                  JOIN batches b ON b.batch_id = si.batch_id
                 WHERE b.medicine_id = %s AND s.sale_date < date_trunc('month', now())
                 GROUP BY 1 ORDER BY 1""", (int(mid),))
    if hist.empty:
        st.info("No complete months of sales for this medicine yet.")
        return
    hist["month"] = pd.to_datetime(hist["month"])
    last_complete = (pd.Timestamp(date.today()).replace(day=1) - pd.offsets.MonthBegin(1))
    idx = pd.date_range(hist["month"].min(), last_complete, freq="MS")
    actual = hist.set_index("month")["units"].reindex(idx, fill_value=0)
    chart = pd.DataFrame({"actual": actual, "forecast": 0})
    pred = view.loc[view["medicine_id"] == mid, "predicted_qty"].iloc[0]
    chart.loc[pd.Timestamp(month)] = [0, int(pred)]
    st.bar_chart(chart)
    st.caption("Months with no sales count as 0, the same rule the forecast script uses.")


# ---------------------------------------------------------------------------
# Sales history
# ---------------------------------------------------------------------------
def page_sales_history():
    st.title("Sales history")
    c1, c2 = st.columns(2)
    start = c1.date_input("From", value=date.today() - timedelta(days=30))
    end = c2.date_input("To", value=date.today())
    sales = q("""SELECT s.sale_id, s.sale_date, COALESCE(c.full_name, 'Walk-in') AS customer,
                        st.full_name AS served_by, s.payment_mode, s.total_amount
                   FROM sales s
                   LEFT JOIN customers c ON c.customer_id = s.customer_id
                   JOIN staff st         ON st.staff_id = s.staff_id
                  WHERE s.sale_date >= %s::date AND s.sale_date < (%s::date + 1)
                  ORDER BY s.sale_date DESC LIMIT 500""", (start, end))
    st.write(f"{len(sales)} sales, total {money(sales['total_amount'].sum() if len(sales) else 0)} "
             "(latest 500 shown at most). Click a row to see its lines.")
    event = st.dataframe(sales, hide_index=True, on_select="rerun",
                         selection_mode="single-row", key="sales_table")
    if event.selection.rows:
        sale_id = int(sales.iloc[event.selection.rows[0]]["sale_id"])
        lines = q("""SELECT m.name AS medicine, b.batch_no, si.quantity, si.unit_price,
                            si.quantity * si.unit_price AS line_total
                       FROM sale_items si
                       JOIN batches b   ON b.batch_id = si.batch_id
                       JOIN medicines m ON m.medicine_id = b.medicine_id
                      WHERE si.sale_id = %s ORDER BY m.name""", (sale_id,))
        st.subheader(f"Sale #{sale_id}")
        st.dataframe(lines, hide_index=True)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
PAGES = {
    "Dashboard": page_dashboard,
    "Inventory": page_inventory,
    "Alerts": page_alerts,
    "New sale": page_new_sale,
    "Purchasing": page_purchasing,
    "Forecast": page_forecast,
    "Sales history": page_sales_history,
}


def main():
    st.sidebar.title("💊 Pharmacy")
    page = st.sidebar.radio("Go to", list(PAGES), label_visibility="collapsed")
    try:
        q("SELECT 1")
    except psycopg2.Error as e:
        st.error("Cannot connect to the database. Check DB_HOST, DB_PORT, DB_NAME, DB_USER and "
                 f"DB_PASSWORD in your .env file.\n\n{pg_message(e)}")
        st.stop()
    PAGES[page]()


main()
