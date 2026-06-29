from __future__ import annotations
from datetime import date, timedelta

from flask import Blueprint, jsonify, request
from flask_login import login_required, current_user
from sqlalchemy import func, text

from dashboard import db
from dashboard.models.task import Task, Status, RecurringTask

from .due_dates import load_holidays_for_year
from .dashboard import (
    _get_or_create_dashboard_for_month,
    _nth_business_day_of_month,   # NEW: use same business-day logic as /api/board
)


tasks_bp = Blueprint("tasks_bp", __name__, url_prefix="/api/tasks")


# ---------------- Helpers ----------------

def _copy_due_date_to_new_month(src_due: date | None, target_year: int, target_month: int) -> date | None:
    """
    Copy calendar day-of-month from src_due into (target_year, target_month),
    then push forward to the next business day (Mon–Fri, not in holidays).
    """
    if not src_due:
        return None

    # 1) Try same day-of-month
    try:
        candidate = date(target_year, target_month, src_due.day)
    except ValueError:
        # clamp to last day of month
        if target_month == 12:
            next_year, next_month = target_year + 1, 1
        else:
            next_year, next_month = target_year, target_month + 1
        candidate = date(next_year, next_month, 1) - timedelta(days=1)

    # 2) Push forward to next business day
    while True:
        holidays = load_holidays_for_year(candidate.year)
        if candidate.weekday() < 5 and candidate not in holidays:
            return candidate
        candidate += timedelta(days=1)


def _month_key_for_due_date(d: date) -> str:
    """
    Map a due_date to the correct dashboard month using your rule:

      Board M covers dates from:
        5th business day of month M
        → 4th business day of month M+1 (inclusive)

    So:
      - If the date is on/after the 5th business day of its calendar month,
        it belongs to that month.
      - If it's before that, it belongs to the *previous* board month.
    """
    year = d.year
    month = d.month

    # 5th business day of this calendar month
    bd5 = _nth_business_day_of_month(year, month, 5)

    if bd5 and d >= bd5:
        # Lives on this month’s board
        target_year, target_month = year, month
    else:
        # Early-month date (before 5th BD) → previous board month
        if month == 1:
            target_year, target_month = year - 1, 12
        else:
            target_year, target_month = year, month - 1

    return f"{target_year:04d}-{target_month:02d}"


def _update_recurring_flag_series(task_id: int, new_flag: bool) -> None:
    """
    Flip is_recurring for the whole series (all dashboards) and keep
    Recurring_Task.is_active in sync.

    Series grouping heuristic:
      - same task title
      - same step title (column name)
    """
    # 1) Find series key + context
    row = db.session.execute(
        text("""
            SELECT t.title, s.step_title
            FROM Task t
            JOIN Step s ON s.step_id = t.step_id
            WHERE t.task_id = :task_id
        """),
        {"task_id": task_id},
    ).mappings().first()

    if not row:
        return

    title = row["title"]
    step_title = row["step_title"]

    # 2) Flip is_recurring for *all* matching tasks in that series
    db.session.execute(
        text("""
            UPDATE Task t
            JOIN Step s ON s.step_id = t.step_id
               SET t.is_recurring = :flag
             WHERE t.is_deleted = 0
               AND t.title = :title
               AND s.step_title = :step_title
        """),
        {
            "flag": int(bool(new_flag)),
            "title": title,
            "step_title": step_title,
        },
    )

    # 3) Also flip Recurring_Task.is_active for patterns that match this series
    db.session.execute(
        text("""
            UPDATE Recurring_Task rt
            JOIN Step s ON s.step_id = rt.step_id
               SET rt.is_active = :flag
             WHERE rt.title = :title
               AND s.step_title = :step_title
        """),
        {
            "flag": int(bool(new_flag)),
            "title": title,
            "step_title": step_title,
        },
    )


def _sync_future_dashboards_for_series(task_id: int, new_flag: bool) -> None:
    """
    Keep the series in sync across *future* dashboards.

    - If new_flag is False (recurring turned OFF):
        soft-delete (is_deleted = 1) all future instances in that series.
    - If new_flag is True (recurring turned ON or created):
        do NOT fan out tasks here; recurring instances are generated
        centrally by `_clone_template_tasks_to_dashboard` in dashboard.py
        based on Recurring_Task patterns.
    """
    # Find base task context (which dashboard/month this card "belongs" to)
    base = db.session.execute(
        text("""
            SELECT
                t.task_id,
                t.title,
                t.due_date,
                t.user_id,
                t.notes,
                s.step_id,
                s.step_title,
                s.business_day_id,
                d.dashboard_id,
                d.start_date
            FROM Task t
            JOIN Step s   ON s.step_id = t.step_id
            JOIN Dashboard d ON d.dashboard_id = s.dashboard_id
            WHERE t.task_id = :tid
        """),
        {"tid": task_id},
    ).mappings().first()

    if not base:
        return

    base_title = base["title"]
    base_step_title = base["step_title"]
    base_start_date = base["start_date"]

    # All dashboards strictly "after" this one's start_date
    future_dashboards = db.session.execute(
        text("""
            SELECT dashboard_id, start_date
            FROM Dashboard
            WHERE start_date > :base_start
            ORDER BY start_date ASC, dashboard_id ASC
        """),
        {"base_start": base_start_date},
    ).mappings().all()

    if not future_dashboards:
        return

    if not new_flag:
        # Turned OFF: soft delete future instances of this series, leave current/past intact
        db.session.execute(
            text("""
                UPDATE Task t
                JOIN Step s ON s.step_id = t.step_id
                JOIN Dashboard d ON d.dashboard_id = s.dashboard_id
                   SET t.is_deleted = 1
                 WHERE t.is_deleted = 0
                   AND t.title = :title
                   AND s.step_title = :step_title
                   AND d.start_date > :base_start
            """),
            {
                "title": base_title,
                "step_title": base_step_title,
                "base_start": base_start_date,
            },
        )
        return

    # new_flag=True → do nothing here.
    # Future instances will be created by the recurring pattern engine
    # in dashboard.py when those dashboards are loaded.
    return


def _resolve_status(label: str | None):
    lbl = (label or "Not Started").strip()
    s = Status.query.filter(func.lower(Status.status) == lbl.lower()).first()
    if not s:
        s = Status.query.filter(func.lower(Status.status) == func.lower("Not Started")).first()
    return s


def _resolve_step_id(
    step_title: str | None,
    dashboard_id: int | None = None,
    business_day_hint: int | None = None,
) -> int | None:
    """
    Find Step for this dashboard + title (optionally by business day),
    with backwards-compatible fallbacks.
    """

    # Prefer a match *within the current dashboard*
    if dashboard_id is not None:
        # 1) Exact title match in this dashboard
        if step_title and step_title.strip():
            row = db.session.execute(
                text("""
                    SELECT s.step_id
                    FROM Step s
                    WHERE s.dashboard_id = :dash_id
                      AND LOWER(COALESCE(s.step_title,'')) = LOWER(:t)
                    ORDER BY s.step_id ASC
                    LIMIT 1
                """),
                {"dash_id": dashboard_id, "t": step_title.strip()},
            ).first()
            if row:
                return int(row.step_id)

        # 2) Optionally: match by business day in this dashboard
        if business_day_hint is not None:
            row = db.session.execute(
                text("""
                    SELECT s.step_id
                    FROM Step s
                    JOIN Business_Day bd ON bd.business_day_id = s.business_day_id
                    WHERE s.dashboard_id = :dash_id
                      AND bd.business_day = :bd
                    ORDER BY s.step_id ASC
                    LIMIT 1
                """),
                {"dash_id": dashboard_id, "bd": int(business_day_hint)},
            ).first()
            if row:
                return int(row.step_id)

        # 3) Fallback: any step in this dashboard
        row = db.session.execute(
            text("""
                SELECT step_id
                FROM Step
                WHERE dashboard_id = :dash_id
                ORDER BY step_id ASC
                LIMIT 1
            """),
            {"dash_id": dashboard_id},
        ).first()
        if row:
            return int(row.step_id)

    # ---------------------------
    # Backwards-compatible fallback
    # ---------------------------
    if step_title and step_title.strip():
        row = db.session.execute(
            text("""
                SELECT step_id
                FROM Step
                WHERE LOWER(COALESCE(step_title,'')) = LOWER(:t)
                ORDER BY step_id ASC
                LIMIT 1
            """),
            {"t": step_title.strip()},
        ).first()
        if row:
            return int(row.step_id)

    row = db.session.execute(
        text("SELECT step_id FROM Step ORDER BY step_id ASC LIMIT 1")
    ).first()
    return int(row.step_id) if row else None


def _iso_or_none(d):
    return d.isoformat() if d else None


def _parse_bool(value, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    s = str(value).strip().lower()
    if s in ("0", "false", "no", "off"):
        return False
    if s in ("1", "true", "yes", "on"):
        return True
    return default


# ---------------- CREATE ----------------
@tasks_bp.post("")
@tasks_bp.post("/")
@login_required
def create_task():
    data = request.get_json(silent=True) or {}

    title = (data.get("title") or "").strip()
    if not title:
        return jsonify({"success": False, "error": {"code": "BAD_TITLE", "message": "title is required"}}), 400

    s = _resolve_status(data.get("status_label"))
    if not s:
        return jsonify({
            "success": False,
            "error": {"code": "NO_STATUS", "message": "Status not configured"},
        }), 500

    # Dashboard + business-day from the UI context (the board you were on)
    raw_dash_id = data.get("dashboard_id")
    try:
        original_dashboard_id = int(raw_dash_id) if raw_dash_id is not None else None
    except (TypeError, ValueError):
        original_dashboard_id = None

    raw_biz = data.get("business_day_hint")
    try:
        business_day_hint = int(raw_biz) if raw_biz is not None else None
    except (TypeError, ValueError):
        business_day_hint = None

    # Parse due_date first so we can decide which dashboard this task truly belongs to
    dd = data.get("due_date")
    try:
        due_date = date.fromisoformat(dd) if dd else None
    except ValueError:
        return jsonify({"success": False, "error": {"code": "BAD_DATE", "message": "Use YYYY-MM-DD"}}), 400

    effective_dashboard_id = original_dashboard_id
    if due_date is not None:
        # Use the same 5th-BD → 4th-BD rule the board uses
        month_key = _month_key_for_due_date(due_date)
        with db.engine.begin() as con:
            dash_id_for_due = _get_or_create_dashboard_for_month(con, month_key)
        if dash_id_for_due:
            effective_dashboard_id = dash_id_for_due

    # Resolve the Step within the *effective* dashboard (not necessarily the current view)
    step_id = _resolve_step_id(
        data.get("step_title"),
        dashboard_id=effective_dashboard_id,
        business_day_hint=business_day_hint,
    )
    if not step_id:
        return jsonify({
            "success": False,
            "error": {"code": "NO_STEPS", "message": "No steps configured"},
        }), 500

    # is_recurring: default True if omitted
    is_recurring = bool(data.get("is_recurring", True))

    # ----- Audit_Log -> Timestamps -> Task -----
    try:
        uid = int(current_user.get_id()) if current_user.is_authenticated else None
    except Exception:
        uid = None

    # 1) Audit_Log (no task_id yet)
    db.session.execute(
        text("""
            INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
            VALUES (NULL, :uid, NULL, 'created task', 'Task', NULL)
        """),
        {"uid": uid}
    )
    al_id = db.session.execute(text("SELECT LAST_INSERT_ID()")).scalar_one()

    # 2) Timestamps
    db.session.execute(
        text("INSERT INTO Timestamps (audit_log_id) VALUES (:al_id)"),
        {"al_id": al_id}
    )
    ts_id = db.session.execute(text("SELECT LAST_INSERT_ID()")).scalar_one()

    # 3) Task
    t = Task(
        title=title,
        status_id=s.status_id,
        step_id=step_id,
        due_date=due_date,
        user_id=None,
        ts_id=ts_id,
        is_deleted=False,
        is_recurring=is_recurring,
    )
    db.session.add(t)
    db.session.flush()  # get t.task_id

    # 4) Backfill Audit_Log with task_id
    db.session.execute(
        text("UPDATE Audit_Log SET task_id=:tid, table_id=:tid WHERE audit_log_id=:al_id"),
        {"tid": t.task_id, "al_id": al_id}
    )

    # 5) Persist notes if provided (and reuse them for Recurring_Task)
    notes_val = (data.get("notes") or data.get("note") or "").strip()
    if notes_val != "":
        db.session.execute(
            text("UPDATE Task SET notes = :n WHERE task_id = :tid"),
            {"n": notes_val, "tid": t.task_id}
        )

    # 6) If this task is recurring, create or reuse a Recurring_Task row and link it
    if is_recurring:
        if due_date is not None:
            day_of_month = due_date.day
        else:
            day_of_month = business_day_hint or 1

        rt = RecurringTask.query.filter_by(
            step_id=step_id,
            day_of_month=day_of_month,
            title=title,
        ).first()

        if not rt:
            rt = RecurringTask(
                step_id=step_id,
                day_of_month=day_of_month,
                title=title,
                notes=notes_val or None,
                is_active=True,
            )
            db.session.add(rt)
            db.session.flush()
        else:
            # ensure it's active and optionally refresh notes
            rt.is_active = True
            if notes_val:
                rt.notes = notes_val

        t.recurring_task_id = rt.recurring_task_id

        # NOTE: We no longer fan out instances here; future recurring
        # instances are generated by _clone_template_tasks_to_dashboard
        # when those dashboards are loaded.
        _sync_future_dashboards_for_series(t.task_id, True)

    db.session.commit()

    assignee_name = (data.get("assignee_name") or "").strip() or None
    task_month_key = f"{t.due_date.year:04d}-{t.due_date.month:02d}" if t.due_date else None

    return jsonify({
        "task": {
            "task_id": t.task_id,
            "title": t.title,
            "assignee": {"name": assignee_name} if assignee_name else None,
            "due_date": t.due_date.isoformat() if t.due_date else "",
            "is_recurring": bool(getattr(t, "is_recurring", True)),
            # NEW: tell the frontend where this task actually lives
            "dashboard_id": effective_dashboard_id,
            "month_key": task_month_key,
        }
    }), 201


# ---------------- UPDATE ----------------
@tasks_bp.patch("/<int:task_id>")
@login_required
def update_task(task_id: int):
    t = Task.query.get(task_id)
    if not t:
        return jsonify({"success": False, "error": {"code": "NOT_FOUND", "message": "Task not found"}}), 404
    if getattr(t, "is_deleted", False):
        return jsonify({"success": False, "error": {"code": "GONE", "message": "Task has been deleted"}}), 410

    data = request.get_json(silent=True) or {}

    # Track what changed so we can sync Recurring_Task
    title_changed = False
    notes_changed = False
    notes_val_for_rec = None

    status_label = data.get("status") or data.get("status_label")
    if "status_id" in data:
        t.status_id = int(data["status_id"])
    elif status_label:
        s = _resolve_status(status_label)
        if not s:
            return jsonify({"success": False, "error": {"code": "BAD_STATUS", "message": f"Unknown status: {status_label}"}}), 400
        t.status_id = s.status_id

    if "title" in data and data["title"] is not None:
        new_title = str(data["title"]).strip()[:255]
        if new_title and new_title != t.title:
            t.title = new_title
            title_changed = True

    if "due_date" in data:
        dd = data["due_date"]
        if dd:
            try:
                new_due = date.fromisoformat(dd)
            except ValueError:
                return jsonify({
                    "success": False,
                    "error": {"code": "BAD_DATE", "message": "Use YYYY-MM-DD"},
                }), 400

            t.due_date = new_due

            # If this is a *one-time* task, move it to the dashboard whose
            # business-day window owns this date.
            if not bool(getattr(t, "is_recurring", False)):
                # 1) Decide which board month this date belongs to
                month_key = _month_key_for_due_date(new_due)

                # 2) Ensure that dashboard exists (or create it)
                with db.engine.begin() as con:
                    new_dash_id = _get_or_create_dashboard_for_month(con, month_key)

                if new_dash_id:
                    # 3) Get this task's current column title
                    base = db.session.execute(
                        text("""
                            SELECT s.step_title
                            FROM Step s
                            WHERE s.step_id = :sid
                            LIMIT 1
                        """),
                        {"sid": t.step_id},
                    ).mappings().first()

                    step_title = (base["step_title"] or "").strip() if base else ""

                    if step_title:
                        # 4) Find matching step on the target dashboard
                        step_row = db.session.execute(
                            text("""
                                SELECT s.step_id
                                FROM Step s
                                WHERE s.dashboard_id = :did
                                  AND s.step_title   = :title
                                ORDER BY s.step_id ASC
                                LIMIT 1
                            """),
                            {"did": new_dash_id, "title": step_title},
                        ).first()

                        if step_row:
                            t.step_id = int(step_row.step_id)
        else:
            # Clearing the date
            t.due_date = None

    # Handle recurring flag + propagate to series and future dashboards
    if "is_recurring" in data:
        new_flag = bool(data.get("is_recurring"))
        _update_recurring_flag_series(task_id, new_flag)
        _sync_future_dashboards_for_series(task_id, new_flag)

    if "step_title" in data and data["step_title"]:
        raw_dash = data.get("dashboard_id")
        try:
            dash_id = int(raw_dash) if raw_dash is not None else None
        except (TypeError, ValueError):
            dash_id = None

        raw_biz = data.get("business_day_hint")
        try:
            biz_hint = int(raw_biz) if raw_biz is not None else None
        except (TypeError, ValueError):
            biz_hint = None

        sid = _resolve_step_id(
            data["step_title"],
            dashboard_id=dash_id,
            business_day_hint=biz_hint,
        )
        if not sid:
            return jsonify({
                "success": False,
                "error": {"code": "BAD_STEP", "message": "Unknown step"},
            }), 400
        t.step_id = sid

    if "user_id" in data and data["user_id"] is not None:
        t.user_id = int(data["user_id"])

    # Persist notes when included in patch payload
    if "notes" in data:
        notes_val = (data.get("notes") or "").strip()
        notes_val_for_rec = notes_val
        notes_changed = True
        db.session.execute(
            text("UPDATE Task SET notes = :n WHERE task_id = :tid"),
            {"n": notes_val if notes_val != "" else None, "tid": t.task_id}
        )

    # --- Sync title/notes into Recurring_Task pattern (if linked) ---
    rec_id = getattr(t, "recurring_task_id", None)
    if rec_id:
        updates = []
        params = {"rid": rec_id}
        if title_changed:
            updates.append("title = :title")
            params["title"] = t.title
        if notes_changed:
            updates.append("notes = :notes")
            params["notes"] = (
                notes_val_for_rec if (notes_val_for_rec is not None and notes_val_for_rec != "")
                else None
            )
        if updates:
            db.session.execute(
                text(f"UPDATE Recurring_Task SET {', '.join(updates)} WHERE recurring_task_id = :rid"),
                params,
            )

    # For the UI: which dashboard + month does this task now belong to?
    dash_id = db.session.execute(
        text("""
            SELECT d.dashboard_id
            FROM Step s
            JOIN Dashboard d ON d.dashboard_id = s.dashboard_id
            WHERE s.step_id = :sid
            LIMIT 1
        """),
        {"sid": t.step_id},
    ).scalar()

    month_key = None
    if t.due_date:
        month_key = _month_key_for_due_date(t.due_date)

    db.session.commit()
    return jsonify({"success": True, "data": {
        "task_id": t.task_id,
        "title": t.title,
        "status_id": t.status_id,
        "due_date": _iso_or_none(t.due_date),
        "step_id": t.step_id,
        "user_id": t.user_id,
        "is_recurring": bool(getattr(t, "is_recurring", True)),
        "dashboard_id": dash_id,
        "month_key": month_key,
    }})  # noqa: E501


# ---------------- DELETE (soft) ----------------
@tasks_bp.delete("/<int:task_id>")
@login_required
def delete_task(task_id: int):
    res = db.session.execute(
        text("UPDATE Task SET is_deleted = 1 WHERE task_id = :tid"),
        {"tid": task_id}
    )
    db.session.commit()
    if res.rowcount == 0:
        return jsonify({"success": False, "error": {"code": "NOT_FOUND", "message": "Task not found"}}), 404
    return jsonify({"success": True, "task_id": task_id, "soft_deleted": True})


# ---------------- RESTORE (optional) ----------------
@tasks_bp.post("/<int:task_id>/restore")
@login_required
def restore_task(task_id: int):
    db.session.execute(
        text("UPDATE Task SET is_deleted = 0 WHERE task_id = :tid"),
        {"tid": task_id}
    )
    db.session.commit()
    return jsonify({"success": True, "task_id": task_id})


# ---------------- LIST (optional) ----------------
@tasks_bp.get("")
@tasks_bp.get("/")
@login_required
def list_tasks():

    rows = db.session.execute(text("""
        SELECT t.task_id, t.title, t.due_date, t.status_id, t.step_id, t.user_id, t.is_recurring
        FROM Task t
        WHERE t.is_deleted = 0
        ORDER BY t.task_id ASC
    """)).mappings().all()

    return jsonify({"tasks": [{
        "task_id": r["task_id"],
        "title": r["title"],
        "due_date": _iso_or_none(r["due_date"]),
        "status_id": r["status_id"],
        "step_id": r["step_id"],
        "user_id": r["user_id"],
        "is_recurring": bool(r["is_recurring"]),
    } for r in rows]})
