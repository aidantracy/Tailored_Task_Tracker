import pytest

from dashboard import db, bcrypt
from dashboard.models.user import User
from dashboard.services import user_service
from dashboard.utils import (
    UserAlreadyExistsError,
    DatabaseCommitError,
    DatabaseReadError,
    IncorrectPassword,
    UserDoesNotExistError,
)


class TestCreateUser:

    def test_create_user_success(self, app, signup_user_data):
        """
        GIVEN a running Flask app context
        WHEN the create_user service is called with valid data
        THEN check that it returns a new User object and the user is in the DB.
        """
        new_user = user_service.create_user(signup_user_data)

        assert new_user.email == "service_test@example.com"
        assert new_user.first_name == "John"
        assert new_user.last_name == "Doe"

        persisted_user = User.query.filter_by(email="service_test@example.com").first()
        assert persisted_user is not None
        assert persisted_user.check_password(bcrypt, "aComplexPassword123!")


    def test_create_user_email_exists(self, app, signup_user_data, test_user):
        """
        GIVEN a running Flask app context with a pre-existing user
        WHEN the create_user service is called with the same email
        THEN check that it raises UserAlreadyExistsError
        """
        signup_user_data.email = test_user.email

        with pytest.raises(UserAlreadyExistsError):
            user_service.create_user(signup_user_data)


    def test_create_user_database_read_error(self, app, signup_user_data, mock_user_read_error):
        """
        GIVEN a running Flask app context
        WHEN the database read fails during user creation
        THEN check that it raises DatabaseReadError
        """
        with pytest.raises(DatabaseReadError):
            user_service.create_user(signup_user_data)


    def test_create_user_database_commit_error(self, app, signup_user_data, mock_user_commit_error):
        """
        GIVEN a running Flask app context
        WHEN the database commit fails during user creation
        THEN check that it raises DatabaseCommitError
        """
        with pytest.raises(DatabaseCommitError):
            user_service.create_user(signup_user_data)


class TestLoginUser:

    def test_login_user_success(self, app, login_user_data, test_user):
        """
        GIVEN a running Flask app context with a pre-existing user
        WHEN the login_user service is called with valid data and an already existing user
        THEN check that it returns a User object with the same information as the already existing user
        """
        login_user_data.email = test_user.email
        new_user = user_service.login_user(login_user_data)

        assert new_user.email == test_user.email
        assert new_user.first_name == test_user.first_name
        assert new_user.last_name == test_user.last_name
        assert new_user.check_password(bcrypt, "aComplexPassword123!")


    def test_login_user_email_does_not_exists(self, app, login_user_data):
        """
        GIVEN a running Flask app context
        WHEN the login_user service is called with no associated email
        THEN check that it raises UserDoesNotExistError
        """
        with pytest.raises(UserDoesNotExistError):
            user_service.login_user(login_user_data)

    def test_login_user_incorrect_password(self, app, login_user_data, test_user):
        """
        GIVEN a running Flask app context with a pre-existing user
        WHEN the login_user service is called with a new email
        THEN check that it raises IncorrectPassword
        """
        login_user_data.email = test_user.email
        login_user_data.password = "blahblahblah"
        with pytest.raises(IncorrectPassword):
            user_service.login_user(login_user_data)


    def test_login_user_database_read_error(self, app, login_user_data, mock_user_read_error):
        """
        GIVEN a running Flask app context
        WHEN the database read fails during user login
        THEN check that it raises DatabaseReadError
        """
        with pytest.raises(DatabaseReadError):
            user_service.login_user(login_user_data)