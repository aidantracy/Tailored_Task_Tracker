from flask import jsonify, current_app

GENERIC_ERROR_MAP = {
    "USER_DOES_NOT_EXIST": "INVALID_CREDENTIALS",
    "INCORRECT_PASSWORD": "INVALID_CREDENTIALS",
    "USER_ALREADY_EXISTS": "INVALID_CREDENTIALS",
    "INVALID_REGISTRATION": "BAD_REQUEST",
    "NO_JSON": "BAD_REQUEST",
    "SERVER_ERROR": "INTERNAL_SERVER_ERROR",
    "LOGOUT_FAILED": "INTERNAL_SERVER_ERROR",
}

GENERIC_MESSAGES_CODES = {
    "INVALID_CREDENTIALS": ["Invalid username or password.", 400],
    "BAD_REQUEST": ["The request was malformed or invalid.", 400],
    "INTERNAL_SERVER_ERROR": ["An unexpected error occurred. Please try again later.", 500]
}

def make_success_response(data, status_code=200):
    """Creates a standardized success JSON response."""
    response = {
        "success": True,
        "data": data,
        "error": None,
    }
    return jsonify(response), status_code

def make_error_response(code, status_code, message):
    """Creates a standardized JSON error response."""

    if current_app.config.get("DEBUG"):
        final_code = code
        final_message = message
        final_status_code = status_code
    else:
        if code in GENERIC_ERROR_MAP:
            final_code = GENERIC_ERROR_MAP[code]
            final_message = GENERIC_MESSAGES_CODES[final_code][0]
            final_status_code = GENERIC_MESSAGES_CODES[final_code][1]
        else:
            final_code = "UNEXPECTED_ERROR"
            final_message = "An unexpected error occurred. Please try again later."
            final_status_code = 500

    error_payload = {
        "success": False,
        "data": None,
        "error": {
            "code": final_code,
            "message": final_message,
        }
    }
    return jsonify(error_payload), final_status_code