from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .errors import AppError, app_error_handler
from .routers import (
    auth, categories, doctors, schedules, slot_blocks,
    bookings, intake, calls, procedure_bills, earnings, push, payments,
    ratings, complaints,
)

app = FastAPI(title="Charak API", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],      # tighten in prod to admin domain + app deep-link origins
    allow_credentials=True,
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
app.include_router(push.router,             prefix="/push",             tags=["push"])
app.include_router(payments.router,         prefix="/payments",         tags=["payments"])
app.include_router(ratings.router,          prefix="/bookings",         tags=["ratings"])
app.include_router(complaints.router,       prefix="/bookings",         tags=["complaints"])


@app.get("/healthz", tags=["meta"])
def health():
    return {"status": "ok"}
