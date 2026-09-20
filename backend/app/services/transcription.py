"""
Voice-note transcription.

The intake screen specifies that a recorded voice note "auto-transcribes — show
the transcript inline once done, editable". ``OPENAI_API_KEY`` was already in
config but nothing used it, and ``/bookings/{id}/intake`` accepted
``transcript_text`` from the client, so in practice nothing transcribed anything.

**Scope boundary, deliberately narrow.** The product promises intake is
"reviewed by your doctor directly — never analyzed by AI". Transcription is
speech-to-text and nothing else: no summarising, no triage, no symptom
extraction, no suggestion of urgency or diagnosis. The prompt is empty and the
output is stored verbatim for the doctor to read and the patient to edit. If
anyone later wants a "summary" field here, that is a product decision about the
promise, not an implementation detail.

Transcription is best-effort. A failure records itself on the row and leaves the
audio intact, because the doctor can still play it — a voice note that did not
transcribe is a degraded intake, not a lost one.
"""
from __future__ import annotations

from typing import Optional

import httpx

from ..config import OPENAI_API_KEY
from ..db import supabase

TRANSCRIBE_URL = "https://api.openai.com/v1/audio/transcriptions"
MODEL = "whisper-1"
TIMEOUT_SECONDS = 120   # a few minutes of audio, on a slow link

# Indian patients describing symptoms will code-switch constantly. Leaving the
# language unset lets Whisper detect it rather than forcing English and mangling
# Hindi or Marathi into phonetic nonsense.
LANGUAGE: Optional[str] = None


def enabled() -> bool:
    return bool(OPENAI_API_KEY)


def transcribe_bytes(content: bytes, filename: str, content_type: str) -> str:
    """
    Transcribe audio, returning the text.

    Raises on failure so the caller can record why; callers treat that as a
    degraded upload rather than a failed one.
    """
    if not enabled():
        raise RuntimeError("OPENAI_API_KEY is not configured")

    data = {"model": MODEL}
    if LANGUAGE:
        data["language"] = LANGUAGE

    with httpx.Client(timeout=TIMEOUT_SECONDS) as client:
        res = client.post(
            TRANSCRIBE_URL,
            headers={"Authorization": f"Bearer {OPENAI_API_KEY}"},
            files={"file": (filename, content, content_type)},
            data=data,
        )

    if res.status_code >= 400:
        raise RuntimeError(f"transcription failed ({res.status_code}): {res.text[:200]}")

    text = (res.json() or {}).get("text", "").strip()
    if not text:
        raise RuntimeError("transcription returned no text")
    return text


def transcribe_media(media_id: str, content: bytes, filename: str,
                     content_type: str) -> None:
    """
    Transcribe an intake voice note and record the outcome on its row.

    Never raises: this runs as a background task after the upload has already
    been acknowledged, so there is no caller left to tell. When push is unset the
    row simply records that transcription was not attempted, which keeps the
    reason visible instead of leaving a silently empty transcript.
    """
    if not enabled():
        _update(media_id, {
            "transcript_status": "failed",
            "transcript_error": "transcription is not configured on this deployment",
        })
        print(f"[transcription STUB] media={media_id} ({len(content)} bytes) — OPENAI_API_KEY unset")
        return

    try:
        text = transcribe_bytes(content, filename, content_type)
    except Exception as exc:
        _update(media_id, {
            "transcript_status": "failed",
            "transcript_error": str(exc)[:500],
        })
        return

    _update(media_id, {
        "transcript_text": text,
        "transcript_status": "done",
        "transcript_error": None,
    })


def _update(media_id: str, fields: dict) -> None:
    try:
        supabase.table("intake_media").update(fields).eq("id", media_id).execute()
    except Exception as exc:  # pragma: no cover
        print(f"[transcription] could not update media {media_id}: {exc}")
