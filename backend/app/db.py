from typing import Optional

from supabase import Client, create_client

from .config import SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

# Service-role client — bypasses RLS for backend-controlled operations
supabase: Client = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)


def fetch_one(query) -> Optional[dict]:
    """
    Run a query expecting at most one row. Returns the row, or None if there is none.

    Use this instead of ``.single().execute()`` for any lookup that can legitimately
    miss. PostgREST's ``single()`` raises PGRST116 ("Cannot coerce the result to a
    single JSON object") on zero rows, which surfaced as an unhandled 500 and made
    every ``if not result.data: raise AppError(..., 404)`` check downstream
    unreachable. ``maybe_single()`` is the right primitive, but this client returns
    ``None`` for the whole response object rather than a response with ``data=None``,
    so the ``.data`` access needs guarding — that guard lives here, once.
    """
    result = query.maybe_single().execute()
    return result.data if result else None
