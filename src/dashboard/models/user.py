import datetime

import flask_bcrypt
from flask_login import UserMixin

from dashboard import db, login_manager

class InvitationKey(db.Model):
    __tablename__ = 'Invitation_Keys'

    key_id = db.Column(db.Integer, primary_key=True)
    key_value = db.Column(db.String(64), unique=True, nullable=False)
    is_used = db.Column(db.Integer, nullable=False, default=0)
    created_by_user_id = db.Column(db.Integer, db.ForeignKey('Users.user_id'), nullable=False)
    used_by_user_id = db.Column(db.Integer, db.ForeignKey('Users.user_id'), nullable=True)
    created_at = db.Column(db.TIMESTAMP, default=datetime.datetime.now)
    used_at = db.Column(db.TIMESTAMP, nullable=True)

    creator = db.relationship('User', foreign_keys=[created_by_user_id], backref='created_keys')
    used_by_user = db.relationship('User', foreign_keys=[used_by_user_id], backref='used_key')

    def __repr__(self):
        return f'<InvitationKey {self.key_value} (Used: {bool(self.is_used)})>'

class User(db.Model, UserMixin):
    __tablename__ = 'Users'

    user_id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(32), unique=True)
    email = db.Column(db.String(255), unique=True, nullable=False)
    password = db.Column(db.String(255), nullable=False)
    is_admin = db.Column(db.Integer)
    first_name = db.Column(db.String(64), nullable=False)
    last_name = db.Column(db.String(64), nullable=False)
    ts_id = db.Column(db.Integer)
    color_code = db.Column(db.String(45))
    is_deleted = db.Column(db.Integer, default=0)
    is_invited = db.Column(db.Integer, default=0)
    invitation_key_id = db.Column(db.Integer, db.ForeignKey('Invitation_Keys.key_id'), nullable=True)
    security_question = db.Column(db.String(255), nullable=True)
    security_answer_hash = db.Column(db.String(255), nullable=True)

    def get_id(self):
        """Overrides the default UserMixin method to use `user_id`.

        Needed as flask_login expects an `id` column on default."""
        return str(self.user_id)

    def __repr__(self):
       """Useful for debugging with Flask."""
       return f'<User {self.email}>'

    def set_password(self, bcrypt: flask_bcrypt.Bcrypt, password: str) -> None:
        """Hashes plaintext password to prepare for storage in db."""
        self.password = bcrypt.generate_password_hash(password).decode('utf-8')

    def check_password(self, bcrypt: flask_bcrypt.Bcrypt, password: str) -> bool:
        """Ensures a provided password matches the hashed version in database.

        Note that flask_bcrypt.Bcrypt handles salting under the hood.
        """
        return bcrypt.check_password_hash(self.password, password)

    def set_security_answer(self, bcrypt, answer):
        """Hashes and stores the security answer."""
        self.security_answer_hash = bcrypt.generate_password_hash(answer).decode('utf-8')

    def check_security_answer(self, bcrypt, answer):
        """Checks the provided answer against the hash."""
        if not self.security_answer_hash:
            return False
        return bcrypt.check_password_hash(self.security_answer_hash, answer)

@login_manager.user_loader
def load_user(user_id):
    """Tell Flask-Login how to load a user from the database.

    This function is called automatically on every request if a user is
    logged in. It uses the user_id stored in the session cookie to
    retrieve the corresponding user object from the database.

    Args:
        user_id (str): The user's unique ID from the session cookie.

    Returns:
        User or None: The user object if found, otherwise None.
    """
    return User.query.get(int(user_id))
