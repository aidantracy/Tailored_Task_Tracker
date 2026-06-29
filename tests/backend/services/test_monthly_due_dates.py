# tests/test_monthly_due_dates.py
from datetime import date
import pytest

from dashboard.services.due_date import BusinessCalendar, DueDateEngine

# Tasks you listed, keyed by calendar day-of-month
TASKS = {
    20: "populate financials",
    23: "first review complete",
    25: "second review complete",
    1:  "flash JE upload",
    4:  "final JE upload",
}

def adjust_to_business_day(cal: BusinessCalendar, d: date) -> date:
    """Return d if business day; otherwise the next business day."""
    return d if cal.is_business_day(d) else cal.next_business_day(d)

def month_expectations(year: int, month: int):
    """Return expected adjusted dates for all TASKS in a given month."""
    cal = BusinessCalendar()
    results = {}
    for dom, _name in TASKS.items():
        results[dom] = adjust_to_business_day(cal, date(year, month, dom))
    return results

@pytest.mark.parametrize(
    "year, month, expectations",
    [
        # July 2025:
        # - 7/04 is Independence Day (holiday) -> moves to 7/07 (Mon)
        # - 7/20 is Sunday -> moves to 7/21 (Mon)
        # - others should remain on their actual dates if they’re business days
        (2025, 7, {
            1:  date(2025, 7, 1),   # Tue
            4:  date(2025, 7, 7),   # Fri holiday -> Mon
            20: date(2025, 7, 21),  # Sun -> Mon
            23: date(2025, 7, 23),  # Wed
            25: date(2025, 7, 25),  # Fri
        }),

        # November 2025:
        # - 11/01 is Saturday -> moves to 11/03 (Mon)
        # - 11/23 is Sunday -> moves to 11/24 (Mon)
        (2025, 11, {
            1:  date(2025, 11, 3),  # Sat -> Mon
            4:  date(2025, 11, 4),  # Tue
            20: date(2025, 11, 20), # Thu
            23: date(2025, 11, 24), # Sun -> Mon
            25: date(2025, 11, 25), # Tue
        }),

        # January 2025:
        # - 1/01 is New Year's Day (holiday) -> moves to 1/02 (Thu)
        # - 1/20 is MLK Day (holiday) -> moves to 1/21 (Tue)
        (2025, 1, {
            1:  date(2025, 1, 2),   # Wed holiday -> Thu
            4:  date(2025, 1, 6),   # Sat -> Mon
            20: date(2025, 1, 21),  # Mon holiday -> Tue
            23: date(2025, 1, 23),  # Thu
            25: date(2025, 1, 27),  # Sat -> Mon
        }),
    ]
)
def test_fixed_day_deadlines_adjust_to_business_days(year, month, expectations):
    cal = BusinessCalendar()
    got = month_expectations(year, month)

    # Assert every configured day matches expected adjusted date
    for dom, expected_date in expectations.items():
        assert got[dom] == expected_date, f"Day {dom} expected {expected_date}, got {got[dom]}"

def test_all_fixed_days_return_business_days():
    """Sanity check: every adjusted date is indeed a business day."""
    cal = BusinessCalendar()
    for (year, month) in [(2025, 7), (2025, 11), (2025, 1)]:
        adjusted = month_expectations(year, month)
        for dom, d in adjusted.items():
            assert cal.is_business_day(d), f"Adjusted date for day {dom} is not a business day: {d}"


def test_nth_business_day_simple_month_no_holidays_march_2025():
    """
    March 2025 has no U.S. federal holidays in the first week.
    2025-03-01 is Saturday, so the first business day is Mon 2025-03-03.
    Counting business days: 3/3, 3/4, 3/5, 3/6 → 4th business day = 2025-03-06.
    """
    cal = BusinessCalendar()
    engine = DueDateEngine(cal)

    # Direct calendar call
    d_cal = cal.nth_business_day_of_month(2025, 3, 4)
    assert d_cal == date(2025, 3, 6)

    # Engine convenience method
    d_engine, notes = engine.compute_nth_business_day_of_month(2025, 3, 4)
    assert d_engine == date(2025, 3, 6)
    assert any("n=4" in s for s in notes)


def test_nth_business_day_with_holiday_in_first_week_january_2025():
    """
    January 1, 2025 (New Year's Day) is a U.S. federal holiday.
    That pushes the count so that the 4th business day becomes Tue 2025-01-07:
      Thu 1/2, Fri 1/3, Mon 1/6, Tue 1/7 → 4th business day = 2025-01-07.
    """
    cal = BusinessCalendar()
    engine = DueDateEngine(cal)

    d_cal = cal.nth_business_day_of_month(2025, 1, 4)
    assert d_cal == date(2025, 1, 7)

    d_engine, notes = engine.compute_nth_business_day_of_month(2025, 1, 4)
    assert d_engine == date(2025, 1, 7)
    assert any("n=4" in s for s in notes)


@pytest.mark.parametrize(
    "year, expected",
    [
        (2024, date(2024, 2, 6)),  # Leap year
        (2025, date(2025, 2, 6)),  # Non-leap year
    ],
)
def test_nth_business_day_february_leap_vs_nonleap(year, expected):
    """
    Ensure February’s leap vs. non-leap length doesn’t break early-month rules.
    U.S. federal holidays in Feb (e.g., Presidents’ Day) occur later in the month
    and do not affect the 4th business day in these specific years.
    """
    cal = BusinessCalendar()
    engine = DueDateEngine(cal)

    d_cal = cal.nth_business_day_of_month(year, 2, 4)
    assert d_cal == expected

    d_engine, _ = engine.compute_nth_business_day_of_month(year, 2, 4)
    assert d_engine == expected


def test_guard_excessive_n_raises_value_error():
    """
    Requesting an n that exceeds the number of business days in the month
    should raise a ValueError (as designed).
    """
    cal = BusinessCalendar()

    with pytest.raises(ValueError) as exc:
        cal.nth_business_day_of_month(2025, 2, 40)  # Intentionally absurd

    # Optional: check message clarity
    assert "fewer than 40 business days" in str(exc.value)