"""
Consent against published document versions (``legal_documents`` and
``consents``, migration 0024).

The current version of each document is the latest approved one. A person
has consented when ``consents`` holds a row for that exact version. Rows are
append-only: the evidence that consent was given is never edited, and it
survives account erasure. Since 0030 each version carries its full text, which
the apps show in full and people sign; the row records the text's fingerprint.

Older app builds still post to ``/consents`` with a version string of their
own; those rows count as long as the string matches a published version.
"""
from __future__ import annotations

from typing import Iterable, Optional

from ..db import supabase
from ..errors import AppError

# What each kind of user must have signed before booking (patients) or
# taking bookings (doctors), in the order the apps present them. Telemedicine
# consent is asked for at a patient's first online consultation, not at
# sign-up. A type with no approved version yet is simply not asked for.
REQUIRED = {
    "patient": ("tos", "privacy", "refund_policy"),
    "doctor": ("practitioner_terms", "privacy", "refund_policy"),
}
ONLINE_EXTRA = ("telemedicine",)

# Everything the apps' Legal screen can list (telemedicine only for
# patients, by its audience).
LISTED = ("tos", "practitioner_terms", "privacy", "refund_policy", "telemedicine")



def listing_order(role: str) -> tuple[str, ...]:
    """What ``role`` signs first, in signing order, then anything else listed."""
    return REQUIRED[role] + tuple(t for t in LISTED if t not in REQUIRED[role])


_LIST_COLUMNS = ("type, version, title, url, audience, material, published_at, summary, "
                 "highlights, sha256")


def current_documents(role: Optional[str] = None) -> dict[str, dict]:
    """The latest approved version of each document type, for ``role``."""
    # Only an approved version (the legal review gate, migration 0029) is
    # ever current: a document added but not yet reviewed isn't shown.
    rows = (
        supabase.table("legal_documents")
        .select(f"{_LIST_COLUMNS}, legal_document_approvals!inner(id)")
        .order("published_at", desc=True)
        .execute().data or []
    )
    current: dict[str, dict] = {}
    for row in rows:
        row.pop("legal_document_approvals", None)
        current.setdefault(row["type"], row)
    # The latest version decides who it is for: when the Terms of Use became
    # patients-only, doctors stopped being asked for them, rather than being
    # held to the older version that still named them.
    return {t: d for t, d in current.items() if not role or role in (d.get("audience") or [])}


def document(doc_type: str, version: Optional[str] = None) -> dict:
    """One approved version with its full text: the current one, or ``version``
    (the one someone signed, though it has since been replaced)."""
    query = (
        supabase.table("legal_documents")
        .select(f"{_LIST_COLUMNS}, body, legal_document_approvals!inner(id)")
        .eq("type", doc_type)
    )
    if version:
        query = query.eq("version", version)
    rows = query.order("published_at", desc=True).limit(1).execute().data or []
    if not rows:
        raise AppError("No published version of that document", 404)
    row = rows[0]
    row.pop("legal_document_approvals", None)
    return {**_public(row), "body": row.get("body")}


def accepted_versions(user_id: str) -> set[tuple[str, str]]:
    return set(acceptances(user_id))


def acceptances(user_id: str) -> dict[tuple[str, str], str]:
    """When ``user_id`` first accepted each (type, version)."""
    rows = (
        supabase.table("consents").select("type, version, accepted_at")
        .eq("user_id", user_id).order("accepted_at").execute().data or []
    )
    out: dict[tuple[str, str], str] = {}
    for r in rows:
        out.setdefault((r["type"], r["version"]), r.get("accepted_at"))
    return out


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
            # The fingerprint of the exact text they were shown and signed.
            "document_sha256": doc.get("sha256"),
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
    out = {k: doc.get(k) for k in ("type", "version", "title", "url", "material", "summary",
                                   "published_at", "sha256")}
    out["highlights"] = doc.get("highlights") or []
    # Versions from before 0030 have no text of their own: the apps open the
    # web page instead.
    out["has_text"] = bool(doc.get("sha256"))
    return out
