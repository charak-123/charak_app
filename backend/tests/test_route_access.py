"""
Every route's access rule, checked from the app itself (spec §23.3).

A new endpoint without a sign-in or cron check, or an admin endpoint that
only checks "is ops" instead of naming a permission, fails here rather than
in production. Public routes are listed by name, with why.
"""
from fastapi.routing import APIRoute

from app.deps import get_current_user, require_doctor, require_ops, require_patient
from app.main import app
from app.routers.maintenance import require_cron
from app.services.admin_roles import PERMISSIONS

# (method, path): why it's open.
PUBLIC = {
    ("GET", "/"): "liveness",
    ("GET", "/health"): "liveness",
    ("GET", "/healthz"): "liveness",
    ("GET", "/readyz"): "readiness (no secrets in its body)",
    ("GET", "/categories/"): "directory specialties",
    ("GET", "/doctors/search"): "the public directory",
    ("GET", "/doctors/{doctor_id}"): "a verified doctor's public profile",
    ("GET", "/doctors/{doctor_id}/slots"): "open times",
    ("GET", "/doctors/{doctor_id}/prices"): "published prices",
    ("GET", "/doctors/{doctor_id}/reviews"): "anonymous reviews",
    ("GET", "/doctors/{doctor_id}/service-area"): "is this address served",
    ("POST", "/payments/webhook"): "Razorpay, signature-verified in the handler",
    ("POST", "/admin/login"): "sign-in (rate-limited, TOTP)",
    ("GET", "/config/app"): "minimum app version, before sign-in",
    ("GET", "/legal/current"): "documents to show before sign-up",
    ("GET", "/legal/cancellation-policy"): "the policy shown before booking",
    ("GET", "/legal/documents/{doc_type}"): "the published text of a legal document, as on the website",
}
AUTH_PREFIXES = ("/auth/",)  # sign-in flows: OTP, Google, Firebase (rate-limited)

GUARDS = {get_current_user, require_doctor, require_patient, require_ops, require_cron}


def _calls(route) -> set:
    seen, stack = set(), list(route.dependant.dependencies)
    while stack:
        d = stack.pop()
        seen.add(d.call)
        stack.extend(d.dependencies)
    return seen


def _flatten(routes):
    """FastAPI keeps included routers lazily; their routes come from
    effective_candidates(), already carrying the full prefixed path."""
    for r in routes:
        if isinstance(r, APIRoute) or hasattr(r, "dependant"):
            yield r
        elif hasattr(r, "effective_candidates"):
            yield from _flatten(r.effective_candidates())


def _routes():
    found = list(_flatten(app.routes))
    assert len(found) > 150, f"only {len(found)} routes found: the walk is broken"
    for r in found:
        for m in set(r.methods or ()) - {"HEAD", "OPTIONS"}:
            yield m, r.path, r


def test_every_route_is_signed_in_or_listed_public():
    open_routes = []
    for method, path, route in _routes():
        if (method, path) in PUBLIC or path.startswith(AUTH_PREFIXES) or path.startswith(("/docs", "/openapi", "/redoc")):
            continue
        if not (_calls(route) & GUARDS):
            open_routes.append(f"{method} {path}")
    assert open_routes == [], f"routes with no access check: {open_routes}"


def test_every_admin_route_names_a_permission():
    """Admin endpoints check a role permission, not just "is ops" (§3.13)."""
    bare = []
    for method, path, route in _routes():
        if not path.startswith("/admin") or (method, path) in PUBLIC or path == "/admin/me":
            continue
        names = {getattr(c, "__qualname__", "") for c in _calls(route)}
        if not any("require_permission" in n for n in names):
            bare.append(f"{method} {path}")
    assert bare == [], f"admin routes without a permission: {bare}"


def test_the_public_list_has_no_stale_entries():
    paths = {(m, p) for m, p, _ in _routes()}
    stale = [k for k in PUBLIC if k not in paths and k[1] not in ("/", "/health", "/healthz")]
    assert stale == [], f"PUBLIC lists routes that don't exist: {stale}"


def test_roles_only_grow_upwards_where_intended():
    assert PERMISSIONS["support"] < PERMISSIONS["ops_lead"] < PERMISSIONS["admin"]
    assert PERMISSIONS["finance"] < PERMISSIONS["admin"]
    assert "incidents.decide" not in PERMISSIONS["support"]
    assert "payouts.manage" not in PERMISSIONS["ops_lead"]
    assert "policies.approve" in PERMISSIONS["admin"] and "policies.approve" not in PERMISSIONS["ops_lead"]
