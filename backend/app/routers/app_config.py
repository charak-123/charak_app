"""
GET /config/app: what an app needs to know before anything else.

Public, because it runs before sign-in: the splash screen asks whether this
build may continue. When the API changes in a way an old build can't follow,
raising ``min_app_version`` in app_config sends that build to a "please update"
screen instead of letting it fail half way through a booking.
"""
from typing import Optional

from fastapi import APIRouter

from ..errors import AppError
from ..services import app_config

router = APIRouter()

APPS = ("patient", "doctor")


@router.get("/app")
def app_status(app: str, version: str, platform: Optional[str] = None):
    if app not in APPS:
        raise AppError("app must be 'patient' or 'doctor'", 400)
    if platform is not None and platform not in ("android", "ios"):
        raise AppError("platform must be 'android' or 'ios'", 400)
    if app_config.parse_version(version) is None:
        raise AppError("version must look like 1.2.3", 400)
    return app_config.update_status(app, platform, version)
