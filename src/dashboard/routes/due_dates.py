# src/dashboard/routes/due_dates.py
from __future__ import annotations
from workalendar.usa import UnitedStates
from datetime import date, timedelta
from typing import Set, Optional
from flask import Blueprint, request, jsonify
from sqlalchemy import text
from dashboard import db

bp = Blueprint("due_dates", __name__, url_prefix="/api/due-date")

# --------- helpers ---------
def is_weekend(d: date) -> bool:
    return d.weekday() >= 5  # 5=Sat, 6=Sun


def load_holidays_for_year(year: int) -> Set[date]:
    """
    Use Workalendar's UnitedStates calendar for official holidays.
    No database schema change required.
    """
    cal = UnitedStates()
    return {d for d, _name in cal.holidays(year)}


def next_business_day_on_or_after(d: date, holidays: Set[date]) -> date:
    while is_weekend(d) or d in holidays:
        d += timedelta(days=1)
    return d

# --------- endpoints ---------
@bp.get("/by-day")
def by_day():
    """
    Compute the business date ON or AFTER the target calendar day.
    Query: year, month (1-12), day (1-31)
           [month_offset=0|1] (1 means use the following month)
    Example: /api/due-date/by-day?year=2025&month=11&day=23&month_offset=0
    """
    year  = request.args.get("year", type=int)
    month = request.args.get("month", type=int)
    day   = request.args.get("day", type=int)
    moff  = request.args.get("month_offset", default=0, type=int)

    if not year or not month or not day:
        return jsonify({"error": "year, month, and day are required"}), 400

    # Adjust month by offset (for Flash/Final which live in the next month)
    y, m = year, month + moff
    while m > 12:
        m -= 12
        y += 1

    # Clamp day to last day-of-month if user put 31 in a 30-day month
    try:
        target = date(y, m, day)
    except ValueError:
        # last day of month
        if m == 2:
            last = 29 if (y % 400 == 0 or (y % 4 == 0 and y % 100 != 0)) else 28
        elif m in (4, 6, 9, 11):
            last = 30
        else:
            last = 31
        target = date(y, m, min(day, last))

    holidays = load_holidays_for_year(target.year)
    due = next_business_day_on_or_after(target, holidays)
    return jsonify({
        "method": "by_day_roll_forward",
        "target_date": target.isoformat(),
        "due_date": due.isoformat(),
        "holidays_used": sorted(h.isoformat() for h in holidays),
    }), 200

# Keep /by-nth around if you need it elsewhere; not used by the column pills now.
@bp.get("/by-nth")
def by_nth():
    year  = request.args.get("year", type=int)
    month = request.args.get("month", type=int)
    nth   = request.args.get("nth", type=int)
    moff  = request.args.get("month_offset", default=0, type=int)
    if not year or not month or not nth:
        return jsonify({"error": "year, month, and nth are required"}), 400
    y, m = year, month + moff
    while m > 12:
        m -= 12
        y += 1
    holidays = load_holidays_for_year(y)
    # compute nth business day
    d = date(y, m, 1); count = 0
    while d.month == m:
        if d.weekday() < 5 and d not in holidays:
            count += 1
            if count == nth:
                return jsonify({
                    "method": "nth_business_day",
                    "due_date": d.isoformat(),
                }), 200
        d += timedelta(days=1)
    return jsonify({"error": "nth out of range for month"}), 400
