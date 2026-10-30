"""
Clarification calls router.

Agora RTC tokens are minted for real as soon as AGORA_APP_ID and
AGORA_APP_CERTIFICATE are set; until then a clearly-labelled stub token is
returned so the call UI is testable end to end without credentials.
"""
import time
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends
from pydantic import BaseModel, Field

from ..config import AGORA_APP_CERTIFICATE, AGORA_APP_ID
from ..db import fetch_one, supabase
from ..deps import require_doctor, get_current_user
from ..errors import AppError
from ..services import notifications, visits

router = APIRouter()

# Two hours: a 60-minute consultation joined a few minutes early outlived a
# one-hour token, and Agora drops the call when its token expires.
TOKEN_TTL_SECONDS = 2 * 3600

# How long a clarification call rings on the patient's phone. A doctor who
# rings again restarts it; one who gave up and left the screen without ending
# the call must not leave the patient's app ringing for ever.
RING_SECONDS = 60


def agora_configured() -> bool:
    return bool(AGORA_APP_ID and AGORA_APP_CERTIFICATE)


def _generate_agora_token(channel: str, uid: int) -> str:
    """
    Mint an RTC token valid for TOKEN_TTL_SECONDS.

    ``agora-token-builder`` is imported lazily so it stays an optional dependency
    until credentials exist. If the package is missing while credentials *are*
    set, that is a deployment error worth surfacing rather than silently handing
    the app a token that cannot join a channel.
    """
    if not agora_configured():
        return f"stub_token_{channel}_{uid}_{int(time.time())}"

    try:
        from agora_token_builder import RtcTokenBuilder  # type: ignore
    except ImportError:
        raise AppError(
            "Agora credentials are set but agora-token-builder is not installed", 500
        )

    return RtcTokenBuilder.buildTokenWithUid(
        AGORA_APP_ID,
        AGORA_APP_CERTIFICATE,
        channel,
        uid,
        1,                                    # 1 = publisher
        int(time.time()) + TOKEN_TTL_SECONDS,
    )


def _channel_for(booking_id: str) -> str:
    """
    The Agora channel for a booking: the whole id, not a prefix. An 8-character
    prefix is 32 bits — two bookings sharing it would share a channel, and a
    token minted for one would admit its holder to the other's call. 43
    characters, inside Agora's 64-byte limit.
    """
    return f"charak_{booking_id}"


class CallComplete(BaseModel):
    notes: Optional[str] = None


def _now() -> datetime:
    return datetime.now(timezone.utc)


@router.post("/{booking_id}/clarification-call", status_code=201)
def initiate_call(
    booking_id: str,
    background: BackgroundTasks,
    user: dict = Depends(require_doctor),
):
    """
    Doctor rings the patient. Returns Agora token + channel name.

    A call already in progress on this booking is rung again rather than
    refused. The doctor's screen used to leave the call open when it was
    closed with the back gesture, and every later "Call patient" then failed
    with 409 until someone ended a call nobody could see. Ringing again is what
    the doctor meant, and it is one channel per booking either way.
    """
    b = fetch_one(supabase.table("bookings").select("*").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    if b["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    if b["status"] not in ("requested", "accepted"):
        raise AppError("Can only clarify requested or accepted bookings", 400)

    now = _now().isoformat()
    active = (
        supabase.table("clarification_calls")
        .select("*")
        .eq("booking_id", booking_id)
        .eq("call_status", "initiated")
        .order("created_at", desc=True)
        .execute()
        .data
    ) or []
    if active:
        # started_at is when it last rang: the patient app rings for
        # RING_SECONDS from here.
        row = (
            supabase.table("clarification_calls").update({"started_at": now})
            .eq("id", active[0]["id"]).execute().data or [active[0]]
        )[0]
    else:
        row = supabase.table("clarification_calls").insert({
            "booking_id": booking_id,
            "call_status": "initiated",
            "started_at": now,
        }).execute().data[0]

    channel_name = _channel_for(booking_id)
    token = _generate_agora_token(channel_name, 0)
    visits.record_call_join({**b, "id": booking_id}, "doctor", user["sub"], "clarification")

    notifications.clarification_call_started(b, background)

    return {
        **row,
        "agora_channel": channel_name,
        "agora_token": token,
        "agora_app_id": AGORA_APP_ID,
        "live": agora_configured(),
        "expires_in": TOKEN_TTL_SECONDS,
    }


def _rang_at(call: dict) -> Optional[datetime]:
    ts = call.get("started_at") or call.get("created_at")
    if not ts:
        return None
    dt = datetime.fromisoformat(str(ts).replace("Z", "+00:00"))
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


@router.get("/patient/ringing-call")
def ringing_call(user: dict = Depends(get_current_user)):
    """
    ``call``: the clarification call ringing for this patient right now, or
    null. ``open_requests``: how many of their bookings a doctor could call
    about (requested or accepted), so the app asks often only while that is
    more than none.

    Push is how a ringing call normally reaches the phone, but it can be off
    (no Firebase on a dev backend, notifications denied, a battery saver
    holding messages back). The patient app asks this while it is open, so a
    call still rings.
    """
    bookings = (
        supabase.table("bookings").select("id")
        .eq("patient_id", user["sub"])
        .in_("status", ["requested", "accepted"])
        .execute().data
    ) or []
    return {"call": _ringing_for(bookings), "open_requests": len(bookings)}


def _ringing_for(bookings: list[dict]) -> Optional[dict]:
    if not bookings:
        return None
    calls = (
        supabase.table("clarification_calls").select("*")
        .in_("booking_id", [b["id"] for b in bookings])
        .eq("call_status", "initiated")
        .execute().data
    ) or []
    cutoff = _now() - timedelta(seconds=RING_SECONDS)
    ringing = [c for c in calls if (_rang_at(c) or cutoff) > cutoff]
    if not ringing:
        return None
    call = max(ringing, key=lambda c: _rang_at(c))
    booking = fetch_one(
        supabase.table("bookings").select("id, doctors(name, photo_url)").eq("id", call["booking_id"])
    ) or {}
    doctor = booking.get("doctors") or {}
    return {
        "booking_id": call["booking_id"],
        "call_id": call["id"],
        "doctor_name": doctor.get("name"),
        "doctor_photo_url": doctor.get("photo_url"),
        "rang_at": _rang_at(call).isoformat(),
        "ring_seconds": RING_SECONDS,
    }


@router.post("/{booking_id}/clarification-call/{call_id}/decline")
def decline_call(
    booking_id: str,
    call_id: str,
    background: BackgroundTasks,
    user: dict = Depends(get_current_user),
):
    """The patient can't talk now. Closes the call as missed and tells the
    doctor, whose screen would otherwise keep saying "Ringing…"."""
    booking = fetch_one(
        supabase.table("bookings").select("id, patient_id, doctor_id").eq("id", booking_id)
    )
    if not booking:
        raise AppError("Booking not found", 404)
    if user["sub"] != booking["patient_id"]:
        raise AppError("Forbidden", 403)
    call = fetch_one(
        supabase.table("clarification_calls").select("*")
        .eq("id", call_id).eq("booking_id", booking_id)
    )
    if not call:
        raise AppError("Call not found", 404)
    if call["call_status"] != "initiated":
        return call                                  # already over: nothing to decline
    updated = (
        supabase.table("clarification_calls").update({
            "call_status": "missed",
            "ended_at": _now().isoformat(),
        })
        .eq("id", call_id).eq("call_status", "initiated").execute().data
    ) or [call]
    notifications.clarification_call_declined(booking, background)
    return updated[0]


@router.get("/{booking_id}/clarification-call/{call_id}")
def get_call(booking_id: str, call_id: str, user: dict = Depends(get_current_user)):
    """One call's state: the doctor's screen asks while it rings, to learn
    that the patient declined."""
    booking = fetch_one(
        supabase.table("bookings").select("patient_id, doctor_id").eq("id", booking_id)
    )
    if not booking:
        raise AppError("Booking not found", 404)
    if user["sub"] not in (booking["patient_id"], booking["doctor_id"]):
        raise AppError("Forbidden", 403)
    call = fetch_one(
        supabase.table("clarification_calls").select("*")
        .eq("id", call_id).eq("booking_id", booking_id)
    )
    if not call:
        raise AppError("Call not found", 404)
    return call


class JoinRequest(BaseModel):
    uid: int = Field(default=0, ge=0)


@router.post("/{booking_id}/clarification-call/{call_id}/token")
def patient_join_token(
    booking_id: str,
    call_id: str,
    body: Optional[JoinRequest] = None,
    user: dict = Depends(get_current_user),
):
    """
    Token for the patient side of an in-progress call.

    The doctor gets theirs from the initiate response; without this the patient
    app had no way to join the channel it was being called on.
    """
    booking = fetch_one(
        supabase.table("bookings").select("id, patient_id, doctor_id").eq("id", booking_id)
    )
    if not booking:
        raise AppError("Booking not found", 404)
    if user["sub"] not in (booking["patient_id"], booking["doctor_id"]):
        raise AppError("Forbidden", 403)

    call = (
        supabase.table("clarification_calls").select("*")
        .eq("id", call_id).eq("booking_id", booking_id).execute().data or []
    )
    if not call:
        raise AppError("Call not found", 404)
    if call[0]["call_status"] != "initiated":
        raise AppError("Call is no longer in progress", 400)

    channel_name = _channel_for(booking_id)
    uid = (body or JoinRequest()).uid
    role = "patient" if user["sub"] == booking["patient_id"] else "doctor"
    visits.record_call_join({**booking, "id": booking_id}, role, user["sub"], "clarification")
    return {
        "agora_channel": channel_name,
        "agora_token": _generate_agora_token(channel_name, uid),
        "agora_app_id": AGORA_APP_ID,
        "uid": uid,
        "live": agora_configured(),
        "expires_in": TOKEN_TTL_SECONDS,
    }


@router.post("/{booking_id}/call")
def join_active_call(
    booking_id: str,
    body: Optional[JoinRequest] = None,
    user: dict = Depends(get_current_user),
):
    """
    Join whatever call is ringing on this booking.

    The patient app has no call id — it is told a doctor is calling and simply
    asks to be let in. This resolves the in-progress clarification call itself
    and mints the joiner's token. Legacy ``token``/``doctor_name`` keys are
    returned alongside the ``agora_*`` ones the shared call session reads.
    """
    booking = fetch_one(
        supabase.table("bookings")
        .select("id, patient_id, doctor_id, channel, status, scheduled_start, doctors(name), users(name)")
        .eq("id", booking_id)
    )
    if not booking:
        raise AppError("Booking not found", 404)
    if user["sub"] not in (booking["patient_id"], booking["doctor_id"]):
        raise AppError("Forbidden", 403)

    active = (
        supabase.table("clarification_calls")
        .select("*")
        .eq("booking_id", booking_id)
        .eq("call_status", "initiated")
        .order("created_at", desc=True)
        .execute()
        .data
    )

    # A scheduled online consult *is* the call — it has no clarification-call
    # row and never will, because nobody "initiates" it: both sides simply join
    # at the slot time. Requiring a ringing clarification call here meant the
    # patient's "Join call" button 404'd on every consult they had paid for.
    # The channel name is derived from the booking id, so both sides land in the
    # same place without any call record to coordinate them.
    is_paid_consult = (
        booking.get("channel") == "online_consult"
        and booking.get("status") in ("paid", "in_progress")
    )
    if not active and not is_paid_consult:
        raise AppError("No call is in progress for this booking", 404)

    channel_name = _channel_for(booking_id)
    uid = (body or JoinRequest()).uid
    token = _generate_agora_token(channel_name, uid)
    # Recorded for both sides (evidence if someone says the other never
    # joined). The doctor joining a paid consult starts the consultation.
    role = "patient" if user["sub"] == booking["patient_id"] else "doctor"
    visits.record_call_join({**booking, "id": booking_id}, role, user["sub"],
                            "consultation" if is_paid_consult else "clarification")
    return {
        # None for a scheduled consult — there is no clarification-call row to
        # report, and the app only uses this id to close a clarification call.
        "call_id": active[0]["id"] if active else None,
        "agora_channel": channel_name,
        "agora_token": token,
        "agora_app_id": AGORA_APP_ID,
        "token": token,                                    # legacy key
        "doctor_name": (booking.get("doctors") or {}).get("name"),
        "patient_name": (booking.get("users") or {}).get("name"),
        "uid": uid,
        "live": agora_configured(),
        "expires_in": TOKEN_TTL_SECONDS,
    }


@router.patch("/{booking_id}/clarification-call/{call_id}/complete")
def complete_call(booking_id: str, call_id: str, body: CallComplete, user: dict = Depends(require_doctor)):
    call = _get_call(call_id, booking_id, user["sub"])
    if call["call_status"] == "missed":
        # The patient declined while the doctor was writing a note: keep the
        # note, and the call stays missed.
        return supabase.table("clarification_calls").update({
            "notes": body.notes,
        }).eq("id", call_id).execute().data[0]
    if call["call_status"] != "initiated":
        raise AppError("Call is not in progress", 400)
    return supabase.table("clarification_calls").update({
        "call_status": "completed",
        "notes": body.notes,
        "ended_at": datetime.now(timezone.utc).isoformat(),
    }).eq("id", call_id).execute().data[0]


@router.patch("/{booking_id}/clarification-call/{call_id}/missed")
def mark_missed(booking_id: str, call_id: str, user: dict = Depends(require_doctor)):
    call = _get_call(call_id, booking_id, user["sub"])
    if call["call_status"] != "initiated":
        raise AppError("Call is not in progress", 400)
    return supabase.table("clarification_calls").update({
        "call_status": "missed",
    }).eq("id", call_id).execute().data[0]


@router.get("/{booking_id}/clarification-calls")
def list_calls(booking_id: str, user: dict = Depends(get_current_user)):
    b = fetch_one(supabase.table("bookings").select("patient_id, doctor_id").eq("id", booking_id))
    if not b:
        raise AppError("Booking not found", 404)
    if b["patient_id"] != user["sub"] and b["doctor_id"] != user["sub"]:
        raise AppError("Forbidden", 403)
    return (
        supabase.table("clarification_calls")
        .select("*")
        .eq("booking_id", booking_id)
        .order("created_at")
        .execute()
        .data
    )


def _get_call(call_id: str, booking_id: str, doctor_id: str) -> dict:
    call = fetch_one(
        supabase.table("clarification_calls").select("*, bookings(doctor_id)")
        .eq("id", call_id).eq("booking_id", booking_id)
    )
    if not call:
        raise AppError("Call not found", 404)
    if call["bookings"]["doctor_id"] != doctor_id:
        raise AppError("Forbidden", 403)
    return call
