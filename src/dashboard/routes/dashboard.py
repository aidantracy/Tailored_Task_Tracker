# src/dashboard/routes/dashboard.py
from __future__ import annotations
import uuid
from functools import wraps
from datetime import datetime, date, timedelta

from flask import Blueprint, current_app, render_template, jsonify, request, redirect, url_for
from flask_login import login_required, current_user
from sqlalchemy import text
from sqlalchemy.exc import OperationalError, ProgrammingError
from dashboard import db
from ..models import InvitationKey, User
from ..utils.responses import make_success_response, make_error_response
from .due_dates import load_holidays_for_year

dashboard_bp = Blueprint(
    "dashboard_bp",
    __name__,
    template_folder="../templates",
    static_folder="../static",
)


def admin_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not current_user.is_authenticated or not current_user.is_admin:
            return make_error_response(code="FORBIDDEN", status_code=403, message="Admin access required.")
        return f(*args, **kwargs)
    return decorated_function


@dashboard_bp.get("/health/db")
def db_health():
    try:
        with db.engine.connect() as con:
            row = con.execute(text("SELECT 1 AS ok")).first()
            return (jsonify({"db": 1}), 200) if (row and row.ok == 1) else (jsonify({"db": 0}), 500)
    except Exception as e:
        current_app.logger.exception("DB health failed")
        return jsonify({"db": 0, "error": str(e)}), 500


def _bootstrap_recurring_from_tasks(con):
    """
    One-time bootstrap:

    - If Recurring_Task already has rows, do nothing.
    - Otherwise, find the EARLIEST dashboard (your seeded board),
      and create Recurring_Task patterns from its recurring tasks.

    This prevents:
      - Re-populating patterns from later months
      - Drift caused by using already-shifted due dates as a new pattern
    """
    # If we already have at least one recurring pattern, don't bootstrap again.
    has_any = con.execute(
        text("SELECT 1 AS x FROM Recurring_Task LIMIT 1")
    ).first()
    if has_any:
        return

    # Find the earliest dashboard (seed)
    seed = con.execute(
        text("""
            SELECT dashboard_id
            FROM Dashboard
            ORDER BY start_date ASC, dashboard_id ASC
            LIMIT 1
        """)
    ).first()
    if not seed:
        return

    seed_dash_id = int(seed.dashboard_id)

    # 1) Insert Recurring_Task rows ONLY from the seed dashboard's recurring tasks.
    con.execute(
        text("""
            INSERT INTO Recurring_Task (step_id, day_of_month, title, notes, is_active)
            SELECT
                t.step_id,
                DAY(t.due_date) AS day_of_month,
                t.title,
                t.notes,
                1
            FROM Task t
            JOIN Step s ON s.step_id = t.step_id
            LEFT JOIN Recurring_Task rt
              ON rt.step_id      = t.step_id
             AND rt.title        = t.title
             AND rt.day_of_month = DAY(t.due_date)
            WHERE s.dashboard_id      = :seed_dash_id
              AND t.is_recurring      = 1
              AND t.is_deleted        = 0
              AND t.due_date         IS NOT NULL
              AND t.recurring_task_id IS NULL
              AND rt.recurring_task_id IS NULL
        """),
        {"seed_dash_id": seed_dash_id},
    )

    # 2) Backfill Task.recurring_task_id for those seed tasks.
    con.execute(
        text("""
            UPDATE Task t
            JOIN Step s ON s.step_id = t.step_id
            JOIN Recurring_Task rt
              ON rt.step_id      = t.step_id
             AND rt.title        = t.title
             AND rt.day_of_month = DAY(t.due_date)
            SET t.recurring_task_id = rt.recurring_task_id
            WHERE s.dashboard_id      = :seed_dash_id
              AND t.is_recurring      = 1
              AND t.is_deleted        = 0
              AND t.due_date         IS NOT NULL
              AND t.recurring_task_id IS NULL
        """),
        {"seed_dash_id": seed_dash_id},
    )


def _get_active_dashboard_id(con):
    """Return dashboard_id for current month if it exists,
    otherwise fall back to the most recently created dashboard."""
    try:
        today = date.today()
        month_key = f"{today.year:04d}-{today.month:02d}"

        # Prefer a dashboard whose month_key matches the current month
        row = con.execute(text("""
            SELECT dashboard_id
              FROM Dashboard
             WHERE month_key = :mk
             LIMIT 1
        """), {"mk": month_key}).first()
        if row:
            return row.dashboard_id

        # Fallback: most recently created dashboard (highest id)
        row = con.execute(text("""
            SELECT dashboard_id
              FROM Dashboard
             ORDER BY dashboard_id DESC
             LIMIT 1
        """)).first()
        return row.dashboard_id if row else None
    except (OperationalError, ProgrammingError) as e:
        current_app.logger.warning("DB not ready in _get_active_dashboard_id: %s", e)
        return None


def _get_or_create_dashboard_for_month(con, month_key: str | None):
    """
    Lookup or create a Dashboard row for the given YYYY-MM month_key.

    - Validates month_key format.
    - Creates Dashboard(start_date, end_date) if missing.
    - Clones Step structure from a template dashboard.
    - Ensures recurring tasks for that month are present based on Recurring_Task
      (via _clone_template_tasks_to_dashboard, which is now idempotent).
    """

    if not month_key:
        # Fall back to whatever you treat as the "active" dashboard.
        return _get_active_dashboard_id(con)

    # Parse YYYY-MM
    try:
        year_str, month_str = month_key.split("-", 1)
        year = int(year_str)
        month = int(month_str)
        if month < 1 or month > 12:
            raise ValueError
    except Exception:
        current_app.logger.warning("Bad month_key %r, falling back to active", month_key)
        return _get_active_dashboard_id(con)

    # Ensure seed dashboard's recurring tasks are in Recurring_Task
    _bootstrap_recurring_from_tasks(con)

    # If it already exists, just ensure recurring tasks and return it.
    existing = con.execute(
        text("""
            SELECT dashboard_id, YEAR(start_date) AS y, MONTH(start_date) AS m
            FROM Dashboard
            WHERE month_key = :mk
            LIMIT 1
        """),
        {"mk": month_key},
    ).first()
    if existing:
        dash_id = int(existing.dashboard_id)
        board_year = int(existing.y or 0) or None
        board_month = int(existing.m or 0) or None
        if board_year and board_month:
            _clone_template_tasks_to_dashboard(
                con,
                template_dashboard_id=None,
                new_dashboard_id=dash_id,
                target_year=board_year,
                target_month=board_month,
            )
        return dash_id

    # Compute start and end dates for that calendar month.
    start_date = date(year, month, 1)
    if month == 12:
        next_month_year = year + 1
        next_month = 1
    else:
        next_month_year = year
        next_month = month + 1
    end_date = date(next_month_year, next_month, 1) - timedelta(days=1)

    # Pick a template dashboard to clone steps from:
    #  - Prefer the closest *earlier* month so new step changes propagate.
    #  - Fall back to the earliest dashboard if nothing earlier exists.
    template = con.execute(
        text("""
            SELECT dashboard_id
            FROM Dashboard
            WHERE start_date < :start_date
            ORDER BY start_date DESC, dashboard_id DESC
            LIMIT 1
        """),
        {"start_date": start_date},
    ).first()

    if not template:
        template = con.execute(
            text("""
                SELECT dashboard_id
                FROM Dashboard
                ORDER BY start_date ASC, dashboard_id ASC
                LIMIT 1
            """)
        ).first()

    # Insert the new Dashboard row
    con.execute(
        text("""
            INSERT INTO Dashboard (month_key, start_date, end_date)
            VALUES (:mk, :start_date, :end_date)
        """),
        {"mk": month_key, "start_date": start_date, "end_date": end_date},
    )

    row = con.execute(
        text("SELECT dashboard_id FROM Dashboard WHERE month_key = :mk"),
        {"mk": month_key},
    ).first()

    dash_id = int(row.dashboard_id) if row else None

    if template and dash_id:
        template_dash_id = int(template.dashboard_id)

        # 1) Clone Steps from the template dashboard
        con.execute(
            text("""
                INSERT INTO Step (dashboard_id, business_day_id, step_title)
                SELECT :new_dash_id, s.business_day_id, s.step_title
                FROM Step s
                WHERE s.dashboard_id = :src_dash_id
                ORDER BY s.step_id ASC
            """),
            {"new_dash_id": dash_id, "src_dash_id": template_dash_id},
        )

        # 2) Ensure recurring tasks for this new month (idempotent)
        _clone_template_tasks_to_dashboard(
            con,
            template_dashboard_id=template_dash_id,  # kept for signature; not used
            new_dashboard_id=dash_id,
            target_year=year,
            target_month=month,
        )

    return dash_id


def _business_day_index_for_date(d: date) -> int | None:
    """
    Given a date that is already on a business day, return its
    1-based 'nth business day of the month' (using the same weekend /
    holiday rules as /api/due-date).

    NOTE: kept for compatibility; not used in new cloning logic.
    """
    if d is None:
        return None

    holidays = load_holidays_for_year(d.year)
    current = date(d.year, d.month, 1)
    count = 0

    while current.month == d.month:
        # business day = weekday and not a holiday
        if current.weekday() < 5 and current not in holidays:
            count += 1
            if current == d:
                return count
        current += timedelta(days=1)

    return None


def _nth_business_day_of_month(year: int, month: int, nth: int) -> date | None:
    """
    Return the nth business day for (year, month), using the same
    holiday/weekend logic as /api/due-date. Returns None if nth is bad.

    NOTE: kept for compatibility; not used in new cloning logic.
    """
    if not nth or nth <= 0:
        return None

    holidays = load_holidays_for_year(year)
    current = date(year, month, 1)
    count = 0

    while current.month == month:
        if current.weekday() < 5 and current not in holidays:
            count += 1
            if count == nth:
                return current
        current += timedelta(days=1)

    return None


def _copy_due_date_to_new_month(src_due: date, target_year: int, target_month: int) -> date | None:
    """
    Copy the calendar day-of-month from src_due into (target_year, target_month),
    then push FORWARD to the next business day if that date falls on a weekend
    or custom holiday.

    Kept as a helper if you ever need it; the new cloning logic uses Recurring_Task.day_of_month.
    """
    if not src_due:
        return None

    # 1) Try to build the same calendar day-of-month in the target month.
    try:
        candidate = date(target_year, target_month, src_due.day)
    except ValueError:
        # If the month doesn't have that many days (e.g. 31 in Feb),
        # clamp to the last day of the month.
        if target_month == 12:
            next_year, next_month = target_year + 1, 1
        else:
            next_year, next_month = target_year, target_month + 1
        candidate = date(next_year, next_month, 1) - timedelta(days=1)

    # 2) Push forward to the next business day (Mon–Fri, not in extra holidays)
    while True:
        holidays = load_holidays_for_year(candidate.year)
        if candidate.weekday() < 5 and candidate not in holidays:
            return candidate
        candidate += timedelta(days=1)


def _clone_template_tasks_to_dashboard(
    con,
    template_dashboard_id: int | None,
    new_dashboard_id: int,
    target_year: int | None,
    target_month: int | None,
) -> None:
    """
    Ensure that ALL active Recurring_Task patterns have a Task instance
    on the given dashboard + (year, month).

    - Uses Recurring_Task.day_of_month as the anchor.
    - Maps the defining Step for each pattern onto the corresponding Step in the
      target dashboard.
    - Applies a month_offset for "next month" columns:
        * columns whose Business_Day.business_day is 1 or 4
          are treated as 'next month' buckets
    - Only inserts if there is no existing Task for that pattern in that
      *effective* year/month (board month + month_offset).
    - Only inserts for months >= the pattern's earliest Task.due_date.
    - Idempotent: safe to call multiple times for the same month/dashboard.
    """

    if not target_year or not target_month:
        return

    # Status row for "Not Started"
    status_row = con.execute(
        text("""
            SELECT status_id
            FROM Status
            WHERE LOWER(status) = 'not started'
            LIMIT 1
        """)
    ).first()
    if not status_row:
        current_app.logger.warning("No 'Not Started' status found; skipping recurring fill.")
        return
    not_started_status_id = int(status_row.status_id)

    # Load all active recurring patterns + the *source* step's metadata.
    pattern_rows = con.execute(
        text("""
            SELECT
                rt.recurring_task_id,
                rt.title,
                rt.day_of_month,
                rt.notes,
                s_src.business_day_id AS src_business_day_id,
                s_src.step_title      AS src_step_title
            FROM Recurring_Task rt
            JOIN Step s_src ON s_src.step_id = rt.step_id
            WHERE rt.is_active = 1
        """),
    ).mappings().all()

    if not pattern_rows:
        return

    # Figure out month_offset per business_day_id
    # Columns whose business_day is 1 or 4 are "next month" columns.
    bd_rows = con.execute(
        text("SELECT business_day_id, business_day FROM Business_Day")
    ).mappings().all()
    month_offset_by_bd: dict[int, int] = {}
    for bd in bd_rows:
        try:
            dom = int(bd["business_day"] or 0)
            bid = int(bd["business_day_id"])
        except (TypeError, ValueError):
            continue
        month_offset_by_bd[bid] = 1 if dom in (1, 4) else 0

    for row in pattern_rows:
        rtid = int(row["recurring_task_id"])
        dom = int(row["day_of_month"])
        title = row["title"]
        notes = row["notes"]
        src_bd = row["src_business_day_id"]
        src_step_title = (row["src_step_title"] or "").strip()

        # --- Resolve destination Step (column) on this dashboard ---
        dest_step_id = None

        # 1) Preferred: same business_day_id AND same title
        if src_bd is not None and src_step_title:
            step_row = con.execute(
                text("""
                    SELECT step_id
                    FROM Step
                    WHERE dashboard_id    = :dash_id
                      AND business_day_id = :bd
                      AND step_title      = :title
                    ORDER BY step_id ASC
                    LIMIT 1
                """),
                {"dash_id": new_dashboard_id, "bd": int(src_bd), "title": src_step_title},
            ).first()
            if step_row:
                dest_step_id = int(step_row.step_id)

        # 2) Fallback: same business_day_id (handles renamed columns)
        if dest_step_id is None and src_bd is not None:
            step_row = con.execute(
                text("""
                    SELECT step_id
                    FROM Step
                    WHERE dashboard_id    = :dash_id
                      AND business_day_id = :bd
                    ORDER BY step_id ASC
                    LIMIT 1
                """),
                {"dash_id": new_dashboard_id, "bd": int(src_bd)},
            ).first()
            if step_row:
                dest_step_id = int(step_row.step_id)

        # 3) Fallback: same title anywhere on this dashboard
        if dest_step_id is None and src_step_title:
            step_row = con.execute(
                text("""
                    SELECT step_id
                    FROM Step
                    WHERE dashboard_id = :dash_id
                      AND step_title   = :title
                    ORDER BY step_id ASC
                    LIMIT 1
                """),
                {"dash_id": new_dashboard_id, "title": src_step_title},
            ).first()
            if step_row:
                dest_step_id = int(step_row.step_id)

        # If we still can't map this pattern to a step, skip it
        if dest_step_id is None:
            continue

        # Column month offset (0 = board month, 1 = following month)
        month_offset = 0
        if src_bd is not None:
            try:
                month_offset = int(month_offset_by_bd.get(int(src_bd), 0))
            except (TypeError, ValueError):
                month_offset = 0

        # Effective year/month for THIS pattern on THIS board:
        #   - normal columns: the board month
        #   - "next month" columns: the following month
        eff_year, eff_month = target_year, target_month
        if month_offset:
            eff_month += month_offset
            while eff_month > 12:
                eff_month -= 12
                eff_year += 1

        # Determine earliest month this pattern should apply to:
        first_row = con.execute(
            text("""
                SELECT MIN(due_date) AS first_due
                FROM Task
                WHERE recurring_task_id = :rtid
                  AND is_deleted = 0
            """),
            {"rtid": rtid},
        ).first()
        first_due = getattr(first_row, "first_due", None)
        if not first_due:
            # No concrete tasks yet for this pattern; be safe and skip.
            continue

        # Don't back-fill boards whose effective month is before the
        # pattern's first effective month.
        if (eff_year, eff_month) < (first_due.year, first_due.month):
            continue

        # Check if any recurring task already exists for this pattern in this
        # effective month on this dashboard.
        existing_task = con.execute(
            text("""
                SELECT task_id, recurring_task_id, is_deleted
                FROM Task
                WHERE step_id        = :sid
                  AND is_recurring   = 1
                  AND title          = :title
                  AND due_date IS NOT NULL
                  AND YEAR(due_date) = :y
                  AND MONTH(due_date)= :m
                ORDER BY due_date ASC, task_id ASC
                LIMIT 1
            """),
            {"sid": dest_step_id, "title": title, "y": eff_year, "m": eff_month},
        ).first()

        if existing_task:
            # If it's a legacy non-deleted task with NULL recurring_task_id, attach it to this pattern.
            if (
                getattr(existing_task, "recurring_task_id", None) is None
                and not getattr(existing_task, "is_deleted", False)
            ):
                con.execute(
                    text("""
                        UPDATE Task
                        SET recurring_task_id = :rtid
                        WHERE task_id = :tid
                    """),
                    {"rtid": rtid, "tid": existing_task.task_id},
                )
            # Either way, there's already a task representing this pattern/month.
            continue

        # Compute candidate due date from day_of_month in the EFFECTIVE month
        try:
            candidate = date(eff_year, eff_month, dom)
        except ValueError:
            # Month doesn't have this many days (e.g., 31 in February) → clamp
            if eff_month == 12:
                ny, nm = eff_year + 1, 1
            else:
                ny, nm = eff_year, eff_month + 1
            candidate = date(ny, nm, 1) - timedelta(days=1)

        # Push forward to next business day (Mon–Fri and not holiday)
        holidays = load_holidays_for_year(candidate.year)
        while candidate.weekday() >= 5 or candidate in holidays:
            candidate += timedelta(days=1)
        new_due = candidate

        # For now, don't auto-assign a user; let the month stand alone.
        user_id = None

        # Current user (if any) for audit log
        try:
            uid = int(current_user.get_id()) if current_user.is_authenticated else None
        except Exception:
            uid = None

        # 1) Audit_Log entry for this generated task
        con.execute(
            text("""
                INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
                VALUES (NULL, :uid, NULL, 'generated from recurring pattern', 'Task', NULL)
            """),
            {"uid": uid},
        )
        al_id = con.execute(text("SELECT LAST_INSERT_ID()")).scalar_one()

        # 2) Timestamps row associated to that audit log
        con.execute(
            text("INSERT INTO Timestamps (audit_log_id) VALUES (:al_id)"),
            {"al_id": al_id},
        )
        ts_id = con.execute(text("SELECT LAST_INSERT_ID()")).scalar_one()

        # 3) Insert the new Task
        con.execute(
            text("""
                INSERT INTO Task (
                    due_date,
                    ts_id,
                    user_id,
                    step_id,
                    status_id,
                    title,
                    is_deleted,
                    is_recurring,
                    recurring_task_id,
                    notes
                )
                VALUES (:due_date, :ts_id, :user_id, :step_id, :status_id, :title, 0, 1, :rtid, :notes)
            """),
            {
                "due_date": new_due,
                "ts_id": ts_id,
                "user_id": user_id,
                "step_id": dest_step_id,
                "status_id": not_started_status_id,
                "title": title,
                "rtid": rtid,
                "notes": notes,
            },
        )
        new_task_id = con.execute(text("SELECT LAST_INSERT_ID()")).scalar_one()

        # 4) Backfill the Audit_Log with this task_id
        con.execute(
            text("UPDATE Audit_Log SET task_id=:tid, table_id=:tid WHERE audit_log_id=:al_id"),
            {"tid": new_task_id, "al_id": al_id},
        )





def _load_steps(con, dash_id: int):
    """Load steps with target calendar day…"""
    try:
        rows = con.execute(text("""
            SELECT
                s.step_id,
                s.step_title,
                bd.business_day AS target_dom
            FROM Step s
            JOIN Business_Day bd ON bd.business_day_id = s.business_day_id
            WHERE s.dashboard_id = :d
            ORDER BY
                CASE WHEN bd.business_day IN (1,4) THEN 1 ELSE 0 END,
                bd.business_day
        """), {"d": dash_id}).mappings().all()

        steps = []
        for r in rows:
            dom = int(r["target_dom"] or 0)
            month_offset = 1 if dom in (1, 4) else 0
            steps.append({
                "step_id": r["step_id"],
                "title": r["step_title"],
                "day_of_month": dom,
                "month_offset": month_offset,
            })
        return steps
    except (OperationalError, ProgrammingError) as e:
        current_app.logger.warning("DB not ready in _load_steps: %s", e)
        return []


def _load_month_options(con):
    """
    Return a list of {key, label} for each Dashboard month.
    key  = 'YYYY-MM'
    label = 'Nov 2025', etc.
    """
    try:
        rows = con.execute(text("""
            SELECT
                dashboard_id,
                COALESCE(month_key, DATE_FORMAT(start_date, '%Y-%m')) AS month_key,
                start_date
            FROM Dashboard
            ORDER BY start_date ASC, dashboard_id ASC
        """)).mappings().all()
        options = []
        for r in rows:
            key = r["month_key"]
            start_date = r.get("start_date")
            label = None
            if start_date:
                try:
                    label = start_date.strftime("%b %Y")
                except Exception:
                    label = None
            if not label and key:
                try:
                    dt = datetime.strptime(key, "%Y-%m")
                    label = dt.strftime("%b %Y")
                except Exception:
                    label = key
            if not label:
                label = "Unknown"
            options.append({"key": key, "label": label})
        return options
    except Exception as e:
        current_app.logger.warning("Failed to load month options: %s", e)
        return []


@dashboard_bp.get("/admin")
@login_required
@admin_required
def admin():
    try: 
        return render_template("admin.html", hide_month_picker=True)
    except Exception:
        return redirect(url_for("dashboard_bp.index"))

@dashboard_bp.get("/settings")
@login_required
def settings():
    return render_template("settings.html", hide_month_picker=True)

@dashboard_bp.post("/api/admin/invitation-keys")
@login_required
@admin_required
def create_invitation_key():
    try:
        new_key_value = str(uuid.uuid4())
        new_key = InvitationKey(
            key_value=new_key_value,
            created_by_user_id=current_user.user_id
        )
        db.session.add(new_key)
        db.session.commit()

        return make_success_response(
            data={"key_value": new_key_value},
            status_code=201
        )
    except Exception as e:
        current_app.logger.error(f"Error creating key: {e}", exc_info=True)
        db.session.rollback()
        return make_error_response(code="SERVER_ERROR", status_code=500, message="Could not create key.")


@dashboard_bp.get("/api/admin/invitation-keys")
@login_required
@admin_required
def get_invitation_keys():
    """
    Fetches ONLY unused, available invitation keys.
    """
    try:
        # Query only for keys that are not used
        keys = db.session.query(InvitationKey).filter(
            InvitationKey.is_used == 0
        ).order_by(InvitationKey.created_at.desc()).all()

        key_list = []
        for key in keys:
            key_list.append({
                "key_value": key.key_value,
                "created_at": key.created_at.isoformat(),
            })
        return make_success_response(data=key_list, status_code=200)

    except Exception as e:
        current_app.logger.error(f"Error fetching available keys: {e}", exc_info=True)
        return make_error_response(code="SERVER_ERROR", status_code=500, message="Could not fetch keys.")


@dashboard_bp.get("/")
def index():
    try:
        requested_month = request.args.get("month", type=str)

        # Use a transaction so inserts are committed automatically
        with db.engine.begin() as con:
            # One-time bootstrap from the seeded board
            # In test environments (SQLite) the Dashboard / Recurring_Task tables
            # may not exist; if so, just skip this bootstrap instead of 500-ing.
            try:
                _bootstrap_recurring_from_tasks(con)
            except (OperationalError, ProgrammingError) as e:
                current_app.logger.warning(
                    "Skipping _bootstrap_recurring_from_tasks; schema not ready: %s", e
                )

            if requested_month:
                dash_id = _get_or_create_dashboard_for_month(con, requested_month)
            else:
                dash_id = _get_active_dashboard_id(con)

            if not dash_id:
                return render_template(
                    "dashboard.html",
                    dashboard_id=0,
                    steps=[],
                    empty_message="No dashboard found. Seed your DB.",
                    board_year=None,
                    board_month=None,
                    month_key=None,
                    current_month_key=None,
                ), 200

            steps = _load_steps(con, dash_id)

            # Pull month metadata for this dashboard
            meta = con.execute(
                text(
                    """
                    SELECT
                        month_key,
                        YEAR(start_date)  AS start_year,
                        MONTH(start_date) AS start_month
                    FROM Dashboard
                    WHERE dashboard_id = :d
                    LIMIT 1
                    """
                ),
                {"d": dash_id},
            ).mappings().first()

            if meta:
                month_key = meta["month_key"]
                board_year = int(meta["start_year"] or 0) or None
                board_month = int(meta["start_month"] or 0) or None

                # Ensure recurring tasks for this dashboard/month as well
                if board_year and board_month:
                    _clone_template_tasks_to_dashboard(
                        con,
                        template_dashboard_id=None,
                        new_dashboard_id=dash_id,
                        target_year=board_year,
                        target_month=board_month,
                    )
            else:
                month_key = requested_month
                board_year = None
                board_month = None

        return render_template(
            "dashboard.html",
            dashboard_id=dash_id,
            steps=steps,
            empty_message=None,
            board_year=board_year,
            board_month=board_month,
            month_key=month_key,
            current_month_key=month_key,
        ), 200
    except Exception as e:
        current_app.logger.error("Error rendering dashboard: %s", e, exc_info=True)
        return "An error occurred while loading the page. Flask ↔ MySQL wired. Try /health/db.", 500



def _db_has_column(table_name: str, column_name: str) -> bool:
    """
    Returns True if `column_name` exists on `table_name` in the current MySQL database.
    Safe to call even before migrations have been applied.
    """
    try:
        row = db.session.execute(text("""
            SELECT COUNT(*) AS cnt
            FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = :t
              AND COLUMN_NAME = :c
        """), {"t": table_name, "c": column_name}).first()
        return bool(row and getattr(row, "cnt", 0) > 0)
    except Exception as e:
        current_app.logger.warning("Column check failed for %s.%s: %s", table_name, column_name, e)
        return False


@dashboard_bp.get("/api/board")
@login_required
def api_board():
    # Optional dashboard_id from query string
    requested_id = request.args.get("dashboard_id", type=int)

    if requested_id:
        dash_row = db.session.execute(
            text("SELECT dashboard_id FROM Dashboard WHERE dashboard_id = :did"),
            {"did": requested_id},
        ).first()
    else:
        # Fallback: first dashboard if none specified
        dash_row = db.session.execute(
            text("SELECT dashboard_id FROM Dashboard ORDER BY dashboard_id ASC LIMIT 1")
        ).first()

    dashboard_id = int(dash_row.dashboard_id) if dash_row else None

    # Figure out this dashboard's business-day window:
    # 5th business day of the board month → 4th business day of the next month
    window_start = None
    window_end = None

    if dashboard_id is not None:
        meta = db.session.execute(
            text("""
                SELECT start_date, end_date
                FROM Dashboard
                WHERE dashboard_id = :did
                LIMIT 1
            """),
            {"did": dashboard_id},
        ).mappings().first()

        if meta and meta["start_date"]:
            start = meta["start_date"]  # a date object
            year = start.year
            month = start.month

            # 5th business day of the *board* month
            window_start = _nth_business_day_of_month(year, month, 5)

            # 4th business day of the *next* month
            if month == 12:
                next_year, next_month = year + 1, 1
            else:
                next_year, next_month = year, month + 1

            # If you want 4th business day, use 4; if you decide you really want 5th, change this to 5.
            window_end = _nth_business_day_of_month(next_year, next_month, 4)


    # Only use step_title (per your schema)
    steps = db.session.execute(text("""
        SELECT step_id,
               COALESCE(step_title, CONCAT('Step ', step_id)) AS step_title
        FROM Step
        WHERE (:did IS NULL OR dashboard_id = :did)
        ORDER BY step_id ASC
    """), {"did": dashboard_id}).mappings().all()

    # Backward-compat: only select t.notes / t.is_recurring if the columns exist
    has_notes_col = _db_has_column("Task", "notes")
    has_recurring_col = _db_has_column("Task", "is_recurring")

    task_cols = """
        t.task_id,
        t.title,
        t.due_date,
        {notes_expr} AS notes,
        {recurring_expr} AS is_recurring,
        st.status AS status_label,
        u.first_name, u.last_name
    """.format(
        notes_expr=("t.notes" if has_notes_col else "NULL"),
        recurring_expr=("t.is_recurring" if has_recurring_col else "1")
    )

    # Extra WHERE clause:
    # Keep tasks whose due_date is within the board's business-day window:
    #   5th business day of board month → 4th business day of next month.
    # Tasks with NULL due_date are always included.
    extra_filter = """
        AND (
            (:win_start IS NULL OR t.due_date IS NULL OR t.due_date >= :win_start)
            AND (:win_end   IS NULL OR t.due_date IS NULL OR t.due_date <= :win_end)
        )
    """



    out_steps = []
    for s in steps:
        rows = db.session.execute(
            text(f"""
                SELECT {task_cols}
                FROM Task t
                JOIN Status st ON st.status_id = t.status_id
                LEFT JOIN Users u ON u.user_id = t.user_id
                WHERE t.step_id = :sid
                  AND t.is_deleted = 0
                  {extra_filter}
                ORDER BY t.task_id ASC
            """),
            {
                "sid": s["step_id"],
                "win_start": window_start,
                "win_end": window_end,
            },
        ).mappings().all()


        out_steps.append({
            "step_title": s["step_title"] or "",
            "tasks": [{
                "task_id": r["task_id"],
                "title": r["title"],
                "due_date": r["due_date"].isoformat() if r["due_date"] else "",
                "status": r["status_label"] or "Not Started",
                "notes": r["notes"] or "",
                "is_recurring": bool(r["is_recurring"]) if "is_recurring" in r else True,
                "assignee": (
                    {"name": f'{r["first_name"]} {r["last_name"]}'.strip()}
                    if (r["first_name"] or r["last_name"]) else None
                ),
                # (duplicate key in your original — kept as-is for compatibility)
                "is_recurring": bool(r.get("is_recurring", True)),
            } for r in rows]
        })

    return jsonify({"dashboard_id": dashboard_id, "steps": out_steps})


@dashboard_bp.get("/api/admin/users/candidates")
@login_required
@admin_required
def get_admin_candidates():
    """
    Fetches users who are not currently admins and not deleted.
    """
    try:
        # Filter: Not admin, not deleted, order by name
        candidates = db.session.query(User).filter(
            User.is_admin == 0,
            User.is_deleted == 0
        ).order_by(User.last_name.asc(), User.first_name.asc()).all()

        user_list = []
        for user in candidates:
            user_list.append({
                "user_id": user.user_id,
                "full_name": f"{user.first_name} {user.last_name}",
                "email": user.email
            })

        return make_success_response(data=user_list, status_code=200)

    except Exception as e:
        current_app.logger.error(f"Error fetching candidates: {e}", exc_info=True)
        return make_error_response(code="SERVER_ERROR", status_code=500, message="Could not fetch users.")


@dashboard_bp.post("/api/admin/users/promote/<int:user_id>")
@login_required
@admin_required
def promote_user(user_id):
    """
    Promotes a specific user to admin.
    """
    try:
        user = db.session.query(User).filter_by(user_id=user_id).first()

        if not user:
            return make_error_response(code="NOT_FOUND", status_code=404, message="User not found.")

        if user.is_admin:
            return make_error_response(code="BAD_REQUEST", status_code=400, message="User is already an admin.")

        # Update status
        user.is_admin = 1
        db.session.commit()

        current_app.logger.info(f"User {current_user.email} promoted {user.email} to admin.")

        return make_success_response(
            data={"message": f"{user.first_name} is now an admin."},
            status_code=200
        )

    except Exception as e:
        current_app.logger.error(f"Error promoting user: {e}", exc_info=True)
        db.session.rollback()
        return make_error_response(code="SERVER_ERROR", status_code=500, message="Could not promote user.")


@dashboard_bp.get("/api/admin/users/admins")
@login_required
@admin_required
def get_current_admins():
    """
    Fetches users who are currently admins (excluding the current user).
    """
    try:
        # Fetch admins, excluding the user making the request (to prevent self-demotion)
        admins = db.session.query(User).filter(
            User.is_admin == 1,
            User.is_deleted == 0,
            User.user_id != current_user.user_id
        ).order_by(User.last_name.asc(), User.first_name.asc()).all()

        user_list = []
        for user in admins:
            user_list.append({
                "user_id": user.user_id,
                "full_name": f"{user.first_name} {user.last_name}",
                "email": user.email
            })

        return make_success_response(data=user_list, status_code=200)

    except Exception as e:
        current_app.logger.error(f"Error fetching admins: {e}", exc_info=True)
        return make_error_response(code="SERVER_ERROR", status_code=500, message="Could not fetch admins.")


@dashboard_bp.post("/api/admin/users/revoke/<int:user_id>")
@login_required
@admin_required
def revoke_admin(user_id):
    """
    Revokes admin privileges from a user.
    """
    try:
        if user_id == current_user.user_id:
            return make_error_response(code="FORBIDDEN", status_code=403, message="You cannot revoke your own admin status.")

        user = db.session.query(User).filter_by(user_id=user_id).first()

        if not user:
            return make_error_response(code="NOT_FOUND", status_code=404, message="User not found.")

        if not user.is_admin:
            return make_error_response(code="BAD_REQUEST", status_code=400, message="User is not an admin.")

        # Update status
        user.is_admin = 0
        db.session.commit()

        current_app.logger.info(f"User {current_user.email} revoked admin status from {user.email}.")

        return make_success_response(
            data={"message": f"{user.first_name} is no longer an admin."},
            status_code=200
        )

    except Exception as e:
        current_app.logger.error(f"Error revoking admin: {e}", exc_info=True)
        db.session.rollback()
        return make_error_response(code="SERVER_ERROR", status_code=500, message="Could not revoke admin status.")


@dashboard_bp.get("/api/admin/users/active")
@login_required
@admin_required
def get_active_users():
    """
    Fetches all active (non-deleted) users, excluding the current admin.
    """
    try:
        # Fetch all non-deleted users, except the current user
        users = db.session.query(User).filter(
            User.is_deleted == 0,
            User.user_id != current_user.user_id
        ).order_by(User.last_name.asc(), User.first_name.asc()).all()

        user_list = []
        for user in users:
            role = "Admin" if user.is_admin else "User"
            user_list.append({
                "user_id": user.user_id,
                "full_name": f"{user.first_name} {user.last_name}",
                "email": user.email,
                "role": role
            })

        return make_success_response(data=user_list, status_code=200)

    except Exception as e:
        current_app.logger.error(f"Error fetching users: {e}", exc_info=True)
        return make_error_response(code="SERVER_ERROR", status_code=500, message="Could not fetch users.")


@dashboard_bp.post("/api/admin/users/delete/<int:user_id>")
@login_required
@admin_required
def delete_user(user_id):
    """
    Soft deletes a user.
    """
    try:
        if user_id == current_user.user_id:
            return make_error_response(code="FORBIDDEN", status_code=403, message="You cannot delete yourself.")

        user = db.session.query(User).filter_by(user_id=user_id).first()

        if not user:
            return make_error_response(code="NOT_FOUND", status_code=404, message="User not found.")

        if user.is_deleted:
            return make_error_response(code="BAD_REQUEST", status_code=400, message="User is already deleted.")

        # Soft delete
        user.is_deleted = 1
        db.session.commit()

        current_app.logger.info(f"User {current_user.email} deleted user {user.email}.")

        return make_success_response(
            data={"message": f"User {user.first_name} has been deleted."},
            status_code=200
        )

    except Exception as e:
        current_app.logger.error(f"Error deleting user: {e}", exc_info=True)
        db.session.rollback()
        return make_error_response(code="SERVER_ERROR", status_code=500, message="Could not delete user.")
