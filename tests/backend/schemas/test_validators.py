""""Only test custom code for pydantic."""

import pytest

from dashboard.schemas.auth_schemas import proper_password_complexity


@pytest.mark.parametrize("password", [
    "aComplexPassword1!",
    "Another$Pass123",
    "Test@1234",
    "NOLOWERCASE1!",
])
def test_proper_password_complexity_valid(password):
    assert proper_password_complexity(password) == password

@pytest.mark.parametrize("password", [
    "short",          # Too short
    "nouppercase1!",  # No uppercase
    "NoNumber!",      # No number
    "NoSpecial1",     # No special character
])
def test_proper_password_complexity_invalid(password):
    with pytest.raises(ValueError):
        proper_password_complexity(password)