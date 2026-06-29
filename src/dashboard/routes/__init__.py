# dashboard/routes/__init__.py
from .auth import auth_bp
from .dashboard import dashboard_bp
from .due_dates import bp as due_dates_bp

def register(app):
    app.register_blueprint(dashboard_bp)
    app.register_blueprint(auth_bp)
    app.register_blueprint(due_dates_bp)

__all__ = ["dashboard_bp", "auth_bp", "due_dates_bp", "register"]
