# src/dashboard/routes/steps.py
from __future__ import annotations

from flask import Blueprint, jsonify, request
from sqlalchemy import text
from dashboard import db

steps_bp = Blueprint("steps", __name__, url_prefix="/api/steps")


@steps_bp.patch("/rename")
def rename_step():
    """
    Rename a Step (column) by dashboard + old title.

    JSON body:
      {
        "dashboard_id": <int>,        # required
        "old_title": "Populate Financials",
        "new_title": "New Name"
      }

    200 OK  -> {"ok": True,  "step": {"dashboard_id": X, "old_title": "...", "new_title": "..."}}
    400     -> missing params, too long, etc.
    404     -> old_title not found
    409     -> new_title already exists on this dashboard
    """
    data = request.get_json(silent=True) or {}

    # validate inputs
    try:
        dash_id = int(data.get("dashboard_id"))
    except Exception:
        dash_id = None

    old_title = (data.get("old_title") or "").strip()
    new_title = (data.get("new_title") or "").strip()

    if not dash_id or not old_title or not new_title:
        return jsonify({"ok": False, "error": "dashboard_id, old_title, and new_title are required"}), 400
    if len(new_title) > 100:
        return jsonify({"ok": False, "error": "new_title too long"}), 400
    if old_title == new_title:
        return jsonify({"ok": True, "step": {"dashboard_id": dash_id, "old_title": old_title, "new_title": new_title}}), 200

    with db.engine.begin() as conn:
        # ensure old title exists
        exists = conn.execute(
            text("SELECT step_id FROM Step WHERE dashboard_id=:d AND step_title=:t LIMIT 1"),
            {"d": dash_id, "t": old_title},
        ).first()
        if not exists:
            return jsonify({"ok": False, "error": "Step not found"}), 404

        # prevent duplicates
        dup = conn.execute(
            text("SELECT step_id FROM Step WHERE dashboard_id=:d AND step_title=:t LIMIT 1"),
            {"d": dash_id, "t": new_title},
        ).first()
        if dup:
            return jsonify({"ok": False, "error": "A step with that name already exists"}), 409

        # apply rename
        res = conn.execute(
            text("""
                UPDATE Step
                   SET step_title=:new
                 WHERE dashboard_id=:d AND step_title=:old
                 LIMIT 1
            """),
            {"new": new_title, "d": dash_id, "old": old_title},
        )
        if res.rowcount == 0:
            return jsonify({"ok": False, "error": "Step not found"}), 404

    return jsonify({
        "ok": True,
        "step": {"dashboard_id": dash_id, "old_title": old_title, "new_title": new_title}
    }), 200
