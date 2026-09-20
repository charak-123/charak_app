"""
Tests for voice-note transcription.

The scope boundary is the point: this is speech-to-text and nothing else. The
product promises intake is "reviewed by your doctor directly — never analyzed by
AI", so there is no summarising, triage or symptom extraction here, and the tests
assert the request carries no prompt that could introduce any.
"""
from unittest.mock import MagicMock, patch

import pytest

from app.services import transcription
from tests.conftest import make_chain, make_supabase

SVC_DB = "app.services.transcription.supabase"


def _ok_response(text="मुझे दो दिन से बुखार है"):
    res = MagicMock()
    res.status_code = 200
    res.json.return_value = {"text": text}
    return res


class _Client:
    """Stands in for httpx.Client as a context manager."""
    def __init__(self, response):
        self._response = response
        self.captured = {}

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def post(self, url, **kwargs):
        self.captured = {"url": url, **kwargs}
        return self._response


# ── enablement ────────────────────────────────────────────────────────────────

def test_transcription_is_disabled_without_a_key():
    with patch("app.services.transcription.OPENAI_API_KEY", ""):
        assert transcription.enabled() is False


def test_transcription_is_enabled_with_a_key():
    with patch("app.services.transcription.OPENAI_API_KEY", "sk-test"):
        assert transcription.enabled() is True


def test_transcribe_bytes_refuses_when_unconfigured():
    with patch("app.services.transcription.OPENAI_API_KEY", ""):
        with pytest.raises(RuntimeError):
            transcription.transcribe_bytes(b"\x00", "a.m4a", "audio/mp4")


# ── the request ───────────────────────────────────────────────────────────────

def test_a_successful_transcription_returns_the_text():
    fake = _Client(_ok_response("I have had a fever for two days"))
    with patch("app.services.transcription.OPENAI_API_KEY", "sk-test"), \
         patch("app.services.transcription.httpx.Client", lambda **kw: fake):
        text = transcription.transcribe_bytes(b"\x00" * 100, "note.m4a", "audio/mp4")
    assert text == "I have had a fever for two days"


def test_the_request_carries_no_prompt_or_instruction():
    """A prompt is where interpretation would creep in. There must not be one."""
    fake = _Client(_ok_response())
    with patch("app.services.transcription.OPENAI_API_KEY", "sk-test"), \
         patch("app.services.transcription.httpx.Client", lambda **kw: fake):
        transcription.transcribe_bytes(b"\x00" * 100, "note.m4a", "audio/mp4")

    sent = fake.captured["data"]
    assert sent == {"model": transcription.MODEL}
    assert "prompt" not in sent
    assert "instructions" not in sent


def test_the_language_is_left_unset_so_code_switching_survives():
    """Indian patients code-switch constantly; forcing English mangles Hindi into
    phonetic nonsense."""
    assert transcription.LANGUAGE is None


def test_transcribed_text_is_stored_verbatim_and_stripped():
    fake = _Client(_ok_response("  fever since Tuesday  "))
    with patch("app.services.transcription.OPENAI_API_KEY", "sk-test"), \
         patch("app.services.transcription.httpx.Client", lambda **kw: fake):
        assert transcription.transcribe_bytes(b"\x00", "a.m4a", "audio/mp4") \
            == "fever since Tuesday"


def test_an_api_error_raises_with_the_status():
    bad = MagicMock()
    bad.status_code = 429
    bad.text = "rate limited"
    with patch("app.services.transcription.OPENAI_API_KEY", "sk-test"), \
         patch("app.services.transcription.httpx.Client", lambda **kw: _Client(bad)):
        with pytest.raises(RuntimeError) as exc:
            transcription.transcribe_bytes(b"\x00", "a.m4a", "audio/mp4")
    assert "429" in str(exc.value)


def test_empty_text_is_treated_as_a_failure():
    """Silence transcribed to nothing should record as failed, not as a successful
    empty transcript the doctor might read as 'no complaint'."""
    with patch("app.services.transcription.OPENAI_API_KEY", "sk-test"), \
         patch("app.services.transcription.httpx.Client",
               lambda **kw: _Client(_ok_response("   "))):
        with pytest.raises(RuntimeError):
            transcription.transcribe_bytes(b"\x00", "a.m4a", "audio/mp4")


# ── the background task ───────────────────────────────────────────────────────

def test_a_completed_transcription_is_written_to_the_row():
    media = make_chain(list_data=[{"id": "im-1"}])
    db = make_supabase({"intake_media": media})
    with patch(SVC_DB, db), \
         patch("app.services.transcription.OPENAI_API_KEY", "sk-test"), \
         patch("app.services.transcription.transcribe_bytes", lambda *a: "fever"):
        transcription.transcribe_media("im-1", b"\x00", "a.m4a", "audio/mp4")

    written = media.update.call_args[0][0]
    assert written["transcript_text"] == "fever"
    assert written["transcript_status"] == "done"
    assert written["transcript_error"] is None


def test_a_failed_transcription_records_why_and_never_raises():
    """This runs after the upload was acknowledged — there is no caller left to
    tell, and the audio is still playable, so the intake is degraded not lost."""
    media = make_chain(list_data=[{"id": "im-1"}])
    db = make_supabase({"intake_media": media})

    def _boom(*a):
        raise RuntimeError("whisper exploded")

    with patch(SVC_DB, db), \
         patch("app.services.transcription.OPENAI_API_KEY", "sk-test"), \
         patch("app.services.transcription.transcribe_bytes", _boom):
        transcription.transcribe_media("im-1", b"\x00", "a.m4a", "audio/mp4")

    written = media.update.call_args[0][0]
    assert written["transcript_status"] == "failed"
    assert "whisper exploded" in written["transcript_error"]


def test_an_unconfigured_deployment_records_the_reason_rather_than_silence():
    """An empty transcript with no explanation looks like a transcription that
    found nothing to say."""
    media = make_chain(list_data=[{"id": "im-1"}])
    db = make_supabase({"intake_media": media})
    with patch(SVC_DB, db), patch("app.services.transcription.OPENAI_API_KEY", ""):
        transcription.transcribe_media("im-1", b"\x00", "a.m4a", "audio/mp4")

    written = media.update.call_args[0][0]
    assert written["transcript_status"] == "failed"
    assert "not configured" in written["transcript_error"]


def test_a_database_failure_while_recording_does_not_raise():
    broken = MagicMock()
    broken.table.side_effect = RuntimeError("no connection")
    with patch(SVC_DB, broken), patch("app.services.transcription.OPENAI_API_KEY", ""):
        transcription.transcribe_media("im-1", b"\x00", "a.m4a", "audio/mp4")
