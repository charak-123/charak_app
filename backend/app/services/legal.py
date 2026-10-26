"""
Consent against published document versions (``legal_documents`` and
``consents``, migration 0024).

The current version of each document is the latest one published. A person
has consented when ``consents`` holds a row for that exact version. Rows are
append-only: the evidence that consent was given is never edited, and it
survives account erasure.

Older app builds still post to ``/consents`` with a version string of their
own; those rows count as long as the string matches a published version.
"""
from __future__ import annotations

from typing import Iterable, Optional

from ..db import supabase
from ..errors import AppError

# What each kind of user must have accepted before booking (patients) or
# taking bookings (doctors). Telemedicine consent is asked for at a patient's
# first online consultation, not at sign-up.
REQUIRED = {
    "patient": ("tos", "privacy"),
    "doctor": ("tos", "privacy"),
}
ONLINE_EXTRA = ("telemedicine",)


def current_documents(role: Optional[str] = None) -> dict[str, dict]:
    """The latest published version of each document type, for ``role``."""
    rows = (
        supabase.table("legal_documents")
        .select("type, version, title, url, audience, material, published_at")
        .order("published_at", desc=True)
        .execute().data or []
    )
    current: dict[str, dict] = {}
    for row in rows:
        if role and role not in (row.get("audience") or []):
            continue
        current.setdefault(row["type"], row)
    return current


def accepted_versions(user_id: str) -> set[tuple[str, str]]:
    rows = (
        supabase.table("consents").select("type, version")
        .eq("user_id", user_id).execute().data or []
    )
    return {(r["type"], r["version"]) for r in rows}


def missing(user_id: str, role: str, types: Iterable[str]) -> list[dict]:
    """The documents of ``types`` whose current version ``user_id`` hasn't accepted."""
    docs = current_documents(role)
    accepted = accepted_versions(user_id)
    return [
        _public(docs[t]) for t in types
        if t in docs and (t, docs[t]["version"]) not in accepted
    ]


def require(user_id: str, role: str, types: Iterable[str]) -> None:
    """Refuse with 428 listing what is still to be accepted. The apps answer a
    428 with the consent sheet and then retry."""
    outstanding = missing(user_id, role, types)
    if outstanding:
        raise AppError(
            "Please review and accept the latest terms to continue.", 428,
            consent_required=outstanding,
        )


def record(user_id: str, role: str, items: list[dict], *, method: str,
           ip: Optional[str] = None, booking_id: Optional[str] = None,
           app_version: Optional[str] = None) -> list[dict]:
    """
    Record acceptance of each ``{"type", "version"}`` in ``items``. Every
    version must be the current published one, so a stale screen can't record
    consent to text the person was never shown. Accepting the same version
    again records nothing new.
    """
    docs = current_documents(role)
    accepted = accepted_versions(user_id)
    rows = []
    for item in items:
        doc = docs.get(item.get("type"))
        if doc is None:
            raise AppError(f"Unknown document '{item.get('type')}'", 400)
        if item.get("version") != doc["version"]:
            raise AppError(
                f"The {doc['title']} has been updated. Please review the latest version.",
                409, current=_public(doc),
            )
        if (doc["type"], doc["version"]) in accepted:
            continue
        rows.append({
            "user_id": user_id,
            "role": role,
            "type": doc["type"],
            "version": doc["version"],
            "method": method,
            "booking_id": booking_id,
            "app_version": app_version,
            "ip": ip,
        })
    if rows:
        supabase.table("consents").insert(rows).execute()
    return rows


def record_booking_policy(user_id: str, policy: dict, booking_id: str,
                          ip: Optional[str] = None) -> None:
    """The cancellation policy the patient ticked on the confirm screen, kept
    with the booking it was accepted for."""
    supabase.table("consents").insert({
        "user_id": user_id,
        "role": "patient",
        "type": "booking_policy",
        "version": f"{policy['channel']}:{policy['version']}",
        "method": "booking_confirmation",
        "booking_id": booking_id,
        "ip": ip,
    }).execute()


def _public(doc: dict) -> dict:
    return {k: doc.get(k) for k in ("type", "version", "title", "url", "material")}
