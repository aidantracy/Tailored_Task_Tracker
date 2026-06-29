from __future__ import annotations

import os

from flask import Flask, request, jsonify, redirect, url_for
from flask_bcrypt import Bcrypt
from flask_login import LoginManager
from flask_sqlalchemy import SQLAlchemy
from werkzeug.middleware.dispatcher import DispatcherMiddleware

from .config import DevConfig, ProdConfig, TestConfig, ProdTestConfig

bcrypt = Bcrypt()
login_manager = LoginManager()
db = SQLAlchemy()


def create_app(config_class=None) -> Flask:
    """
    Application factory.

    If config_class is not provided, choose based on FLASK_CONFIG:

      FLASK_CONFIG=prod      -> ProdConfig
      FLASK_CONFIG=production-> ProdConfig
      FLASK_CONFIG=test      -> TestConfig
      FLASK_CONFIG=testing   -> TestConfig
      FLASK_CONFIG=prodtest  -> ProdTestConfig
      (anything else / unset)-> DevConfig
    """
    if config_class is None:
        env = os.getenv("FLASK_CONFIG", "dev").lower()
        if env in ("prod", "production"):
            config_class = ProdConfig
        elif env in ("test", "testing"):
            config_class = TestConfig
        elif env in ("prodtest", "prod_test", "prod-test"):
            config_class = ProdTestConfig
        else:
            config_class = DevConfig

    # Read APP_ROOT from env to support deployment under a URL sub-path
    app_root = os.environ.get("APP_ROOT", "/").rstrip("/") or "/"

    # If we’re under a prefix, serve static files under that prefix too
    if app_root == "/":
        app = Flask(__name__, template_folder="templates", static_folder="static")
    else:
        app = Flask(
            __name__,
            template_folder="templates",
            static_folder="static",
            static_url_path=f"{app_root}/static",
        )

    app.config.from_object(config_class)

    print(f"APPLICATION_ROOT={app_root}")

    # Tell Flask what its application root is
    app.config["APPLICATION_ROOT"] = app_root

    # Dev cookie settings (safe defaults; SDP/render/azure can override via env)
    app.config.update(
        SESSION_COOKIE_SAMESITE="Lax",
        SESSION_COOKIE_SECURE=False,
        REMEMBER_COOKIE_SAMESITE="Lax",
        REMEMBER_COOKIE_SECURE=False,
        TEMPLATES_AUTO_RELOAD=True,
    )

    bcrypt.init_app(app)
    login_manager.init_app(app)
    db.init_app(app)

    login_manager.login_view = "dashboard_bp.index"
    # "strong" can cause logouts behind proxies/load balancers
    login_manager.session_protection = "basic"

    @login_manager.unauthorized_handler
    def _unauthorized():
        wants_json = (
            request.is_json
            or request.accept_mimetypes.quality("application/json")
               > request.accept_mimetypes.quality("text/html")
            or request.path.startswith("/api/")
        )
        if wants_json:
            return jsonify({
                "success": False,
                "data": None,
                "error": {"code": "UNAUTHORIZED", "message": "Login required"},
            }), 401
        return redirect(url_for("dashboard_bp.index"))

    @app.after_request
    def _no_cache(res):
        res.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
        res.headers["Pragma"] = "no-cache"
        res.headers["Expires"] = "0"
        vary = res.headers.get("Vary")
        res.headers["Vary"] = "Cookie" if not vary else (vary + ", Cookie")
        return res

    # ---- Register blueprints (prefer routes/, fall back to flat) ----
    dashboard_bp = auth_bp = due_dates_bp = steps_bp = tasks_bp = comments_bp = None
    try:
        from .routes.dashboard import dashboard_bp  # type: ignore
        from .routes.auth import auth_bp            # type: ignore
        try:
            from .routes.due_dates import bp as due_dates_bp  # type: ignore
        except Exception:
            from .routes.due_dates import due_dates_bp        # type: ignore
        try:
            from .routes.steps import steps_bp  # type: ignore
        except Exception:
            steps_bp = None
        try:
            from .routes.tasks import tasks_bp  # ✅ tasks API
        except Exception:
            tasks_bp = None
        try:
            from .routes.comments import comments_bp  # ✅ comments API
        except Exception:
            comments_bp = None
    except Exception:
        # legacy fallback if routes/ not present
        from .dashboard import dashboard_bp            # type: ignore
        from .auth import auth_bp                      # type: ignore
        try:
            from .due_dates import bp as due_dates_bp  # type: ignore
        except Exception:
            try:
                from .due_dates import due_dates_bp    # type: ignore
            except Exception:
                due_dates_bp = None
        try:
            from .steps import steps_bp  # type: ignore
        except Exception:
            steps_bp = None
        try:
            from .tasks import tasks_bp  # type: ignore
        except Exception:
            tasks_bp = None
        try:
            from .comments import comments_bp 
        except Exception:
            comments_bp = None

    app.register_blueprint(dashboard_bp)
    app.register_blueprint(auth_bp)
    if due_dates_bp:
        app.register_blueprint(due_dates_bp)
    if steps_bp:
        app.register_blueprint(steps_bp)
    if tasks_bp:
        app.register_blueprint(tasks_bp)
    if comments_bp:
        app.register_blueprint(comments_bp)

    # Needed to manually test that error messages in ProdTestConfig are sanitized.
    if app.config["TESTING"] and not app.config["DEBUG"]:
        with app.app_context():
            db.create_all()

    # If we have a prefix, mount the app under that prefix
    if app_root != "/":
        app.wsgi_app = DispatcherMiddleware(
            None,
            {app_root: app.wsgi_app}
        )

    return app
