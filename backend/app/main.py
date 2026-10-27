import logging
import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware

from postgrest.exceptions import APIError

from .logging_config import configure_logging

configure_logging()
logger = logging.getLogger(__name__)

from .errors import AppError, app_error_handler, db_error_handler
from .routers import (
    account, addresses, admin, admin_ops, app_config, auth, bookings, calls, categories, complaints, consents, doctors,
    earnings, intake, legal, maintenance, notifications, payments, payouts,
    procedure_bills, push, ratings, schedules, slot_blocks, trust, uploads, users, visit,
)
from .services.idempotency import IdempotencyMiddleware
from .services.notifications import push_enabled

# The interactive docs publish a complete map of every route and payload. Useful
# locally, a free reconnaissance aid in production — so off unless asked for.
_docs_enabled = os.getenv("ENABLE_API_DOCS", "").lower() in ("1", "true", "yes")

app = FastAPI(
    title="Charak API",
    version="0.2.0",
    docs_url="/docs" if _docs_enabled else None,
    redoc_url="/redoc" if _docs_enabled else None,
    openapi_url="/openapi.json" if _docs_enabled else None,
)

# The mobile apps are not browsers and send no Origin, so CORS only governs the
# admin dashboard. ALLOWED_ORIGINS is a comma-separated list; the "*" default
# keeps local development frictionless and should be set in production.
_origins = [o.strip() for o in os.getenv("ALLOWED_ORIGINS", "*").split(",") if o.strip()]
if _origins == ["*"]:
    # Not a hard failure: the mobile apps send no Origin at all, so this never
    # blocks them. It only means the admin dashboard — wherever it ends up
    # hosted — can be called cross-origin from anywhere. Tighten this to the
    # admin's real domain once it has one.
    logger.warning(
        "ALLOWED_ORIGINS is unset (defaulting to '*'). Fine for local "
        "development; set it to the admin dashboard's domain in production."
    )

# Innermost of the middleware (Starlette wraps later additions around earlier
# ones): CORS and GZip sit outside it, so a replayed response still gets CORS
# headers and is stored as plain, uncompressed JSON.
app.add_middleware(IdempotencyMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials="*" not in _origins,
    allow_methods=["*"],
    allow_headers=["*"],
    # Browsers may reuse a preflight this long (Chrome caps it at 2 hours):
    # without it the admin sent an OPTIONS before nearly every request.
    max_age=7200,
)

@app.middleware("http")
async def _security_headers(request, call_next):
    # The API only ever returns JSON: never let a browser sniff a response into
    # HTML, frame it, or leak the URL (which can carry ids) as a referrer.
    response = await call_next(request)
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "no-referrer")
    return response


# Compress JSON list responses (directory search, history, ledger). Mobile data
# is the constraint for patients, and these payloads gzip to a fraction.
app.add_middleware(GZipMiddleware, minimum_size=1024)

app.add_exception_handler(AppError, app_error_handler)
# Malformed path ids reach the driver as invalid uuid input; without this they
# surfaced as unhandled 500s on every `{id}` route.
app.add_exception_handler(APIError, db_error_handler)

app.include_router(auth.router,             prefix="/auth",             tags=["auth"])
app.include_router(categories.router,       prefix="/categories",       tags=["categories"])
app.include_router(consents.router,         prefix="/consents",         tags=["consents"])
app.include_router(doctors.router,          prefix="/doctors",          tags=["doctors"])
app.include_router(schedules.router,        prefix="/schedules",        tags=["schedules"])
app.include_router(slot_blocks.router,      prefix="/slot-blocks",      tags=["slot-blocks"])
app.include_router(bookings.router,         prefix="/bookings",         tags=["bookings"])
app.include_router(intake.router,           prefix="/bookings",         tags=["intake"])
app.include_router(calls.router,            prefix="/bookings",         tags=["calls"])
app.include_router(procedure_bills.router,  prefix="/bookings",         tags=["procedure-bills"])
app.include_router(earnings.router,         prefix="/earnings",         tags=["earnings"])
app.include_router(payouts.router,          prefix="/payouts",          tags=["payouts"])
app.include_router(push.router,             prefix="/push",             tags=["push"])
app.include_router(notifications.router,    prefix="/notifications",    tags=["notifications"])
app.include_router(payments.router,         prefix="/payments",         tags=["payments"])
app.include_router(ratings.router,          prefix="/bookings",         tags=["ratings"])
app.include_router(complaints.router,       prefix="/bookings",         tags=["complaints"])
app.include_router(admin.router,            prefix="/admin",            tags=["admin"])
app.include_router(admin_ops.router,        prefix="/admin",            tags=["admin"])
app.include_router(users.router,            prefix="/users",            tags=["users"])
app.include_router(addresses.router,        prefix="/addresses",        tags=["addresses"])
app.include_router(uploads.router,          prefix="/uploads",          tags=["uploads"])
app.include_router(maintenance.router,      prefix="/maintenance",      tags=["maintenance"])
app.include_router(app_config.router,       prefix="/config",           tags=["config"])
app.include_router(legal.router,            prefix="/legal",            tags=["legal"])
app.include_router(account.router,          prefix="/me",               tags=["account"])
app.include_router(visit.router,            prefix="/bookings",         tags=["visit"])
app.include_router(visit.rx_router,         prefix="/prescriptions",    tags=["visit"])
app.include_router(visit.me_router,         prefix="/me",               tags=["visit"])
app.include_router(trust.router,            prefix="/bookings",         tags=["trust"])
app.include_router(trust.incidents_router,  prefix="/incidents",        tags=["trust"])
app.include_router(trust.reschedule_router, prefix="/reschedule-requests", tags=["trust"])


@app.get("/healthz", tags=["meta"])
def health():
    return {"status": "ok"}


@app.get("/readyz", tags=["meta"])
def ready():
    """
    Deep health check for the load balancer: confirms the database actually
    answers, and reports which external integrations are live. A deploy that can
    boot but not reach Supabase should not receive traffic.
    """
    from .db import supabase
    from .routers.calls import agora_configured
    from .routers.payments import live_mode as razorpay_live, webhook_verified
    from .config import MSG91_API_KEY
    from .services.transcription import (
        enabled as transcription_enabled,
        backend_name as transcription_backend,
    )

    try:
        supabase.table("categories").select("id").limit(1).execute()
        db_ok = True
        db_error = None
    except Exception as exc:
        db_ok = False
        # The driver's message can name hosts, roles and tables; this endpoint
        # is unauthenticated, so the detail goes to the log, not the response.
        logger.error("readiness check: database unreachable — %r", exc)
        db_error = "unreachable"

    return {
        # Live keys with an unverifiable webhook is a degraded deploy, not a
        # healthy one: it can take a patient's money and never confirm the booking.
        "status": "ok" if db_ok and not (razorpay_live() and not webhook_verified())
                  else "degraded",
        "database": {"ok": db_ok, "error": db_error},
        "integrations": {
            "sms_otp": bool(MSG91_API_KEY),
            "payments": razorpay_live(),
            # Live keys without a verified webhook is the dangerous combination:
            # payments can be taken but confirmations cannot be trusted.
            "payments_webhook_verified": webhook_verified(),
            "push": push_enabled(),
            "video_calls": agora_configured(),
            "transcription": transcription_enabled(),
            # Which backend, not just whether one exists: "vertex:...@asia-south1"
            # is the difference between health data staying in India and not.
            "transcription_backend": transcription_backend(),
        },
    }
