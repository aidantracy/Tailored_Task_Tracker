# Month-End Close — Business-Day Schedule

LedgerLine anchors each milestone *step* to a specific **business day** of the
month (weekends and holidays excluded), not a fixed calendar date. The default
close cadence is:

| Business day | Milestone step | Month |
|---|---|---|
| Day 20 | Populate Financials | Current month |
| Day 23 | First Review Complete | Current month |
| Day 25 | Second Review Complete | Current month |
| Day 1 | Flash JE Upload | Following month |
| Day 4 | Final JE Upload | Following month |

Because the dates are derived from business-day math (see
`src/dashboard/services/due_date.py`), the board stays correct automatically as
months change — a deadline that would otherwise fall on a weekend or holiday is
pushed to the next valid business day.
