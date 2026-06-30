# LedgerLine

LedgerLine is a web app for running a finance team's monthly close. It lays the close out as a board of milestone steps, each tied to a specific business day of the month, and tracks every task from "not started" to "done" with owners, due dates, comments, and history.

This was an industry-sponsored project that counted as both our senior capstone and an internship. I built it with two teammates over a semester, working directly with our sponsor at a hospital system and collaborating with the cybersecurity team to shape the requirements and design the app around the hospital's real month-end close.

[![CI](https://github.com/aidantracy/Tailored_Task_Tracker/actions/workflows/ci.yml/badge.svg)](https://github.com/aidantracy/Tailored_Task_Tracker/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## Why it exists

Accounting teams close their books on the same schedule every month, and the deadlines are tied to business days rather than calendar dates: the fifth business day, the tenth, and so on. Most teams track this in a mix of spreadsheets and email, which makes it hard to see what is late or who owns what. LedgerLine puts the whole close on one board and keeps the dates correct on its own as the months roll over.

## What it does

- Lays the close out as ordered steps (Populate Financials, First Review, Second Review, Flash JE Upload, Final JE Upload), each anchored to the Nth business day of the month.
- Works out due dates from business-day math, skipping weekends and holidays, so a deadline never lands on a day nobody works.
- Rolls recurring tasks forward into the next month and recomputes their dates, keeping the linked series in sync.
- Tracks each task through four states (Not Started, In Progress, Stuck, Done) with assignees and per-task comment threads, including unread counts.
- Handles accounts end to end: invitation-key signup, login, password reset with a security question, an admin role, and the ability to promote other users.
- Keeps an audit log of every change and supports soft-delete with restore, so nothing is lost by accident.

## Tech stack

Backend is Python and Flask, using the application-factory pattern with blueprints, Flask-Login for sessions, Flask-Bcrypt for password hashing, SQLAlchemy for data access, and Pydantic to validate incoming requests. Data lives in MySQL 8.4 with a plain SQL schema and seed scripts. The frontend is server-rendered Jinja2 templates with vanilla JavaScript modules and Tailwind utility classes. Business-day and holiday math is handled by workalendar. Everything runs in containers through Docker or Podman Compose, with Gunicorn as the production server. Tests are written with pytest, QUnit, and Cypress, and CI on GitHub Actions also runs Ruff and mypy.

## Architecture

Routes stay thin and hand the real work to a services layer, where the due-date engine and user logic live. Requests are validated with Pydantic schemas before anything touches the database, and models handle persistence. Shared helpers for JSON responses and exceptions sit in `utils`. The whole app is assembled in a `create_app()` factory that picks its configuration from the environment, which is what makes it straightforward to test.

## Running it locally

You need Docker or Podman with Compose installed. Python and MySQL run inside the containers, so you do not have to install them yourself.

```bash
git clone https://github.com/aidantracy/Tailored_Task_Tracker.git
cd Tailored_Task_Tracker
cp .env.example .env          # on Windows: copy .env.example .env
podman compose up -d --build  # or: docker compose up -d --build
```

Open http://localhost:5000 and create an account. The database loads its schema and seed data on the first start, so the board comes up already populated with a sample close.

To stop and clear everything:

```bash
podman compose down -v
```

## Tests

```bash
pip install ".[dev]"
pytest                  # backend unit tests
npm install
npm test                # QUnit frontend tests
npm run cypress:run     # end-to-end tests (needs the stack running)
```

Linting and type checks run with Ruff and mypy. CI runs the backend and frontend tests on every push and pull request.

## Project layout

```
src/dashboard/
  __init__.py     application factory and configuration
  config.py       dev / test / prod configs
  routes/         blueprints: auth, dashboard, tasks, steps, comments, due_dates
  services/       due-date engine and user logic
  schemas/        Pydantic request validation
  models/         user, task, step
  utils/          shared responses and exceptions
  templates/      Jinja2 pages
  static/         JavaScript, CSS, images
db/init/          MySQL schema and seed data
tests/            backend (pytest), frontend (QUnit), e2e (Cypress)
docs/             schedule notes and database design
```

## Team

Built by Bakir Grbic, Aidan Tracy, and Alexander Daniluc.

## License

MIT. See [LICENSE](LICENSE).
