from datetime import datetime, timezone

import jwt
from fastapi import Depends, Header, HTTPException
from jwt import InvalidTokenError
from postgrest.exceptions import APIError

from .config import JWT_SECRET
from .db import supabase

_REVOCABLE_TABLES = {"patient": "users", "doctor": "doctors"}


def _session_revoked(role: str, user_id: str, issued_at) -> bool:
    """
    True if `issued_at` (the token's `iat`, a unix timestamp) is older than the
    account's `sessions_revoked_at` — i.e. this specific token was minted
    before ops force-expired that account's sessions (lost/stolen phone).

    An ops token is revoked once its admin_users row is gone: removing an
    admin has to end their access now, not when their 12-hour token expires.
    """
    if role == "ops":
        try:
            admin = supabase.table("admin_users").select("id").eq("id", user_id).execute().data
        except APIError:   # a sub that is not even a uuid
            return True
        return not admin

    table = _REVOCABLE_TABLES.get(role)
    if not table or issued_at is None:
        return False
    rows = (
        supabase.table(table)
        .select("sessions_revoked_at")
        .eq("id", user_id)
        .execute()
        .data
    )
    revoked_at = rows[0].get("sessions_revoked_at") if rows else None
    if not revoked_at:
        return False
    revoked_dt = datetime.fromisoformat(str(revoked_at).replace("Z", "+00:00"))
    issued_dt = datetime.fromtimestamp(issued_at, tz=timezone.utc)
    # `iat` is whole seconds; the revocation stamp has microseconds. Without
    # truncating, a sign-in in the same second as a revocation (deleting an
    # account and signing straight back in) minted a token that was dead on
    # arrival.
    return issued_dt < revoked_dt.replace(microsecond=0)


def get_current_user(authorization: str = Header(...)) -> dict:
    try:
        token = authorization.removeprefix("Bearer ")
        payload = jwt.decode(token, JWT_SECRET, algorithms=["HS256"])
    except InvalidTokenError:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    if _session_revoked(payload.get("role"), payload.get("sub"), payload.get("iat")):
        raise HTTPException(status_code=401, detail="Session revoked. Please sign in again.")

    return payload  # {"sub": id, "role": "patient"|"doctor"|"ops"}


def require_doctor(user: dict = Depends(get_current_user)) -> dict:
    if user.get("role") != "doctor":
        raise HTTPException(status_code=403, detail="Doctor access required")
    return user


def require_patient(user: dict = Depends(get_current_user)) -> dict:
    if user.get("role") != "patient":
        raise HTTPException(status_code=403, detail="Patient access required")
    return user


def require_ops(user: dict = Depends(get_current_user)) -> dict:
    if user.get("role") != "ops":
        raise HTTPException(status_code=403, detail="Ops access required")
    return user
