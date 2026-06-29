from flask import Blueprint, request, redirect, url_for
from flask_login import login_user, logout_user, login_required
from pydantic import ValidationError
from werkzeug.exceptions import BadRequest

from ..schemas.auth_schemas import ResetRequestSchema, ResetConfirmSchema
from ..services import user_service
from ..schemas import SignupSchema, LoginSchema
from ..utils import (
    UserAlreadyExistsError,
    UserDoesNotExistError,
    IncorrectPassword,
    DatabaseCommitError,
    DatabaseReadError,
    InvalidInvitationKeyError,
)
from ..utils.responses import make_success_response, make_error_response

auth_bp = Blueprint('auth_bp', __name__)

@auth_bp.post("/signup")
def signup():
    try:
        raw_data = request.get_json()
        user_data = SignupSchema.model_validate(raw_data)
        new_user = user_service.create_user(user_data)
        login_user(new_user, remember=False)
        return make_success_response(
            data={"message": "Signup successful! You are logged in."},
            status_code=201
        )
    except ValidationError as e:
        return make_error_response("INVALID_REGISTRATION", status_code=400, message=str(e))
    except BadRequest as e:
        return make_error_response(code="NO_JSON", status_code=400, message=str(e))
    except UserAlreadyExistsError as e:
        return make_error_response(code="USER_ALREADY_EXISTS", status_code=409, message=str(e))
    except InvalidInvitationKeyError as e:
        return make_error_response(code="INVALID_KEY", status_code=403, message=str(e))
    except (DatabaseCommitError, DatabaseReadError) as e:
        return make_error_response(code="SERVER_ERROR", status_code=500, message=str(e))

@auth_bp.post("/login")
def login():
    try:
        raw_data = request.get_json()
        user_data = LoginSchema.model_validate(raw_data)
        old_user = user_service.login_user(user_data)
        login_user(old_user, remember=False)
        return make_success_response(
            data={"message": "Login successful! You are logged in."},
            status_code=200
        )
    except ValidationError as e:
        return make_error_response("INVALID_REGISTRATION", status_code=400, message=str(e))
    except BadRequest as e:
        return make_error_response(code="NO_JSON", status_code=400, message=str(e))
    except UserDoesNotExistError as e:
        return make_error_response(code="USER_DOES_NOT_EXIST", status_code=404, message=str(e))
    except IncorrectPassword as e:
        return make_error_response(code="INCORRECT_PASSWORD", status_code=401, message=str(e))
    except PermissionError as e:
        return make_error_response(code="ACCOUNT_DELETED", status_code=403, message=str(e))
    except DatabaseReadError as e:
        return make_error_response(code="SERVER_ERROR", status_code=500, message=str(e))


@auth_bp.post("/reset-request")
def reset_request():
    """
    Step 1: User provides email, system returns the security question.
    """
    try:
        raw_data = request.get_json()
        data = ResetRequestSchema.model_validate(raw_data)
        question = user_service.get_security_question(data.email)

        return make_success_response(
            data={"question": question},
            status_code=200
        )
    except (UserDoesNotExistError, ValidationError) as e:
        return make_error_response("INVALID_DATA", status_code=400, message=str(e))
    except Exception as e:
        return make_error_response("SERVER_ERROR", status_code=500, message=str(e))

@auth_bp.post("/reset-confirm")
def reset_confirm():
    """
    Step 2: User provides security answer and new password.
    """
    try:
        raw_data = request.get_json()
        data = ResetConfirmSchema.model_validate(raw_data)
        user_service.reset_password(data)

        return make_success_response(
            data={"message": "Password reset successful. Please login."},
            status_code=200
        )
    except (UserDoesNotExistError, ValidationError) as e:
        return make_error_response("INVALID_DATA", status_code=400, message=str(e))
    except IncorrectPassword:
        return make_error_response("INVALID_ANSWER", status_code=401, message="Security answer is incorrect.")
    except Exception as e:
        return make_error_response("SERVER_ERROR", status_code=500, message=str(e))


@auth_bp.route("/logout", methods=["GET", "POST"])
@login_required
def logout():
    """Ends session. GET → redirect (HTML). POST → JSON (programmatic)."""
    try:
        logout_user()

        # Honor ?next=... if provided and safe
        next_url = request.args.get("next")
        if next_url and next_url.startswith("/"):
            safe_next = next_url
        else:
            safe_next = url_for("dashboard_bp.index")

        # HTML path: redirect so the browser fully reloads the header
        wants_html = (
            request.method == "GET" or
            request.accept_mimetypes.get("text/html", 0) >= request.accept_mimetypes.get("application/json", 0)
        )
        if wants_html and not request.is_json:
            return redirect(safe_next)

        # Programmatic path (beacon/fetch)
        return make_success_response(data={"message": "Logout successful."}, status_code=200)
    except Exception as e:
        return make_error_response(code="LOGOUT_FAILED", status_code=500, message=str(e))
