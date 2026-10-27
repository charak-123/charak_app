"""
Admin roles (migration 0029, plan §3.13). Each admin account has one role;
each role a fixed set of permissions; each admin endpoint names the one it
needs (deps.require_permission).

    support    sees bookings, cases and queues; reveals a patient's phone
               (audited) to call them
    ops_lead   support, plus deciding: incidents, reviews, refunds, doctor
               verification and suspension, overrides, prescription access
    finance    money: refunds, payouts, adjustments, pricing history, metrics
    admin      everything, including approving policies and legal documents

A token from before roles existed carries no role and gets the least
(support): signing in again issues one with the account's role.
"""
from __future__ import annotations

ROLES = ("support", "ops_lead", "finance", "admin")

_SUPPORT = {
    "bookings.read", "complaints.read", "complaints.update", "incidents.read", "reviews.read",
    "visits.read", "doctors.read", "patient_phone.reveal", "metrics.read",
}
_OPS_LEAD = _SUPPORT | {
    "incidents.decide", "reviews.moderate", "refunds.manage", "doctors.verify", "doctors.suspend",
    "sessions.revoke", "bookings.override", "prescriptions.break_glass", "procedure_bills.review",
    "deletions.fulfil", "audit.read", "system.read", "system.retry",
}
_FINANCE = {
    "bookings.read", "doctors.read", "metrics.read", "refunds.manage", "payouts.read",
    "payouts.manage", "pricing.read", "audit.read",
}

PERMISSIONS: dict[str, frozenset[str]] = {
    "support": frozenset(_SUPPORT),
    "ops_lead": frozenset(_OPS_LEAD | {"pricing.read", "payouts.read"}),
    "finance": frozenset(_FINANCE),
    "admin": frozenset(_OPS_LEAD | _FINANCE | {"policies.approve", "storage.manage", "admins.manage"}),
}


def role_of(user: dict) -> str:
    role = user.get("admin_role")
    return role if role in PERMISSIONS else "support"


def can(user: dict, permission: str) -> bool:
    return user.get("role") == "ops" and permission in PERMISSIONS[role_of(user)]


def permissions_of(user: dict) -> list[str]:
    return sorted(PERMISSIONS[role_of(user)]) if user.get("role") == "ops" else []
