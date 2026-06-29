"""
This will be our test suite for the backend.

For adding new files to this folder the name of the file matters or else
pytest won't find your test file needs "test_" behind what ever the
filename is for pytest to find it.
"""

import pytest

from dashboard.models.user import User


class TestSignup:

    def test_signup_success(self, test_client, available_key):
        """
        GIVEN a Flask application configured for testing
        WHEN the "/signup" endpoint is posted to with valid data
        THEN check that a "201 Created" status code is returned, the user is in the DB,
             and the JSON response is correct.
        """
        response = test_client.post("/signup", json={
            "email": "test@example.com",
            "password": "aComplexPassword123!",
            "first_name": "John",
            "last_name": "Doe",
            "invitation_key": available_key.key_value,
            "security_question": "What was the name of your first pet?",
            "security_answer": "blah",
        })
        data = response.json

        assert response.status_code == 201
        assert data["success"] is True
        assert "Signup successful!" in data["data"]["message"]

        assert "Set-Cookie" in response.headers

        user = User.query.filter_by(email="test@example.com").first()
        assert user is not None
        assert user.email == "test@example.com"


    @pytest.mark.parametrize(
        "payload, status_code, description",
        [
            ({"password": "aComplexPassword123!"}, 400, "Missing email and names"),
            ({"email": "test@example.com"}, 400, "Missing password and names"),
            ({"email": "", "password": "aComplexPassword123!"}, 400, "Empty email string and no names"),
            ({"email": "test@example.com", "password": ""}, 400, "Empty password string and no names"),
            ({}, 400, "Empty JSON object"),
            ({"first_name": "John", "last_name": "Doe"}, 400, "Missing email and password"),
        ],
    )
    def test_signup_bad_requests(self, test_client, payload, status_code, description):
        """
        GIVEN a Flask application
        WHEN the "/signup" endpoint is posted to with bad request
        THEN check that a "400 Bad Request" status_code is returned
        """
        response = test_client.post("/signup", json=payload)
        data = response.json

        assert response.status_code == status_code
        assert data["success"] is False


    @pytest.mark.parametrize(
        "payload, description",
        [
            ({"email": "not-a-valid-email", "password": "aComplexPassword123!", "first_name": "John", "last_name": "Doe"}, "Invalid email format"),
            ({"email": "test@example.com", "password": "weak", "first_name": "John", "last_name": "Doe"}, "Password does not meet complexity requirements"),
            ({"email": "not-a-valid-email", "password": "weak", "first_name": "John", "last_name": "Doe"}, "Invalid Email and Password"),
            ({"blah": "blah blah blah","email": "valid@email.com", "password": "aComplexPassword123!"}, "Extra json data"),
        ]
    )
    def test_signup_invalid_data_formats(self, test_client, payload, description):
        """
        GIVEN a Flask application
        WHEN the "/signup" endpoint is posted with invalidly formatted data
        THEN check that a "400 Bad Request" status_code is returned.
        """
        response = test_client.post("/signup", json=payload)
        data = response.json
        print(data["error"]["message"])

        assert response.status_code == 400
        assert data["success"] is False
        assert data["error"]["code"] == "INVALID_REGISTRATION"


    def test_signup_bad_json_body(self, test_client):
        """
        GIVEN a Flask application
        WHEN the "/signup" endpoint is posted to without a JSON body
        THEN check that a "400 Bad Request" is returned
        """
        response = test_client.post(
            "/signup",
            content_type="application/json",
            data="blah blah blah"
        )

        data = response.json

        assert response.status_code == 400
        assert data["error"]["code"] == "NO_JSON"

    def test_signup_no_json_body(self, test_client):
        """
        GIVEN a Flask application
        WHEN the "/signup" endpoint is posted to without a JSON body
        THEN check that a "400 Bad Request" is returned with the "NO_JSON" error code.
        """
        response = test_client.post(
            "/signup",
            content_type="application/json",
        )
        data = response.json

        assert response.status_code == 400
        assert data["error"]["code"] == "NO_JSON"

    def test_signup_user_already_exists(self, test_client, test_user, available_key):
        """
        GIVEN a Flask application with a pre-existing user
        WHEN the "/signup" endpoint is posted with the same user's email
        THEN check that a "400 Conflict" is returned.
        """
        response = test_client.post("/signup", json={
            "email": test_user.email,
            "password": "aNewPassword1!",
            "first_name": "John",
            "last_name": "Doe",
            "invitation_key": available_key.key_value,
            "security_question": "What was the name of your first pet?",
            "security_answer": "blah",
        })
        data = response.json

        assert response.status_code == 409
        assert data["success"] is False


    def test_signup_database_read_error(self, test_client, mock_user_read_error, available_key):
        """
        GIVEN a Flask application
        WHEN a database read error occurs during signup
        THEN check that a "500 Internal Server Error" is returned.
        """
        response = test_client.post("/signup", json={
            "email": "test@example.com",
            "password": "aComplexPassword123!",
            "first_name": "John",
            "last_name": "Doe",
            "invitation_key": available_key.key_value,
            "security_question": "What was the name of your first pet?",
            "security_answer": "blah",
        })
        data = response.json

        assert response.status_code == 500
        assert data["success"] is False
        assert data["error"]["code"] == "SERVER_ERROR"


class TestLogin:

    def test_login_success(self, test_client, test_user):
        """
        GIVEN a Flask application and an existing user
        WHEN the "/login" endpoint is posted to with valid credentials
        THEN check that a "200 OK" status code is returned and the
             JSON response is correct.
        """
        response = test_client.post("/login", json={
            "email": test_user.email,
            "password": "aComplexPassword123!",
        })
        data = response.json

        assert response.status_code == 200
        assert data["success"] is True
        assert "Login successful!" in data["data"]["message"]
        assert "Set-Cookie" in response.headers


    @pytest.mark.parametrize(
        "payload, status_code, description",
        [
            ({"password": "aComplexPassword123!"}, 400, "Missing email"),
            ({"email": "test@example.com"}, 400, "Missing password"),
            ({"email": "", "password": "aComplexPassword123!"}, 400, "Empty email string"),
            ({"email": "test@example.com", "password": ""}, 400, "Empty password string"),
            ({}, 400, "Empty JSON object"),
        ],
    )
    def test_login_bad_requests_missing_data(self, test_client, payload, status_code, description):
        """
        GIVEN a Flask application
        WHEN the "/login" endpoint is posted to with missing data
        THEN check that a "400 Bad Request" status_code is returned
        """
        response = test_client.post("/login", json=payload)
        data = response.json

        assert response.status_code == status_code
        assert data["success"] is False


    @pytest.mark.parametrize(
        "payload, description",
        [
            ({"email": "not-a-valid-email", "password": "aComplexPassword123!"}, "Invalid email format"),
            ({"blah": "blah blah blah","email": "valid@email.com", "password": "aComplexPassword123!"}, "Extra json data"),
        ]
    )
    def test_login_invalid_data_formats(self, test_client, payload, description):
        """
        GIVEN a Flask application
        WHEN the "/login" endpoint is posted with invalidly formatted data (e.g., bad email)
        THEN check that a "400 Bad Request" status_code is returned.
        """
        response = test_client.post("/login", json=payload)
        data = response.json

        assert response.status_code == 400
        assert data["success"] is False
        assert data["error"]["code"] == "INVALID_REGISTRATION" # Same as above, check your error code


    def test_login_bad_json_body(self, test_client):
        """
        GIVEN a Flask application
        WHEN the "/login" endpoint is posted to with an invalid JSON body
        THEN check that a "400 Bad Request" is returned
        """
        response = test_client.post(
            "/login",
            content_type="application/json",
            data="not json"
        )
        data = response.json

        assert response.status_code == 400
        assert data["error"]["code"] == "NO_JSON"


    def test_login_no_json_body(self, test_client):
        """
        GIVEN a Flask application
        WHEN the "/login" endpoint is posted to without a JSON body
        THEN check that a "400 Bad Request" is returned
        """
        response = test_client.post(
            "/login",
            content_type="application/json",
        )
        data = response.json

        assert response.status_code == 400
        assert data["error"]["code"] == "NO_JSON"


    def test_login_user_does_not_exist(self, test_client):
        """
        GIVEN a Flask application
        WHEN the "/login" endpoint is posted with an email that does not exist
        THEN check that a "404 Not Found" is returned.
        """
        response = test_client.post("/login", json={
            "email": "nobody@example.com",
            "password": "aPassword1!",
        })
        data = response.json

        assert response.status_code == 404
        assert data["success"] is False
        assert data["error"]["code"] == "USER_DOES_NOT_EXIST"


    def test_login_incorrect_password(self, test_client, test_user):
        """
        GIVEN a Flask application and an existing user
        WHEN the "/login" endpoint is posted with the wrong password
        THEN check that a "401 Unauthorized" is returned.
        """
        response = test_client.post("/login", json={
            "email": test_user.email,
            "password": "ThisIsTheWrongPassword!",
        })
        data = response.json

        assert response.status_code == 401
        assert data["success"] is False
        assert data["error"]["code"] == "INCORRECT_PASSWORD"


    def test_login_database_error(self, test_client, mock_user_read_error):
        """
        GIVEN a Flask application
        WHEN a database error occurs during the login read operation
        THEN check that a "500 Internal Server Error" is returned.
        """
        response = test_client.post("/login", json={
            "email": "test@example.com",
            "password": "aComplexPassword123!",
        })
        data = response.json

        assert response.status_code == 500
        assert data["success"] is False
        assert data["error"]["code"] == "SERVER_ERROR"