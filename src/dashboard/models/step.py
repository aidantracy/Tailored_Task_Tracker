from dashboard import db

class Step(db.Model):
    __tablename__ = 'Step'  # matches your schema naming
    step_id = db.Column(db.Integer, primary_key=True)
    title   = db.Column(db.String(255), nullable=False)
    # optional columns are ok to omit (e.g., business_day_id) if you don’t use them
