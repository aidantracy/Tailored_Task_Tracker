import pytest

from dashboard.utils import make_success_response, make_error_response

class TestDevEnv:

    def test_make_success_response(self, app):
        """
        GIVEN a Flask application context
        WHEN make_success_response() is called
        THEN check that it returns a correctly structured success JSON response and status code.
        """
        with app.app_context():
            payload = {"user_id": 1, "email": "test@example.com"}
            response, status_code = make_success_response(data=payload, status_code=201)
            json_data = response.get_json()

        assert status_code == 201
        assert json_data["success"] is True
        assert json_data["data"] == payload
        assert json_data["error"] is None


    @pytest.mark.parametrize(
        "error_code, status_code, message",
        [
            ("INVALID_REGISTRATION", 400, "Generic Error"),
            ("NO_JSON", 400, "Generic Error"),
            ("USER_ALREADY_EXISTS", 409, "Generic Error"),
            ("SERVER_ERROR", 500, "Generic Error"),
            ("USER_DOES_NOT_EXIST", 404, "Generic Error"),
            ("INCORRECT_PASSWORD", 401, "Generic Error"),
            ("LOGOUT_FAILED", 500, "Generic Error"),
        ],
    )
    def test_make_error_response_known_code(self, error_code, status_code, message, app):
        """
        GIVEN a Flask application context
        WHEN make_error_response() is called with a known error code
        THEN check that it returns a correctly structured error JSON response with the correct message.
        """
        with app.app_context():
            response, caught_status_code = make_error_response(
                code=error_code,
                status_code=status_code,
                message=message
            )
            json_data = response.get_json()

        assert caught_status_code == status_code
        assert json_data["success"] is False
        assert json_data["data"] is None
        assert json_data["error"]["code"] == error_code
        assert json_data["error"]["message"] == message


class TestProdEnv:

    @pytest.mark.parametrize(
        "error_code, status_code, message, expected_e_code, expected_s_code, expected_message",
        [
            ("INVALID_REGISTRATION", 400, "Generic Error", "BAD_REQUEST", 400, "The request was malformed or invalid."),
            ("NO_JSON", 400, "Generic Error", "BAD_REQUEST", 400, "The request was malformed or invalid."),
            ("USER_ALREADY_EXISTS", 409, "Generic Error", "INVALID_CREDENTIALS", 400, "Invalid username or password."),
            ("SERVER_ERROR", 500, "Generic Error", "INTERNAL_SERVER_ERROR", 500, "An unexpected error occurred. Please try again later."),
            ("USER_DOES_NOT_EXIST", 404, "Generic Error", "INVALID_CREDENTIALS", 400, "Invalid username or password."),
            ("INCORRECT_PASSWORD", 401, "Generic Error", "INVALID_CREDENTIALS", 400, "Invalid username or password."),
            ("LOGOUT_FAILED", 500, "Generic Error", "INTERNAL_SERVER_ERROR", 500, "An unexpected error occurred. Please try again later."),
        ],
    )
    def test_make_error_response_known_code(
            self,
            error_code,
            status_code,
            message,
            expected_e_code,
            expected_s_code,
            expected_message,
            prod_app
    ):
        """
        GIVEN a prod Flask application context
        WHEN make_error_response() is called with a known error code
        THEN check that a generic error is returned
        """
        with prod_app.app_context():
            response, caught_status_code = make_error_response(
                code=error_code,
                status_code=status_code,
                message=message
            )
            json_data = response.get_json()

        assert caught_status_code == expected_s_code
        assert json_data["success"] is False
        assert json_data["data"] is None
        assert json_data["error"]["code"] == expected_e_code
        assert json_data["error"]["message"] == expected_message