from typing import Any


class AppError(Exception):
    """Domain error carrying an i18n key + params; rendered to the user by the API layer."""

    def __init__(self, code: str, status: int = 400, **params: Any):
        super().__init__(code)
        self.code = code
        self.status = status
        self.params = params
