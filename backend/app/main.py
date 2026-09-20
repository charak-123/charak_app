import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .errors import AppError, app_error_handler
from .routers import (
    addresses, admin, auth, bookings, calls, categories, complaints, doctors,
    earnings, intake, maintenance, notifications, payments, payouts,
    procedure_bills, push, ratings, schedules, slot_blocks, uploads, users,
)
from .services.notifications import push_enabled

app = FastAPI(title="Charak API", version="0.2.0")

# The mobile apps are not browsers and send no Origin, so CORS only governs the
# admin dashboard. ALLOWED_ORIGINS is a comma-separated list; the "*" default
# keeps local development frictionless and should be set in production.
_origins = [o.strip() for o in os.getenv("ALLOWED_ORIGINS", "*").split(",") if o.strip()]

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials="*" not in _origins,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_exception_handler(AppError, app_error_handler)

app.include_router(auth.router,             prefix="/auth",             tags=["auth"])
app.include_router(categories.router,       prefix="/categories",       tags=["categories"])
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
app.include_router(users.router,            prefix="/users",            tags=["users"])
app.include_router(addresses.router,        prefix="/addresses",        tags=["addresses"])
app.include_router(uploads.router,          prefix="/uploads",          tags=["uploads"])
app.include_router(maintenance.router,      prefix="/maintenance",      tags=["maintenance"])


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
    from .routers.payments import live_mode as razorpay_live
    from .config import MSG91_API_KEY
    from .services.transcription import enabled as transcription_enabled

    try:
        supabase.table("categories").select("id").limit(1).execute()
        db_ok = True
        db_error = None
    except Exception as exc:
        db_ok = False
        db_error = str(exc)[:200]

    return {
        "status": "ok" if db_ok else "degraded",
        "database": {"ok": db_ok, "error": db_error},
        "integrations": {
            "sms_otp": bool(MSG91_API_KEY),
            "payments": razorpay_live(),
            "push": push_enabled(),
            "video_calls": agora_configured(),
            "transcription": transcription_enabled(),
        },
    }
