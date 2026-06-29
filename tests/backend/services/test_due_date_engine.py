from datetime import date
from dashboard.services.due_date import BusinessCalendar, DueDateEngine


def test_add_business_days_skips_weekend_and_holiday():

    # Example: July 4th, 2025 is a US holiday (Friday). Start on 2025-07-03 (Thu), add 1 day -> 2025-07-07 (Mon)
    cal = BusinessCalendar()
    engine = DueDateEngine(cal)

    start = date(2025, 7, 3)
    due, _ = engine.compute(start, 1)
    assert due.weekday() == 0  # Monday

def test_normalize_start_if_weekend():

    cal = BusinessCalendar()
    engine = DueDateEngine(cal)
    start = date(2025, 7, 5)  # Saturday
    due, notes = engine.compute(start, 0)
    assert "Normalized start" in " ".join(notes)
    assert due.weekday() in (0,1,2,3,4)  # Mon-Fri
