"""
Generic sliding-window rate limiter, backed by the `rate_limit_hits` table
(migration 0018).

Why a table and not an in-process counter: the API runs as two uvicorn workers
per container (see Dockerfile) and up to three container instances on Cloud
Run (see the deploy command in docs/runbooks/backend_go_live.md). An
in-process dict would give each worker/instance its own budget, so the real
limit would be (workers × instances) times what it looks like — exactly the
bug otp_store.py's own docstring already explains for OTP sends. Rows in a
shared table are visible to every worker and instance immediately.

Usage, as a FastAPI dependency:

    @router.post("/login")
    def admin_login(
        body: AdminLoginRequest,
        _rl: None = Depends(rate_limiter("admin-login", 5, 900)),
    ):
        ...

`identifier` defaults to the caller's IP; pass a custom `key` function to limit
by something else (e.g. the email in the request body) instead or as well.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Callable, Optional

from fastapi import Depends, Request

from ..db import supabase
from ..errors import AppError


def _now() -> datetime:
    return datetime.now(timezone.utc)


def hits_in_window(scope: str, identifier: str, window_seconds: int) -> int:
    since = (_now() - timedelta(seconds=window_seconds)).isoformat()
    rows = (
        supabase.table("rate_limit_hits")
        .select("id")
        .eq("scope", scope)
        .eq("identifier", identifier)
        .gte("created_at", since)
        .execute()
        .data
        or []
    )
    return len(rows)


def record_hit(scope: str, identifier: str) -> None:
    supabase.table("rate_limit_hits").insert({
        "scope": scope,
        "identifier": identifier,
    }).execute()


def _client_ip(request: Request) -> str:
    # Cloud Run (and Fly) sit behind a proxy; the real client address is the
    # first hop in X-Forwarded-For, not request.client (that's the proxy).
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def rate_limiter(
    scope: str,
    max_hits: int,
    window_seconds: int,
    key: Optional[Callable[[Request], str]] = None,
):
    """
    Build a FastAPI dependency that 429s once `max_hits` requests with the same
    identifier land inside `window_seconds`. Counts the *rejected* request too
    (a caller hammering the endpoint keeps resetting its own cooldown instead
    of ever getting back in sooner by stopping).
    """
    def _dep(request: Request) -> None:
        identifier = key(request) if key else _client_ip(request)
        if hits_in_window(scope, identifier, window_seconds) >= max_hits:
            record_hit(scope, identifier)
            raise AppError("Too many attempts. Please try again later.", 429)
        record_hit(scope, identifier)

    return Depends(_dep)
