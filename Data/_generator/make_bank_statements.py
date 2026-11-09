"""
Generate 24 monthly 'bank statement' CSV files from payments_clean.csv
with deliberate, documented data-quality problems (portfolio project).
Deterministic: same input -> same output.
Usage: python make_bank_statements.py <payments_clean.csv> <output_dir>
"""
import sys, csv, random
from pathlib import Path
import pandas as pd

src, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
rng = random.Random(42)

df = pd.read_csv(src, encoding="utf-8-sig", dtype={"Amount": str})
df["Month"] = df["BookingDate"].str[:7]

# --- P5/P6: invoice reference in Description: format variants + missing/invalid refs
def describe(order_no: str) -> tuple[str, str]:
    r = rng.random()
    if r < 0.0010:   # P6a: no invoice reference at all
        return rng.choice(["Payment", "Online transfer", "Order payment", "Thank you"]), "no_reference"
    if r < 0.0012:   # P6b: invalid reference (last digit missing)
        return f"Payment for invoice INV-{order_no[:-1]}", "invalid_reference"
    if r < 0.8500:
        return f"Payment for invoice INV-{order_no}", "standard"
    if r < 0.9000:
        return f"INV {order_no}", "variant"
    if r < 0.9400:
        return f"inv-{order_no}", "variant"
    if r < 0.9700:
        return f"Invoice no. {order_no}", "variant"
    return f"{order_no}", "variant"

orders = df["Description"].str.extract(r"INV-(\d+)")[0]
res = [describe(o) for o in orders]
df["Description"] = [d for d, _ in res]
df["RefStatus"] = [s for _, s in res]

NEW_FORMAT_FROM = "2025-07"   # P3: bank changed export format
OVERLAP_MONTHS = {"2024-04": 2, "2024-10": 2, "2025-03": 1, "2025-07": 1}  # P4: overlap = days of previous month repeated

months = sorted(df["Month"].unique())
dup_rows = 0
for m in months:
    part = df[df["Month"] == m]
    if m in OVERLAP_MONTHS:
        prev = df[df["Month"] < m]
        last_days = sorted(prev["BookingDate"].unique())[-OVERLAP_MONTHS[m]:]
        extra = prev[prev["BookingDate"].isin(last_days)]
        dup_rows += len(extra)
        part = pd.concat([extra, part])
    y, mm = m.split("-")
    start = f"{m}-01"
    end = (pd.Period(m) .end_time.date()).isoformat()

    if m < NEW_FORMAT_FROM:
        # Old format: comma, dot decimal, ISO dates, 3 metadata lines, footer total, UTF-8 BOM
        path = out / f"contoso_bank_statement_{m}.csv"
        with open(path, "w", encoding="utf-8-sig", newline="") as f:
            f.write("Contoso Ltd. - account statement\r\n")
            f.write("Account: USD operating account\r\n")
            f.write(f"Period: {start} - {end}\r\n")
            w = csv.writer(f, lineterminator="\r\n")
            w.writerow(["TransactionId", "BookingDate", "Amount", "Currency", "PayerName", "Description"])
            for r in part.itertuples():
                w.writerow([r.TransactionId, r.BookingDate, r.Amount, r.Currency, r.PayerName, r.Description])
            total = sum(float(a) for a in part["Amount"])
            w.writerow(["Total credits", "", f"{total:.2f}", "USD", "", f"{len(part)} transactions"])
    else:
        # New format: semicolon, decimal comma, dd.MM.yyyy, renamed + reordered columns,
        # extra ValueDate column, no metadata, no footer, UTF-8 without BOM
        path = out / f"Statement_{y}{mm}.csv"
        def dmy(d): return f"{d[8:10]}.{d[5:7]}.{d[0:4]}"
        with open(path, "w", encoding="utf-8", newline="") as f:
            w = csv.writer(f, delimiter=";", lineterminator="\r\n")
            w.writerow(["Booking date", "Value date", "Transaction ID", "Counterparty", "Payment details", "Amount", "Currency"])
            for r in part.itertuples():
                w.writerow([dmy(r.BookingDate), dmy(r.BookingDate), r.TransactionId, r.PayerName,
                            r.Description, r.Amount.replace(".", ","), r.Currency])

# ---- control figures (answer key) ----
paid = df["Amount"].astype(float)
nr = df[df.RefStatus == "no_reference"]; ir = df[df.RefStatus == "invalid_reference"]
print("files:", len(months), "| unique transactions:", len(df), "| amount:", round(paid.sum(), 2))
print("duplicate rows from overlaps:", dup_rows, "| rows in files:", len(df) + dup_rows)
print("no reference:", len(nr), round(nr.Amount.astype(float).sum(), 2))
print("invalid reference:", len(ir), round(ir.Amount.astype(float).sum(), 2))
print("variants:", (df.RefStatus == "variant").sum())
df[df.RefStatus != "standard"][["TransactionId", "RefStatus"]].to_csv(out.parent / "_answer_key_references.csv", index=False)
