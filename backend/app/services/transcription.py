"""
Voice-note transcription and summary.

The intake screen promises a recorded voice note "auto-transcribes — show the
transcript inline once done, editable". This module is what makes that true,
and it also produces the short summary the doctor's request-detail screen shows.

**Where the AI boundary actually sits.** Requirements Document §3.8 is explicit:
"Voice → transcription + summary for the doctor only. Nothing diagnostic.
Nothing analyzes video or images. This is a hard product boundary." So the line
is not "no AI on intake" — an earlier version of this file read it that way and
left the summary unbuilt. The line is:

* voice may be transcribed and summarised;
* photos and video are stored and shown as-is, and nothing reads them;
* the summary reports **what the patient said**, never what it might mean — no
  triage, no urgency score, no differential, no advice.

The prompt below is written to hold that line, and `SUMMARY_PROMPT` is the only
place it can be weakened. Changing it is a product decision, not a refactor.

**The transcript stays primary.** The summary sits beside the patient's own
words, never replacing them: the doctor can always read the full transcript, and
the patient can edit it.

**Two backends.** Vertex AI (Gemini) is preferred — one multimodal call returns
transcript and summary together, and the regional endpoint keeps health data in
India. Whisper remains as a fallback so a deployment with no GCP credentials
still transcribes, just without a summary.

Everything here is best-effort. A failure records itself on the row and leaves
the audio intact, because the doctor can still play it — a voice note that did
not transcribe is a degraded intake, not a lost one.
"""
from __future__ import annotations

import base64
import json
from typing import Optional

import httpx

from ..config import (
    GEMINI_MODEL,
    OPENAI_API_KEY,
    VERTEX_LOCATION,
    VERTEX_PROJECT_ID,
    GOOGLE_APPLICATION_CREDENTIALS,
)
from ..db import supabase

# ── Whisper (fallback) ───────────────────────────────────────────────────────

TRANSCRIBE_URL = "https://api.openai.com/v1/audio/transcriptions"
WHISPER_MODEL = "whisper-1"
TIMEOUT_SECONDS = 120   # a few minutes of audio, on a slow link

# Indian patients describing symptoms will code-switch constantly. Leaving the
# language unset lets the model detect it rather than forcing English and
# mangling Hindi or Marathi into phonetic nonsense.
LANGUAGE: Optional[str] = None

# ── Vertex AI (preferred) ────────────────────────────────────────────────────

VERTEX_URL = (
    "https://{loc}-aiplatform.googleapis.com/v1/projects/{project}"
    "/locations/{loc}/publishers/google/models/{model}:generateContent"
)

SUMMARY_PROMPT = """\
You are transcribing a patient's voice note for a doctor in India.

Return JSON with exactly two fields:

  "transcript": the complete, verbatim transcription. Keep the patient's own
  words and their own language. If they switch between English and Hindi or
  another Indian language, transcribe each part in the language it was spoken.
  Do not translate, tidy, paraphrase or omit anything.

  "summary": at most two sentences telling the doctor what the patient said.
  Report only. Do not diagnose, do not suggest causes, do not assess severity
  or urgency, do not recommend tests or treatment, and do not add anything the
  patient did not say. If the note is too short or unclear to summarise, return
  an empty string.

Return only the JSON object.
"""

MAX_OUTPUT_TOKENS = 2048


def vertex_enabled() -> bool:
    return bool(
        VERTEX_PROJECT_ID and VERTEX_LOCATION and GOOGLE_APPLICATION_CREDENTIALS
    )


def whisper_enabled() -> bool:
    return bool(OPENAI_API_KEY)


def enabled() -> bool:
    return vertex_enabled() or whisper_enabled()


def backend_name() -> str:
    if vertex_enabled():
        return f"vertex:{GEMINI_MODEL}@{VERTEX_LOCATION}"
    if whisper_enabled():
        return f"openai:{WHISPER_MODEL}"
    return "none"


# ── Vertex AI ────────────────────────────────────────────────────────────────

def _vertex_access_token() -> str:
    """
    Mint an OAuth token from the service-account file.

    ``google-auth`` is imported lazily so the package is only required once
    Vertex is actually switched on. Same file as FCM uses; the scope differs.
    """
    from google.oauth2 import service_account          # type: ignore
    from google.auth.transport.requests import Request  # type: ignore

    creds = service_account.Credentials.from_service_account_file(
        GOOGLE_APPLICATION_CREDENTIALS,
        scopes=["https://www.googleapis.com/auth/cloud-platform"],
    )
    creds.refresh(Request())
    return creds.token


def transcribe_and_summarise(content: bytes, content_type: str) -> tuple[str, str]:
    """
    One multimodal call: audio in, ``(transcript, summary)`` out.

    Raises on failure so the caller can record why.
    """
    if not vertex_enabled():
        raise RuntimeError("Vertex AI is not configured")

    url = VERTEX_URL.format(
        loc=VERTEX_LOCATION, project=VERTEX_PROJECT_ID, model=GEMINI_MODEL
    )
    body = {
        "contents": [{
            "role": "user",
            "parts": [
                {"text": SUMMARY_PROMPT},
                {"inlineData": {
                    "mimeType": content_type or "audio/mpeg",
                    "data": base64.b64encode(content).decode(),
                }},
            ],
        }],
        "generationConfig": {
            # Transcription is not a creative task, and a summary that varies
            # between runs is one a doctor cannot trust.
            "temperature": 0,
            "maxOutputTokens": MAX_OUTPUT_TOKENS,
            "responseMimeType": "application/json",
        },
    }

    with httpx.Client(timeout=TIMEOUT_SECONDS) as client:
        res = client.post(
            url,
            json=body,
            headers={"Authorization": f"Bearer {_vertex_access_token()}"},
        )

    if res.status_code >= 400:
        raise RuntimeError(f"vertex failed ({res.status_code}): {res.text[:200]}")

    return _parse_vertex(res.json())


def _parse_vertex(payload: dict) -> tuple[str, str]:
    """
    Pull transcript and summary out of a generateContent response.

    Defensive on purpose: a malformed response must raise something a human can
    read on the media row, not an IndexError three frames deep.
    """
    try:
        parts = payload["candidates"][0]["content"]["parts"]
        text = "".join(p.get("text", "") for p in parts).strip()
    except (KeyError, IndexError, TypeError):
        raise RuntimeError(f"unexpected vertex response: {str(payload)[:200]}")

    if not text:
        raise RuntimeError("vertex returned no content")

    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        # responseMimeType should prevent this, but a transcript is worth more
        # than a summary: if the wrapper is broken, keep the words.
        return text, ""

    transcript = (parsed.get("transcript") or "").strip()
    summary = (parsed.get("summary") or "").strip()
    if not transcript:
        raise RuntimeError("vertex returned no transcript")
    return transcript, summary


# ── Whisper ──────────────────────────────────────────────────────────────────

def transcribe_bytes(content: bytes, filename: str, content_type: str) -> str:
    """Transcribe audio, returning the text. Raises on failure."""
    if not whisper_enabled():
        raise RuntimeError("OPENAI_API_KEY is not configured")

    data = {"model": WHISPER_MODEL}
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


# ── Entry point ──────────────────────────────────────────────────────────────

def transcribe_media(media_id: str, content: bytes, filename: str,
                     content_type: str) -> None:
    """
    Transcribe an intake voice note and record the outcome on its row.

    Never raises: this runs as a background task after the upload has already
    been acknowledged, so there is no caller left to tell. When nothing is
    configured the row records that, which keeps the reason visible instead of
    leaving a silently empty transcript.
    """
    if not enabled():
        _update(media_id, {
            "transcript_status": "failed",
            "transcript_error": "transcription is not configured on this deployment",
        })
        print(f"[transcription STUB] media={media_id} ({len(content)} bytes) — no backend configured")
        return

    transcript = summary = ""
    model = backend_name()

    if vertex_enabled():
        try:
            transcript, summary = transcribe_and_summarise(content, content_type)
        except Exception as exc:
            # Fall back rather than fail: a transcript without a summary is a
            # working intake, and Whisper may well be configured alongside.
            print(f"[transcription] vertex failed for {media_id}: {exc}")
            if not whisper_enabled():
                _update(media_id, {
                    "transcript_status": "failed",
                    "transcript_error": str(exc)[:500],
                })
                return
            transcript, summary = "", ""

    if not transcript:
        try:
            transcript = transcribe_bytes(content, filename, content_type)
            model = f"openai:{WHISPER_MODEL}"
        except Exception as exc:
            _update(media_id, {
                "transcript_status": "failed",
                "transcript_error": str(exc)[:500],
            })
            return

    _update(media_id, {
        "transcript_text": transcript,
        "transcript_summary": summary or None,
        "summary_model": model if summary else None,
        "transcript_status": "done",
        "transcript_error": None,
    })


def _update(media_id: str, fields: dict) -> None:
    try:
        supabase.table("intake_media").update(fields).eq("id", media_id).execute()
    except Exception as exc:  # pragma: no cover
        print(f"[transcription] could not update media {media_id}: {exc}")
