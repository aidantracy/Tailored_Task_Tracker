"""Custom exceptions for the application's service layer."""

class AppServiceError(Exception):
    """Base class for service-layer exceptions."""

class UserAlreadyExistsError(AppServiceError):
    pass

class UserDoesNotExistError(AppServiceError):
    pass

class IncorrectPassword(AppServiceError):
    pass

class DatabaseCommitError(AppServiceError):
    pass

class DatabaseReadError(AppServiceError):
    pass

class InvalidInvitationKeyError(AppServiceError):
    """Raised when an invitation key is invalid, used, or not found."""