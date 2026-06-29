import os


class Config:
    """Base configuration settings for the Flask app."""
    SECRET_KEY = os.getenv("SECRET_KEY", "a-very-secret-key-you-should-change")
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    DEBUG = False
    TESTING = False

    # Generic override for cloud environments (Render, Azure, etc.)
    # e.g. mysql+pymysql://user:pass@host:3306/dashboard
    #   or postgresql+psycopg2://user:pass@host:5432/dbname
    DATABASE_URL = os.getenv("DATABASE_URL")


class DevConfig(Config):
    """Development / default config (local, SDP, etc.)."""
    DEBUG = True

    # Default MySQL settings (used when DATABASE_URL is NOT set)
    DB_USER = os.getenv("MYSQL_USER", "dashboard_user")
    DB_PASSWORD = os.getenv("MYSQL_PASSWORD", "devpassword")
    DB_HOST = os.getenv("DB_HOST", "db")
    DB_PORT = os.getenv("DB_PORT", "3306")
    DB_NAME = os.getenv("MYSQL_DATABASE", "dashboard")

    if Config.DATABASE_URL:
        # Cloud / external DB (Render, Azure, etc.)
        SQLALCHEMY_DATABASE_URI = Config.DATABASE_URL
    else:
        # Local / SDP MySQL
        SQLALCHEMY_DATABASE_URI = (
            f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}"
            f"@{DB_HOST}:{DB_PORT}/{DB_NAME}"
        )


class TestConfig(Config):
    """Config used for unit tests (in-memory SQLite)."""
    DEBUG = True
    TESTING = True
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    WTF_CSRF_ENABLED = False


class ProdTestConfig(TestConfig):
    """
    Special testing config used to validate production-style
    error handling (TESTING=True but DEBUG=False).
    """
    DEBUG = False


class ProdConfig(Config):
    """
    Real production config.
    Uses DATABASE_URL when set, otherwise falls back to MySQL-style env vars.
    """
    DEBUG = False

    DB_USER = os.getenv("MYSQL_USER", "dashboard_user")
    DB_PASSWORD = os.getenv("MYSQL_PASSWORD", "devpassword")
    DB_HOST = os.getenv("DB_HOST", "db")
    DB_PORT = os.getenv("DB_PORT", "3306")
    DB_NAME = os.getenv("MYSQL_DATABASE", "dashboard")

    if Config.DATABASE_URL:
        SQLALCHEMY_DATABASE_URI = Config.DATABASE_URL
    else:
        SQLALCHEMY_DATABASE_URI = (
            f"mysql+pymysql://{DB_USER}:{DB_PASSWORD}"
            f"@{DB_HOST}:{DB_PORT}/{DB_NAME}"
        )
