import re
from typing_extensions import Annotated

from pydantic import BaseModel, EmailStr, Field, AfterValidator, ConfigDict


def proper_password_complexity(password: str) -> str:
    """Checks if the password string meets complexity requirements.

    Plaintext password verified to match policy but not stored for this function.
    """
    PASSWORD_POLICY = r"^(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*]).{8,}$"
    if re.match(PASSWORD_POLICY, password) is None:
        raise ValueError("Password must be 8+ chars, with 1 uppercase, 1 digit, 1 special char.")
    return password


PasswordType = Annotated[
    str,
    AfterValidator(proper_password_complexity)
]


class LoginSchema(BaseModel):
    """Data model for a login request."""
    model_config = ConfigDict(extra="forbid")

    email: EmailStr
    password: Annotated[str, Field(min_length=8)]


class SignupSchema(BaseModel):
    """Data model for a new user registration."""
    model_config = ConfigDict(extra="forbid")

    email: EmailStr
    password: PasswordType
    first_name: Annotated[str, Field(min_length=1, max_length=50)]
    last_name: Annotated[str, Field(min_length=1, max_length=50)]
    invitation_key: Annotated[str, Field(min_length=1)]
    security_question: str = Field(..., min_length=5)
    security_answer: str = Field(..., min_length=1)


class ResetRequestSchema(BaseModel):
    email: EmailStr


class ResetConfirmSchema(BaseModel):
    email: EmailStr
    security_answer: str
    new_password: PasswordType
