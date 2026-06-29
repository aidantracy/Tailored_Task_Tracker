# src/dashboard/routes/comments.py
from __future__ import annotations

from datetime import datetime, timedelta
from flask import Blueprint, jsonify, request, current_app
from flask_login import login_required, current_user
from sqlalchemy import text
from dashboard import db

comments_bp = Blueprint("comments_bp", __name__, url_prefix="/api")


def _display_name(row):
    first = (row.get("first_name") or "").strip()
    last = (row.get("last_name") or "").strip()
    if first or last:
        return (first + " " + last).strip()
    return (row.get("username") or row.get("email") or "Unknown").strip()


@comments_bp.get("/me")
@login_required
def me():
    """Lightweight current-user payload so the client can align bubbles correctly."""
    try:
        uid = getattr(current_user, "user_id", None)
        username = getattr(current_user, "username", None)
        email = getattr(current_user, "email", None)
        first = getattr(current_user, "first_name", None)
        last = getattr(current_user, "last_name", None)
        display = " ".join([x for x in [first, last] if x]) or (username or email or "You")
        return jsonify(
            {
                "user_id": uid,
                "username": username,
                "email": email,
                "first_name": first,
                "last_name": last,
                "display_name": display,
            }
        ), 200
    except Exception:
        return jsonify(
            {
                "user_id": getattr(current_user, "user_id", None),
                "display_name": getattr(current_user, "username", None) or "You",
            }
        ), 200


@comments_bp.get("/tasks/<int:task_id>/comments")
@login_required
def list_comments(task_id: int):
    rows = db.session.execute(
        text(
            """
        SELECT c.comment_id,
               c.user_id,
               c.task_id,
               c.comment,
               ts.create_time,
               u.first_name, u.last_name, u.username, u.email
          FROM Comments c
          JOIN Timestamps ts ON ts.ts_id = c.ts_id
          JOIN Users u       ON u.user_id = c.user_id
         WHERE c.task_id = :task_id
         ORDER BY ts.create_time ASC
        """
        ),
        {"task_id": task_id},
    ).mappings().all()

    return jsonify({
        "comments": [{
            "comment_id": r["comment_id"],
            "user_id": r["user_id"],
            "task_id": r["task_id"],
            "text": r["comment"] or "",
            "at_iso": (
                r["create_time"].isoformat(sep="T", timespec="seconds")
                if hasattr(r["create_time"], "isoformat") and r["create_time"] else None
            ),
            "who": _display_name(r),
        } for r in rows]
    }), 200


@comments_bp.post("/tasks/<int:task_id>/comments")
@login_required
def create_comment(task_id: int):
    data = request.get_json(silent=True) or {}
    text_body = (data.get("text") or "").strip()
    if not text_body:
        return jsonify({"success": False, "error": {"code": "BAD_TEXT", "message": "text is required"}}), 400

    uid = int(current_user.user_id)

    # ---- Duplicate guard: same user, same task, identical text within 5s -> return that one
    try:
        last = db.session.execute(
            text(
                """
            SELECT c.comment_id, c.comment, ts.create_time,
                   u.first_name, u.last_name, u.username, u.email, c.user_id
              FROM Comments c
              JOIN Timestamps ts ON ts.ts_id = c.ts_id
              JOIN Users u       ON u.user_id = c.user_id
             WHERE c.task_id = :task_id AND c.user_id = :uid
             ORDER BY ts.create_time DESC
             LIMIT 1
            """
            ),
            {"task_id": task_id, "uid": uid},
        ).mappings().first()

        if last and (last["comment"] or "") == text_body and last.get("create_time"):
            now = datetime.utcnow()
            created_at = last["create_time"]
            try:
                created_at = created_at.replace(tzinfo=None)
            except Exception:
                pass
            if (now - created_at) <= timedelta(seconds=5):
                return jsonify({
                    "comment": {
                        "comment_id": last["comment_id"],
                        "user_id": last["user_id"],
                        "task_id": task_id,
                        "text": last["comment"] or "",
                        "at_iso": created_at.isoformat(timespec="seconds"),
                        "who": _display_name(last),
                    }
                }), 200
    except Exception:
        current_app.logger.exception("duplicate guard lookup failed")

    # ---- Insert path
    try:
        preview = text_body[:120] + ("…" if len(text_body) > 120 else "")

        audit = db.session.execute(
            text("""
                INSERT INTO Audit_Log (task_id, user_id, prev_state, new_state, table_type, table_id)
                VALUES (:task_id, :user_id, NULL, :new_state, 'Comments', NULL)
            """),
            {"task_id": task_id, "user_id": uid, "new_state": preview},
        )
        audit_log_id = audit.lastrowid

        ts = db.session.execute(
            text("""INSERT INTO Timestamps (audit_log_id) VALUES (:audit_log_id)"""),
            {"audit_log_id": audit_log_id},
        )
        ts_id = ts.lastrowid

        ins = db.session.execute(
            text("""
                INSERT INTO Comments (user_id, task_id, ts_id, comment)
                VALUES (:user_id, :task_id, :ts_id, :comment)
            """),
            {"user_id": uid, "task_id": task_id, "ts_id": ts_id, "comment": text_body},
        )
        comment_id = ins.lastrowid

        db.session.execute(
            text("""UPDATE Audit_Log SET table_id = :comment_id WHERE audit_log_id = :audit_log_id"""),
            {"comment_id": comment_id, "audit_log_id": audit_log_id},
        )

        db.session.commit()

    except Exception:
        db.session.rollback()
        current_app.logger.exception("create_comment failed")
        return jsonify({"success": False, "error": {"code": "DB_ERROR", "message": "Failed to save comment"}}), 500

    # Return the created comment including display info
    row = db.session.execute(
        text(
            """
        SELECT c.comment_id,
               c.user_id,
               c.task_id,
               c.comment,
               ts.create_time,
               u.first_name, u.last_name, u.username, u.email
          FROM Comments c
          JOIN Timestamps ts ON ts.ts_id = c.ts_id
          JOIN Users u       ON u.user_id = c.user_id
         WHERE c.comment_id = :cid
        """
        ),
        {"cid": comment_id},
    ).mappings().first()

    return jsonify({
        "comment": {
            "comment_id": row["comment_id"],
            "user_id": row["user_id"],
            "task_id": row["task_id"],
            "text": row["comment"] or "",
            "at_iso": (
                row["create_time"].isoformat(sep="T", timespec="seconds")
                if hasattr(row["create_time"], "isoformat") and row["create_time"] else None
            ),
            "who": _display_name(row),
        }
    }), 201


@comments_bp.get("/comments/counts")
@login_required
def comment_counts():
    ids_raw = (request.args.get("task_ids") or "").strip()
    if not ids_raw:
        return jsonify({"counts": {}}), 200

    try:
        ids = [int(x) for x in ids_raw.split(",") if x.strip().isdigit()]
    except Exception:
        ids = []
    if not ids:
        return jsonify({"counts": {}}), 200

    placeholders = ",".join([f":id{i}" for i in range(len(ids))])
    params = {f"id{i}": ids[i] for i in range(len(ids))}
    rows = db.session.execute(
        text(
            f"""
        SELECT c.task_id, COUNT(*) AS cnt
          FROM Comments c
         WHERE c.task_id IN ({placeholders})
         GROUP BY c.task_id
        """
        ),
        params,
    ).mappings().all()

    return jsonify({"counts": {str(r["task_id"]): int(r["cnt"]) for r in rows}}), 200


@comments_bp.get("/comments/unread_counts")
@login_required
def unread_counts():
    """For the current user, how many comments by others are newer than last_read_ts per task."""
    ids_raw = (request.args.get("task_ids") or "").strip()
    if not ids_raw:
        return jsonify({"counts": {}}), 200
    try:
        ids = [int(x) for x in ids_raw.split(",") if x.strip().isdigit()]
    except Exception:
        ids = []
    if not ids:
        return jsonify({"counts": {}}), 200

    uid = int(current_user.user_id)
    placeholders = ",".join([f":id{i}" for i in range(len(ids))])
    params = {f"id{i}": ids[i] for i in range(len(ids))}
    params["uid"] = uid

    rows = db.session.execute(
        text(
            f"""
        SELECT c.task_id, COUNT(*) AS unread_cnt
          FROM Comments c
          JOIN Timestamps ts ON ts.ts_id = c.ts_id
          LEFT JOIN User_Task_Read_Markers m
                 ON m.user_id = :uid AND m.task_id = c.task_id
         WHERE c.task_id IN ({placeholders})
           AND c.user_id <> :uid
           AND (m.last_read_ts IS NULL OR ts.create_time > m.last_read_ts)
         GROUP BY c.task_id
        """
        ),
        params,
    ).mappings().all()

    return jsonify({"counts": {str(r["task_id"]): int(r["unread_cnt"]) for r in rows}}), 200


@comments_bp.post("/tasks/<int:task_id>/comments/read_mark")
@login_required
def mark_read(task_id: int):
    """Mark the thread as read up to the latest comment timestamp."""
    uid = int(current_user.user_id)

    # Find the newest comment timestamp for this task; if none, use now().
    row = db.session.execute(
        text(
            """
        SELECT MAX(ts.create_time) AS latest_ts
          FROM Comments c
          JOIN Timestamps ts ON ts.ts_id = c.ts_id
         WHERE c.task_id = :task_id
        """
        ),
        {"task_id": task_id},
    ).mappings().first()
    latest_ts = row["latest_ts"] if row and row["latest_ts"] else datetime.utcnow()

    try:
        db.session.execute(
            text(
                """
            INSERT INTO User_Task_Read_Markers (user_id, task_id, last_read_ts)
            VALUES (:uid, :task_id, :latest_ts)
            ON DUPLICATE KEY UPDATE last_read_ts = GREATEST(VALUES(last_read_ts), last_read_ts)
            """
            ),
            {"uid": uid, "task_id": task_id, "latest_ts": latest_ts},
        )
        db.session.commit()
        return jsonify({"success": True, "task_id": task_id, "last_read_ts": latest_ts.isoformat(timespec="seconds")}), 200
    except Exception:
        db.session.rollback()
        current_app.logger.exception("mark_read failed")
        return jsonify({"success": False}), 500
