from flask import current_app
from pymysql import IntegrityError
from sqlalchemy.exc import SQLAlchemyError
import datetime

from dashboard import db, bcrypt
from ..models import User, InvitationKey
from ..schemas import SignupSchema, LoginSchema
from ..schemas.auth_schemas import ResetConfirmSchema
from ..utils import (
    UserAlreadyExistsError,
    DatabaseCommitError,
    UserDoesNotExistError,
    IncorrectPassword,
    DatabaseReadError,
    InvalidInvitationKeyError,
)


def create_user(user_data: SignupSchema) -> User:
    """
    Core business logic for creating a new user.

    Args:
        SignupSchema object that is valid according to the schema

    Returns:
        User object

    Raises:
        UserAlreadyExistsError
        DatabaseCommitError
        DatabaseReadError
        InvalidInvitationKeyError
    """
    try:
        # 1. Check if user already exists
        user_exists = User.query.filter_by(email=user_data.email).first()
        if user_exists:
            raise UserAlreadyExistsError(f"User with email '{user_data.email}' already exists.")

        # 2. Validate the invitation key
        key = InvitationKey.query.filter_by(
            key_value=user_data.invitation_key,
            is_used=0
        ).first()

        if not key:
            raise InvalidInvitationKeyError("Invalid or already used invitation key.")

    except SQLAlchemyError as e:
        db.session.rollback()
        current_app.logger.error(f"Error checking user/key: {e}", exc_info=True)
        raise DatabaseReadError("Could not create user due to a database read error.")


    # 3. Create new user and link the key
    new_user = User(
        email=user_data.email,
        first_name=user_data.first_name,
        last_name=user_data.last_name,
        invitation_key_id=key.key_id,  # Link the user to the key
        security_question=user_data.security_question,
        is_admin=0
    )

    # Set Password and Security Answer Hash
    new_user.set_password(bcrypt, user_data.password)
    new_user.set_security_answer(bcrypt, user_data.security_answer)

    # 4. Mark key as used
    key.is_used = 1
    key.used_at = datetime.datetime.now()

    try:
        db.session.add(new_user)
        db.session.add(key)      # Add the modified key to the session
        db.session.commit()

        # Now link the key.used_by_user_id back to the new user
        key.used_by_user_id = new_user.user_id
        db.session.add(key)
        db.session.commit()

        return new_user

    except IntegrityError as e:
        db.session.rollback()
        current_app.logger.error(f"Error committing new user {new_user.email}: {e}", exc_info=True)
        raise DatabaseCommitError("Could not create user due to a database write error.")
    except SQLAlchemyError as e:
        db.session.rollback()
        current_app.logger.error(f"Error committing new user or key {new_user.email}: {e}", exc_info=True)
        raise DatabaseCommitError("Could not create user due to a database write error.")


def login_user(user_data: LoginSchema) -> User:
    """
    Core business logic for logging in recurring users.

    Args:
        LoginSchema object that is valid according to the schema

    Returns:
        User object

    Raises:
        DatabaseReadError
        IncorrectPassword
        UserDoesNotExistError
    """
    try:
        returning_user = User.query.filter_by(email=user_data.email).first()

    except SQLAlchemyError as e:
        db.session.rollback()
        current_app.logger.error(f"Error reading from database for user {user_data.email}: {e}", exc_info=True)
        raise DatabaseReadError("Could not log in due to a database error.")


    if returning_user is None:
        raise UserDoesNotExistError(f"User with email '{user_data.email}' does not exist.")

    if returning_user.is_deleted:
        raise PermissionError(f"Account for '{user_data.email}' has been deleted. Please contact an admin.")

    if not returning_user.check_password(bcrypt, user_data.password):
        raise IncorrectPassword(f"Password for User with email '{user_data.email}' is incorrect.")

    return returning_user


def get_security_question(email: str) -> str:
    """
    Retrieves the security question for a user.
    """
    try:
        user = User.query.filter_by(email=email).first()
        if not user:
            raise UserDoesNotExistError("User not found.")

        if not user.security_question:
            # Fallback if legacy user has no question set
            raise UserDoesNotExistError("No security question set for this account.")

        return user.security_question
    except SQLAlchemyError as e:
        current_app.logger.error(f"DB Error getting question: {e}")
        raise DatabaseReadError("Database error.")


def reset_password(data: ResetConfirmSchema) -> User:
    """
    Verifies security answer and resets password.
    """
    try:
        user = User.query.filter_by(email=data.email).first()
        if not user:
            raise UserDoesNotExistError("User not found.")

        # Verify Security Answer
        # Note: We reuse IncorrectPassword exception for incorrect security answer
        # to keep error handling consistent in the controller
        if not user.check_security_answer(bcrypt, data.security_answer):
            raise IncorrectPassword("Incorrect security answer.")

        # Set New Password
        user.set_password(bcrypt, data.new_password)
        db.session.commit()

        return user

    except SQLAlchemyError as e:
        db.session.rollback()
        current_app.logger.error(f"DB Error resetting password: {e}")
        raise DatabaseCommitError("Could not reset password.")