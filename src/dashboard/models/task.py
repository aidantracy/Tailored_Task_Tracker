# src/dashboard/models/task.py
from dashboard import db

class Status(db.Model):
    __tablename__ = "Status"

    status_id  = db.Column(db.Integer, primary_key=True)
    status     = db.Column(db.String(45))
    color_code = db.Column(db.String(45))


class Task(db.Model):
    __tablename__ = "Task"

    task_id    = db.Column(db.Integer, primary_key=True)

    # FK to Recurring_Task (nullable)
    recurring_task_id = db.Column(
        db.Integer,
        db.ForeignKey("Recurring_Task.recurring_task_id"),
        nullable=True,
    )

    due_date   = db.Column(db.Date)
    ts_id      = db.Column(db.Integer, nullable=False)  # per schema
    user_id    = db.Column(db.Integer)
    step_id    = db.Column(db.Integer, nullable=False)
    status_id  = db.Column(db.Integer, nullable=False)

    # soft-delete flag
    is_deleted = db.Column(
        db.Boolean,
        nullable=False,
        server_default=db.text("0"),
        default=False,
    )

    # monthly recurrence flag
    is_recurring = db.Column(
        db.Boolean,
        nullable=False,
        server_default=db.text("1"),
        default=True,
    )

    title = db.Column(db.String(255), nullable=False)
    notes = db.Column(db.Text)

    # optional relationship back to Recurring_Task (nice but not required)
    recurring_pattern = db.relationship(
        "RecurringTask",
        backref="tasks",
        lazy="joined",
        foreign_keys=[recurring_task_id],
    )


class RecurringTask(db.Model):
    __tablename__ = "Recurring_Task"

    recurring_task_id = db.Column(db.Integer, primary_key=True)

    # which column / step this pattern belongs to
    step_id      = db.Column(db.Integer, nullable=False)

    # day of month (1–31) that this tends to fall on
    day_of_month = db.Column(db.Integer, nullable=False)

    title        = db.Column(db.String(255), nullable=False)
    notes        = db.Column(db.Text)

    is_active    = db.Column(
        db.Boolean,
        nullable=False,
        server_default=db.text("1"),
        default=True,
    )
