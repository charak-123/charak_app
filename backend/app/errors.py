from fastapi import Request
from fastapi.responses import JSONResponse


class AppError(Exception):
    def __init__(self, message: str, status_code: int = 400):
        self.message = message
        self.status_code = status_code
        super().__init__(message)


async def app_error_handler(request: Request, exc: AppError):
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": exc.message},
    )


# PostgREST SQLSTATEs worth translating rather than crashing on.
#
# 22P02 is the one that reaches users: FastAPI declares path ids as `str`, so
# anything at all can arrive as a booking or doctor id and go straight into a
# query against a uuid column. Postgres rejects it, supabase-py raises APIError,
# and nothing caught it — so every `{id}` route answered a malformed id with a
# 500. A resource whose id cannot even be parsed does not exist, so 404 is both
# the honest answer and the one that leaks nothing about the column type.
#
# The mocked suite cannot see any of this: a MagicMock accepts "not-a-uuid" as
# happily as a real id and returns whatever the test told it to.
_SQLSTATE_STATUS = {
    "22P02": (404, "Not found"),            # invalid input syntax (bad uuid)
    "23503": (409, "Referenced record does not exist"),   # foreign key violation
    "23505": (409, "Already exists"),       # unique violation
    "22003": (400, "Value out of range"),   # numeric overflow
}


async def db_error_handler(request: Request, exc: Exception):
    """
    Last line of defence for database errors that reach the transport.

    Anything unrecognised is a 500 with a generic body: the driver's message can
    name columns, constraints and values, and that is not something to hand to a
    caller. The detail goes to the log instead.
    """
    code = getattr(exc, "code", None)
    status, message = _SQLSTATE_STATUS.get(code, (500, "Database error"))
    if status >= 500:
        print(f"[db error] {request.method} {request.url.path} — {code} {exc!r}")
    return JSONResponse(status_code=status, content={"error": message})
