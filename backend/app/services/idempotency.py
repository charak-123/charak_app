"""
HTTP idempotency keys, the way Stripe does them.

A client that sends ``Idempotency-Key: <uuid>`` on a write can retry it as
often as it likes (after a timeout, a dropped connection, an app killed
mid-request) and the server acts once:

* first request with a key: claimed, run, and its response stored;
* same key again, after it finished: the stored response is returned with
  ``Idempotent-Replayed: true``, and nothing runs;
* same key while the first is still running: 409, try again shortly;
* same key with a different request (method, path, query or body): 422. A key
  belongs to one request.

Responses are stored for 2xx and 4xx, because those are the answer. A 5xx, a
401/403 (session trouble), a 429 or a redirect is not stored, so the retry (or
the redirected request) runs. A trailing slash doesn't make a different
request: '/addresses' redirects to '/addresses/', and both are one request.

Keys are scoped to the signed-in user, kept 24 hours (purged with the
rate-limit hits), and only apply to POST/PUT/PATCH/DELETE. Requests without a
key behave exactly as before, so older app builds are unaffected.
"""
from __future__ import annotations

import hashlib
import json
import logging
import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

import jwt
from postgrest.exceptions import APIError
from starlette.concurrency import run_in_threadpool
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from ..config import JWT_SECRET
from ..db import fetch_one, supabase

logger = logging.getLogger(__name__)

METHODS = {"POST", "PUT", "PATCH", "DELETE"}
# Callers that are not a signed-in user, or that have their own deduplication
# (the webhook inbox), are left alone.
SKIP_PREFIXES = ("/payments/webhook", "/admin/login", "/auth/", "/maintenance/")
KEY_PATTERN = re.compile(r"^[A-Za-z0-9_\-]{8,128}$")
# A claim this old with no response means the request that made it died.
IN_FLIGHT = timedelta(seconds=60)
NOT_STORED = {401, 403, 429}


@dataclass
class Claim:
    kind: str                       # new | replay | in_flight | mismatch
    status_code: Optional[int] = None
    body: Any = None


def _now() -> datetime:
    return datetime.now(timezone.utc)


def request_hash(method: str, path: str, query: str, body: bytes) -> str:
    digest = hashlib.sha256()
    for part in (method.encode(), path.encode(), query.encode(), body):
        digest.update(len(part).to_bytes(8, "big"))
        digest.update(part)
    return digest.hexdigest()


def user_id_from(request: Request) -> Optional[str]:
    """The session's user id, or None. Only decoded, not authorised: the
    route's own dependency still decides whether the session is valid."""
    header = request.headers.get("authorization", "")
    if not header.lower().startswith("bearer "):
        return None
    try:
        payload = jwt.decode(header[7:], JWT_SECRET, algorithms=["HS256"])
    except jwt.InvalidTokenError:
        return None
    sub = payload.get("sub")
    return str(sub) if sub else None


def claim(user_id: str, key: str, method: str, path: str, req_hash: str) -> Claim:
    try:
        supabase.table("idempotency_keys").insert({
            "user_id": user_id, "key": key, "method": method,
            "path": path, "request_hash": req_hash,
        }).execute()
        return Claim("new")
    except APIError as exc:
        if getattr(exc, "code", None) != "23505":
            raise

    row = fetch_one(
        supabase.table("idempotency_keys").select("*")
        .eq("user_id", user_id).eq("key", key)
    )
    if row is None:                       # purged between the two calls
        return claim(user_id, key, method, path, req_hash)
    if row["request_hash"] != req_hash:
        return Claim("mismatch")
    if row.get("completed_at"):
        return Claim("replay", row.get("status_code"), row.get("response_body"))

    created = datetime.fromisoformat(str(row["created_at"]).replace("Z", "+00:00"))
    if _now() - created < IN_FLIGHT:
        return Claim("in_flight")
    # The request that claimed it never finished. Take the claim over, but only
    # if nobody else just did.
    taken = (
        supabase.table("idempotency_keys").update({"created_at": _now().isoformat()})
        .eq("user_id", user_id).eq("key", key).eq("created_at", row["created_at"])
        .is_("completed_at", "null")
        .execute().data or []
    )
    return Claim("new") if taken else Claim("in_flight")


def complete(user_id: str, key: str, status_code: int, body: Any) -> None:
    supabase.table("idempotency_keys").update({
        "status_code": status_code,
        "response_body": body,
        "completed_at": _now().isoformat(),
    }).eq("user_id", user_id).eq("key", key).execute()


def release(user_id: str, key: str) -> None:
    """Forget an unfinished claim, so the retry runs."""
    supabase.table("idempotency_keys").delete() \
        .eq("user_id", user_id).eq("key", key).is_("completed_at", "null").execute()


class IdempotencyMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        key = request.headers.get("idempotency-key")
        path = request.url.path
        if not key or request.method not in METHODS or path.startswith(SKIP_PREFIXES):
            return await call_next(request)
        if not KEY_PATTERN.match(key):
            return JSONResponse(
                {"error": "Idempotency-Key must be 8–128 letters, digits, '-' or '_'."}, 400
            )
        user_id = user_id_from(request)
        if user_id is None:
            return await call_next(request)   # no session: the route refuses it anyway

        body = await request.body()
        path = path.rstrip("/") or "/"
        req_hash = request_hash(request.method, path, request.url.query, body)
        decision = await run_in_threadpool(claim, user_id, key, request.method, path, req_hash)

        if decision.kind == "replay":
            return JSONResponse(decision.body, decision.status_code or 200,
                                headers={"Idempotent-Replayed": "true"})
        if decision.kind == "mismatch":
            return JSONResponse(
                {"error": "This Idempotency-Key was already used for a different request."}, 422
            )
        if decision.kind == "in_flight":
            # Retry-After tells the app's client this is "still running, ask
            # again", not a conflict to show the user.
            return JSONResponse(
                {"error": "This request is already being processed. Try again in a moment."}, 409,
                headers={"Retry-After": "1"},
            )

        try:
            response = await call_next(request)
        except Exception:
            await run_in_threadpool(release, user_id, key)
            raise

        content = b"".join([chunk async for chunk in response.body_iterator])
        status = response.status_code
        if status >= 500 or status in NOT_STORED or 300 <= status < 400:
            await run_in_threadpool(release, user_id, key)
        else:
            try:
                stored = json.loads(content) if content else None
            except ValueError:
                stored = None
            try:
                await run_in_threadpool(complete, user_id, key, response.status_code, stored)
            except Exception as exc:          # noqa: BLE001 — the action already happened
                logger.error("could not store idempotent response %s: %r", key, exc)

        return Response(
            content=content,
            status_code=response.status_code,
            headers={k: v for k, v in response.headers.items() if k.lower() != "content-length"},
            media_type=response.media_type,
        )
