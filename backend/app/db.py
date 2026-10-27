from typing import Optional

import httpx
from supabase import Client, create_client
from supabase.lib.client_options import SyncClientOptions

from .config import SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

# Retry failed *connections* (DNS lookup or TCP connect) a couple of times. A
# flaky resolver or a Wi-Fi blip otherwise turns into a 500 on whatever request
# was unlucky, e.g. sign-in. httpx only retries when no request bytes were sent,
# so a write is never applied twice.
#
# HTTP/1.1 with a pool, not one shared HTTP/2 connection: every request
# thread in a process shared that single connection, and the synchronous
# HTTP/2 client serialises a lot of the work on it, so one slow caller (the
# every-minute tick) held up everyone else, admin pages included.
_http = httpx.Client(
    transport=httpx.HTTPTransport(
        retries=2,
        limits=httpx.Limits(max_connections=40, max_keepalive_connections=20, keepalive_expiry=30),
    ),
    timeout=httpx.Timeout(30.0, connect=5.0),
    follow_redirects=True,
)

# Service-role client — bypasses RLS for backend-controlled operations
supabase: Client = create_client(
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, options=SyncClientOptions(httpx_client=_http)
)


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
