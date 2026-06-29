"""
This file contains shared fixtures for the test suite.

Fixtures defined here are automatically discovered by pytest and can be used
in any test file within this directory and its subdirectories without needing
to be imported.
"""
import pytest
from pymysql import IntegrityError
from flask_bcrypt import Bcrypt
from sqlalchemy.exc import SQLAlchemyError

from dashboard import create_app, db
from dashboard.config import TestConfig, ProdTestConfig
from dashboard.models import User, InvitationKey
from dashboard.schemas import SignupSchema, LoginSchema


@pytest.fixture(scope='function')
def app():
    """Instance of Flask application configured for testing."""
    app = create_app(TestConfig)

    with app.app_context():
        db.create_all()
        yield app
        db.drop_all()

@pytest.fixture(scope='function')
def prod_app():
    """Flask app for testing prod messages."""
    app = create_app(ProdTestConfig)

    with app.app_context():
        db.create_all()
        yield app
        db.drop_all()

@pytest.fixture(scope='function')
def test_client(app):
    return app.test_client()

@pytest.fixture(scope='function')
def test_client_prod(prod_app):
    return prod_app.test_client()

@pytest.fixture(scope='session')
def bcrypt():
    """Provides a Bcrypt instance for unittests."""
    return Bcrypt()

@pytest.fixture(scope="function")
def signup_user_data(available_key):
    return SignupSchema.model_validate({
        "email" :"service_test@example.com",
        "password": "aComplexPassword123!",
        "first_name": "John",
        "last_name": "Doe",
        "invitation_key": available_key.key_value,
        "security_question": "What was the name of your first pet?",
        "security_answer": "blah",
    })

@pytest.fixture(scope="session")
def login_user_data():
    return LoginSchema.model_validate({
        "email" :"service_test@example.com",
        "password": "aComplexPassword123!",
    })

@pytest.fixture(scope="function")
def test_user(app, bcrypt):
    """
    Fixture to create and save a new ADMIN user to the database.
    This user is removed after the test finishes.
    """
    user = User(
        email="admin@example.com",
        first_name="Test",
        last_name="User",
        is_admin=1,
    )
    user.set_password(bcrypt, "aComplexPassword123!")

    db.session.add(user)
    db.session.commit()

    return user

@pytest.fixture(scope="function")
def available_key(app, test_user):
    """
    Fixture to create an available invitation key, created by the admin test_user.
    """
    # We use test_user (who is now an admin) as the creator
    key = InvitationKey(
        key_value="test-key-123",
        created_by_user_id=test_user.user_id,
        is_used=0
    )
    db.session.add(key)
    db.session.commit()

    return key

@pytest.fixture
def mock_user_read_error(monkeypatch):
    """
    Simulates a database read error (e.g., connection lost)
    any time User.query.filter_by(...).first() is called.
    """

    def mock_first(*args, **kwargs):
        raise SQLAlchemyError("Simulated DB connection error", {}, None)

    monkeypatch.setattr(User.query_class, "first", mock_first)

@pytest.fixture
def mock_user_commit_error(monkeypatch):
    """
    Simulates a database write error (e.g., missing on nullable key)
    any time db.commit(...) is called.
    """

    def mock_commit():
        raise IntegrityError("Simulated database commit error", {}, None)

    monkeypatch.setattr(db.session, "commit", mock_commit)