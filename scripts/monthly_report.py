#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Monthly attendance dashboard
- runs on the 1st of each month; reports the WHOLE previous month
- reads clock records from Supabase
- builds an .xlsx dashboard: one row per employee, one column group per day
  (Clock In Time / Clock Out Time / Working Hours / OT Hours)
  - Working Hours: actual hours capped at 8 per day
  - OT Hours: floor(hours beyond 8), 0 if none
  - missing punch: "NA"
- emails an HTML summary + the xlsx via SMTP (Gmail)

Environment variables:
  SUPABASE_URL          Supabase project URL
  SUPABASE_SERVICE_KEY  Supabase service_role key (server-side only, never in frontend)
  SMTP_HOST             default smtp.gmail.com
  SMTP_PORT             default 587
  SMTP_USER             sender Gmail address
  SMTP_PASS             Gmail app password
  REPORT_TO             recipient email
  REPORT_CC             CC recipients, comma-separated (optional)
  APP_TZ                timezone, default Asia/Kuala_Lumpur
  REPORT_MONTH          manually specify month YYYY-MM (for testing; forces a run)
"""

import os
import smtplib
import sys
from calendar import monthrange
from datetime import date, datetime, time, timedelta, timezone
from email.header import Header
from email.mime.application import MIMEApplication
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from zoneinfo import ZoneInfo

import requests
from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

SUPABASE_URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_KEY", "")
SMTP_HOST = os.environ.get("SMTP_HOST") or "smtp.gmail.com"
SMTP_PORT = int(os.environ.get("SMTP_PORT") or "587")
SMTP_USER = os.environ.get("SMTP_USER", "")
SMTP_PASS = os.environ.get("SMTP_PASS", "")
REPORT_TO = os.environ.get("REPORT_TO", "")
REPORT_CC = [e.strip() for e in os.environ.get("REPORT_CC", "").split(",") if e.strip()]
TZ = ZoneInfo(os.environ.get("APP_TZ") or "Asia/Kuala_Lumpur")

NA = "NA"
# Night shift: a clock-out before this hour (MYT) belongs to the previous
# calendar day if that day has a clock-in but no clock-out yet.
NIGHT_OUT_CUTOFF_HOUR = 12


# ---------- date helpers ----------

def is_first_of_month(today=None):
    """whether today is the 1st (in the configured timezone)"""
    today = today or datetime.now(TZ).date()
    return today.day == 1


def target_month():
    """target month: previous month by default; REPORT_MONTH overrides (YYYY-MM)"""
    override = os.environ.get("REPORT_MONTH", "").strip()
    if override:
        y, m = map(int, override.split("-"))
        return y, m
    today = datetime.now(TZ).date()
    prev = today.replace(day=1) - timedelta(days=1)
    return prev.year, prev.month


def month_days(year, month):
    return [date(year, month, d) for d in range(1, monthrange(year, month)[1] + 1)]


# ---------- data fetching ----------

def sb_get(path, params):
    r = requests.get(
        f"{SUPABASE_URL}/rest/v1/{path}",
        params=params,
        headers={"apikey": SERVICE_KEY, "Authorization": f"Bearer {SERVICE_KEY}"},
        timeout=30,
    )
    r.raise_for_status()
    return r.json()


def fetch_data(year, month):
    # month boundaries in MYT, converted to UTC for the query.
    # End is extended by 12h to catch night-shift clock-outs that
    # belong to the last day of the month.
    start_utc = datetime(year, month, 1, tzinfo=TZ).astimezone(timezone.utc)
    end_utc = (datetime(year + (month == 12), month % 12 + 1, 1, tzinfo=TZ)
               + timedelta(hours=NIGHT_OUT_CUTOFF_HOUR)).astimezone(timezone.utc)
    employees = sb_get("employees", {
        "select": "id,name,staff_id,labor_type", "active": "eq.true", "order": "name",
    })
    records = sb_get("records", {
        "select": "employee_id,action,ts",
        "and": f"(ts.gte.{start_utc.isoformat()},ts.lt.{end_utc.isoformat()})",
        "order": "ts.asc",
        "limit": "50000",
    })
    return employees, records


# ---------- dashboard building (pure functions, easy to test) ----------

def fmt_time(dt):
    """'8:54:16 AM' style, like the reference dashboard"""
    return dt.strftime("%I:%M:%S %p").lstrip("0")


def build_dashboard(employees, records, year, month):
    """One row per employee; per day: clock-in time, clock-out time.

    Night shifts: a clock-out before NIGHT_OUT_CUTOFF_HOUR (MYT) is
    attributed to the previous calendar day when that day has a
    clock-in but no clock-out yet. Clock-ins always use their own date.
    """
    days = month_days(year, month)

    per_emp = {
        e["id"]: {
            "name": e["name"],
            "staff_id": e.get("staff_id") or "",
            "labor_type": e.get("labor_type") or "",
            "days": {},
        }
        for e in employees
    }

    # pass 1: clock-ins use their own calendar day (earliest per day)
    for r in records:
        if r.get("action") != "in":
            continue
        eid = r.get("employee_id")
        if eid not in per_emp:
            continue
        local = datetime.fromisoformat(r["ts"]).astimezone(TZ)
        if local.date().year != year or local.date().month != month:
            continue
        d = per_emp[eid]["days"].setdefault(local.date().isoformat(), {"in": None, "out": None})
        if d["in"] is None or local < d["in"]:
            d["in"] = local

    # pass 2: clock-outs in chronological order, with night-shift attribution
    outs = sorted(
        (r for r in records if r.get("action") == "out" and r.get("employee_id") in per_emp),
        key=lambda r: r["ts"],
    )
    for r in outs:
        eid = r["employee_id"]
        local = datetime.fromisoformat(r["ts"]).astimezone(TZ)
        target = local.date()
        if local.hour < NIGHT_OUT_CUTOFF_HOUR:
            prev = target - timedelta(days=1)
            pd = per_emp[eid]["days"].get(prev.isoformat())
            if pd is not None and pd["in"] is not None and pd["out"] is None:
                target = prev
        if target.year != year or target.month != month:
            continue
        d = per_emp[eid]["days"].setdefault(target.isoformat(), {"in": None, "out": None})
        if d["out"] is None or local > d["out"]:
            d["out"] = local

    rows = []
    for eid, info in per_emp.items():
        cells = {}  # day_iso -> dict(in, out)
        days_present = 0
        for day in days:
            key = day.isoformat()
            d = info["days"].get(key, {"in": None, "out": None})
            cell = {"in": NA, "out": NA}
            if d["in"]:
                days_present += 1
                cell["in"] = fmt_time(d["in"])
                if d["out"] and d["out"] > d["in"]:
                    cell["out"] = fmt_time(d["out"])
            cells[key] = cell
        rows.append({
            "staff_id": info["staff_id"],
            "name": info["name"],
            "labor_type": info["labor_type"],
            "cells": cells,
            "days_present": days_present,
        })

    rows.sort(key=lambda x: x["name"])
    return days, rows


def render_xlsx(year, month, days, rows, path):
    title = f"Attendance Dashboard - {date(year, month, 1).strftime('%B %Y')}"
    wb = Workbook()
    ws = wb.active
    ws.title = "Dashboard"

    thin = Side(style="thin", color="D0D0D0")
    border = Border(left=thin, right=thin, top=thin, bottom=thin)
    hdr_fill = PatternFill("solid", fgColor="FF1F4E79")
    sub_fill = PatternFill("solid", fgColor="FFD9E2F3")
    hdr_font = Font(bold=True, color="FFFFFF", size=11)
    sub_font = Font(bold=True, size=10)
    label_fill = PatternFill("solid", fgColor="FF92D050")  # green Clock In/Out labels
    label_font = Font(bold=True, size=11)
    center = Alignment(horizontal="center", vertical="center", wrap_text=True)

    ncols = 3 + 4 * len(days)

    # title row
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=ncols)
    c = ws.cell(row=1, column=1, value=title)
    c.font = Font(bold=True, size=14)
    c.alignment = Alignment(horizontal="center", vertical="center")
    ws.row_dimensions[1].height = 30

    # fixed headers + day headers (merged, 4 cols each)
    for ci, h in enumerate(["DL/IDL", "Staff ID", "Name"], start=1):
        cc = ws.cell(row=2, column=ci, value=h)
        cc.font = hdr_font
        cc.fill = hdr_fill
        cc.alignment = center
    for i, day in enumerate(days):
        col = 4 + i * 4
        ws.merge_cells(start_row=2, start_column=col, end_row=2, end_column=col + 3)
        cc = ws.cell(row=2, column=col, value=f"{day.day}-{day.strftime('%b')}")
        cc.font = hdr_font
        cc.fill = hdr_fill
        cc.alignment = center
    ws.row_dimensions[2].height = 22

    # data rows: [Clock In][time][Clock Out][time] per day, green labels
    for ri, r in enumerate(rows):
        excel_row = 3 + ri
        ws.cell(row=excel_row, column=1, value=r["labor_type"] or NA)
        ws.cell(row=excel_row, column=2, value=r["staff_id"])
        ws.cell(row=excel_row, column=3, value=r["name"])
        for i, day in enumerate(days):
            cell = r["cells"][day.isoformat()]
            base = 4 + i * 4
            has_in = cell["in"] != NA
            vals = ["Clock In", cell["in"], "Clock Out", cell["out"]] if has_in else [NA, NA, NA, NA]
            for j, v in enumerate(vals):
                cc = ws.cell(row=excel_row, column=base + j, value=v)
                cc.alignment = center
                if has_in and j in (0, 2):
                    cc.fill = label_fill
                    cc.font = label_font

    # borders + widths + freeze
    for row in ws.iter_rows(min_row=1, max_row=2 + len(rows), min_col=1, max_col=ncols):
        for cell in row:
            cell.border = border
    ws.column_dimensions["A"].width = 10
    ws.column_dimensions["B"].width = 14
    ws.column_dimensions["C"].width = 22
    for i in range(len(days)):
        for j, w in enumerate((12, 14, 12, 14)):
            ws.column_dimensions[get_column_letter(4 + i * 4 + j)].width = w
    ws.freeze_panes = "D3"
    ws.sheet_properties.pageSetUpPr = None

    wb.save(path)
    return title


def render_html(title, rows):
    body_rows = "\n".join(
        f"<tr><td>{r['labor_type'] or NA}</td>"
        f"<td>{r['staff_id']}</td><td>{r['name']}</td><td>{r['days_present']}</td></tr>"
        for r in rows
    ) or '<tr><td colspan="4">No records this month</td></tr>'
    return f"""\
<html><body style="font-family:sans-serif">
<h2>📋 {title}</h2>
<p>See the attached spreadsheet for the full daily breakdown.</p>
<table border="1" cellpadding="8" cellspacing="0" style="border-collapse:collapse">
<tr style="background:#f0f0f0"><th>DL/IDL</th><th>Staff ID</th><th>Name</th><th>Days Present</th></tr>
{body_rows}
</table>
<p style="color:#888;font-size:12px">Generated automatically by the attendance system. Please do not reply.</p>
</body></html>"""


# ---------- email sending ----------

def send_email(subject, html_body, attach_path, attach_name):
    msg = MIMEMultipart()
    msg["From"] = SMTP_USER
    msg["To"] = REPORT_TO
    if REPORT_CC:
        msg["Cc"] = ", ".join(REPORT_CC)
    msg["Subject"] = Header(subject, "utf-8")
    msg.attach(MIMEText(html_body, "html", "utf-8"))

    with open(attach_path, "rb") as f:
        part = MIMEApplication(
            f.read(),
            Name=attach_name,
            _subtype="vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        )
    part["Content-Disposition"] = f'attachment; filename="{attach_name}"'
    msg.attach(part)

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=30) as s:
        s.starttls()
        s.login(SMTP_USER, SMTP_PASS)
        s.sendmail(SMTP_USER, [REPORT_TO] + REPORT_CC, msg.as_string())


# ---------- main ----------

def main():
    if not all([SUPABASE_URL, SERVICE_KEY, SMTP_USER, SMTP_PASS, REPORT_TO]):
        print("missing required environment variables", file=sys.stderr)
        return 1

    forced = bool(os.environ.get("REPORT_MONTH", "").strip())
    if not forced and not is_first_of_month():
        print("today is not the 1st, skipping (report runs on the 1st for last month)")
        return 0

    year, month = target_month()
    print(f"generating dashboard for {year}-{month:02d}...")

    employees, records = fetch_data(year, month)
    days, rows = build_dashboard(employees, records, year, month)

    xlsx_name = f"attendance-dashboard-{year}-{month:02d}.xlsx"
    title = render_xlsx(year, month, days, rows, xlsx_name)

    html = render_html(title, rows)
    send_email(title, html, xlsx_name, xlsx_name)

    print(f"sent to {REPORT_TO}: {len(employees)} employees, {len(days)} days")
    return 0


if __name__ == "__main__":
    sys.exit(main())
