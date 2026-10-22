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
by something else. For an identifier only known once the body is parsed (the
email in a login request), call `enforce(...)` from inside the handler.
"""
from __future__ import annotations

import ipaddress
from datetime import datetime, timedelta, timezone
from typing import Callable, Optional

from fastapi import Depends, Request

from ..config import TRUSTED_PROXY_HOPS
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


def _bucket(ip: str) -> str:
    """
    The unit a limit is counted against. IPv4: the address. IPv6: its /64 —
    one subscriber is handed a whole /64 and can rotate through it freely, so
    counting single v6 addresses would be no limit at all.
    """
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return ip
    if addr.version == 6:
        return str(ipaddress.ip_network(f"{addr}/64", strict=False))
    return str(addr)


def client_ip(request: Request) -> str:
    """
    The caller's address as seen by our own edge.

    Cloud Run sits behind Google's front end, which *appends* the address it
    saw to X-Forwarded-For. Everything to the left of that is whatever the
    client sent, so the first entry is attacker-controlled: reading it let one
    machine rotate a fake address per request and never hit a limit. The
    trustworthy entry is TRUSTED_PROXY_HOPS from the right — 1 for Cloud Run
    serving its run.app URL directly; 2 with an external HTTPS load balancer
    in front, which appends its own address after the client's.
    """
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        parts = [p.strip() for p in forwarded.split(",") if p.strip()]
        if parts:
            return _bucket(parts[-min(TRUSTED_PROXY_HOPS, len(parts))])
    return _bucket(request.client.host) if request.client else "unknown"


def enforce(scope: str, identifier: str, max_hits: int, window_seconds: int) -> None:
    """
    The limiter as a plain call, for identifiers only known inside a handler
    (e.g. the email in a login body). Same counting rules as `rate_limiter`.
    """
    if hits_in_window(scope, identifier, window_seconds) >= max_hits:
        record_hit(scope, identifier)
        raise AppError("Too many attempts. Please try again later.", 429)
    record_hit(scope, identifier)


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
        identifier = key(request) if key else client_ip(request)
        enforce(scope, identifier, max_hits, window_seconds)

    return Depends(_dep)
