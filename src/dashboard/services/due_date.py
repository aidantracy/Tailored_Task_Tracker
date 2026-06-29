from __future__ import annotations
from datetime import date, timedelta
from typing import Iterable, Optional, Tuple

from workalendar.usa import UnitedStates


class BusinessCalendar:
    """
    Thin adapter around workalendar that supports:
      - weekend logic from workalendar (built-in)
      - custom 'extra_holidays' blacklist (dates you want to skip in addition)
    """
    def __init__(self, extra_holidays: Optional[Iterable[date]] = None):
        self.cal = UnitedStates()
        self.extra_holidays = set(extra_holidays or [])

    def is_business_day(self, d: date) -> bool:
        if not self.cal.is_working_day(d):
            return False
        if d in self.extra_holidays:
            return False
        return True

    def next_business_day(self, d: date) -> date:
        cur = d
        while not self.is_business_day(cur):
            cur += timedelta(days=1)
        return cur

    def add_business_days(self, start: date, offset: int) -> date:
        if offset == 0:
            return self.next_business_day(start)
        target = self.cal.add_working_days(start, offset)
        if not self.is_business_day(target):
            target = self.next_business_day(target)
        return target

    # ─── NEW: nth business day of a given (year, month) ─────────────────────────
    def nth_business_day_of_month(self, year: int, month: int, n: int) -> date:
        """
        Return the date of the Nth business day in the given month.
        n must be >= 1. Weekends, official holidays, and extra_holidays are skipped.
        """
        if n < 1:
            raise ValueError("n must be >= 1")
        cur = date(year, month, 1)
        count = 0
        while True:
            if self.is_business_day(cur):
                count += 1
                if count == n:
                    return cur
            cur += timedelta(days=1)
            # simple guard against runaway in pathological calendars
            if cur.month != month and count < n:
                raise ValueError(f"Month {year}-{month:02d} has fewer than {n} business days")

    # (Optional) Often useful alongside "Nth": last business day of month
    def last_business_day_of_month(self, year: int, month: int) -> date:
        """
        Return the last business day of the month.
        """
        # get first day of next month then step back
        if month == 12:
            nxt = date(year + 1, 1, 1)
        else:
            nxt = date(year, month + 1, 1)
        cur = nxt - timedelta(days=1)
        while not self.is_business_day(cur):
            cur -= timedelta(days=1)
        return cur


class DueDateEngine:
    """
    Small façade that returns (due_date, notes) for debugging/traceability.
    """
    def __init__(self, calendar: BusinessCalendar):
        self.cal = calendar

    def compute(self, start: date, offset: int) -> Tuple[date, list[str]]:
        notes = []
        normalized = self.cal.next_business_day(start)
        if normalized != start:
            notes.append(f"Normalized start to business day: {normalized.isoformat()}")
        due = self.cal.add_business_days(normalized, offset)
        if due != normalized and offset == 0:
            notes.append("Offset=0 still normalizes to the nearest business day.")
        return due, notes

    # ─── NEW: compute Nth business day result for a month ───────────────────────
    def compute_nth_business_day_of_month(self, year: int, month: int, n: int) -> Tuple[date, list[str]]:
        d = self.cal.nth_business_day_of_month(year, month, n)
        notes = [f"Nth business day rule: n={n} for {year}-{month:02d} → {d.isoformat()}"]
        return d, notes
