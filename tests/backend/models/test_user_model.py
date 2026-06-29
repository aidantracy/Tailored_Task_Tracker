from dashboard.models import User

def test_set_password(bcrypt):
    """
    GIVEN a User model instance
    WHEN the set_password() method is called with a password
    THEN check that the password attribute is set correctly and is not plaintext.
    """
    user = User(email="test@example.com")
    password = "aComplexPassword123!"
    user.set_password(bcrypt, password)

    assert user.password is not None
    assert user.password != password
    assert bcrypt.check_password_hash(user.password, password)

def test_check_password(bcrypt):
    """
    GIVEN a User model instance with a hashed password
    WHEN the check_password() method is called
    THEN check that it returns True for the correct password and False for an incorrect one.
    """
    user = User(email="test@example.com")
    correct_password = "aComplexPassword123!"
    incorrect_password = "wrongPassword!"
    user.set_password(bcrypt, correct_password)

    assert user.check_password(bcrypt, correct_password) is True
    assert user.check_password(bcrypt, incorrect_password) is False

def test_get_id():
    """
    GIVEN a User model instance with a user_id
    WHEN the get_id() method is called
    THEN check that it returns the user_id as a string.
    """
    user = User(user_id=123, email="test@example.com")
    assert user.get_id() == "123"