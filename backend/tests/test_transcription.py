"""
Tests for voice-note transcription and summary.

The scope boundary is the point, and Requirements Document 3.8 draws it
precisely: "Voice -> transcription + summary for the doctor only. Nothing
diagnostic. Nothing analyzes video or images."

So these tests assert two different things about two different backends:

* the Whisper path carries no prompt at all — it is pure speech-to-text;
* the Vertex path carries one, and its job is to hold the line. The prompt must
  forbid diagnosis, severity and advice, and the tests check that it still does.

A prompt that quietly loses those clauses is the realistic way this boundary
gets crossed, so it is worth a test rather than a comment.
"""
import base64
import json
from contextlib import ExitStack, contextmanager
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

def test_transcription_is_disabled_without_any_backend():
    with patch("app.services.transcription.OPENAI_API_KEY", ""), \
         patch("app.services.transcription.VERTEX_PROJECT_ID", ""):
        assert transcription.enabled() is False


def test_transcription_is_enabled_with_a_key():
    with patch("app.services.transcription.OPENAI_API_KEY", "sk-test"):
        assert transcription.enabled() is True


def test_vertex_needs_all_three_settings():
    """A half-configured Vertex deployment must fall back to Whisper rather than
    fail every upload."""
    with patch("app.services.transcription.VERTEX_PROJECT_ID", "proj"), \
         patch("app.services.transcription.VERTEX_LOCATION", "asia-south1"), \
         patch("app.services.transcription.GOOGLE_APPLICATION_CREDENTIALS", ""):
        assert transcription.vertex_enabled() is False


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


def test_the_whisper_request_carries_no_prompt_or_instruction():
    """On the speech-to-text-only path, a prompt is where interpretation would
    creep in. There must not be one."""
    fake = _Client(_ok_response())
    with patch("app.services.transcription.OPENAI_API_KEY", "sk-test"), \
         patch("app.services.transcription.httpx.Client", lambda **kw: fake):
        transcription.transcribe_bytes(b"\x00" * 100, "note.m4a", "audio/mp4")

    sent = fake.captured["data"]
    assert sent == {"model": transcription.WHISPER_MODEL}
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


# ── Vertex AI: the multimodal path ───────────────────────────────────────────

VERTEX_ON = {
    "app.services.transcription.VERTEX_PROJECT_ID": "charak-prod",
    "app.services.transcription.VERTEX_LOCATION": "asia-south1",
    "app.services.transcription.GOOGLE_APPLICATION_CREDENTIALS": "/secrets/sa.json",
}


def _vertex_response(transcript="मुझे दो दिन से बुखार है", summary="Fever for two days."):
    res = MagicMock()
    res.status_code = 200
    res.json.return_value = {
        "candidates": [{"content": {"parts": [
            {"text": json.dumps({"transcript": transcript, "summary": summary})}
        ]}}]
    }
    return res


@contextmanager
def _vertex_enabled(response=None):
    """Vertex configured, its OAuth mint stubbed, and httpx captured."""
    fake = _Client(response or _vertex_response())
    with ExitStack() as stack:
        for target, value in VERTEX_ON.items():
            stack.enter_context(patch(target, value))
        stack.enter_context(
            patch("app.services.transcription._vertex_access_token", lambda: "tok")
        )
        stack.enter_context(
            patch("app.services.transcription.httpx.Client", lambda **kw: fake)
        )
        yield fake


def test_one_call_returns_both_transcript_and_summary():
    with _vertex_enabled():
        transcript, summary = transcription.transcribe_and_summarise(
            b"\x00" * 100, "audio/mp4"
        )
    assert transcript == "मुझे दो दिन से बुखार है"
    assert summary == "Fever for two days."


def test_the_request_goes_to_the_regional_endpoint_not_the_global_one():
    """The global endpoint silently defeats data residency. Patient voice notes
    describing symptoms are health data and must stay in India."""
    with _vertex_enabled() as fake:
        transcription.transcribe_and_summarise(b"\x00", "audio/mp4")

    url = fake.captured["url"]
    assert "asia-south1-aiplatform.googleapis.com" in url
    assert "/locations/asia-south1/" in url
    assert "aiplatform.googleapis.com/v1/projects/charak-prod" in url


def test_the_prompt_forbids_interpretation():
    """Requirements Doc 3.8 allows a summary and forbids everything past it.
    These clauses are the boundary; losing one is how it gets crossed."""
    prompt = transcription.SUMMARY_PROMPT.lower()
    for forbidden in ("do not diagnose", "do not suggest causes",
                      "severity", "urgency", "treatment"):
        assert forbidden in prompt, f"the prompt no longer constrains: {forbidden}"
    # And it must not invent content the patient did not say.
    assert "did not say" in prompt


def test_the_prompt_preserves_the_patients_own_language():
    prompt = transcription.SUMMARY_PROMPT.lower()
    assert "do not translate" in prompt
    assert "verbatim" in prompt


def test_the_audio_is_sent_inline_and_the_generation_is_deterministic():
    with _vertex_enabled() as fake:
        transcription.transcribe_and_summarise(b"\x01\x02\x03", "audio/mp4")

    body = fake.captured["json"]
    parts = body["contents"][0]["parts"]
    assert parts[1]["inlineData"]["mimeType"] == "audio/mp4"
    assert base64.b64decode(parts[1]["inlineData"]["data"]) == b"\x01\x02\x03"
    # A summary that changes between runs is one a doctor cannot trust.
    assert body["generationConfig"]["temperature"] == 0
    assert body["generationConfig"]["responseMimeType"] == "application/json"


def test_a_malformed_response_raises_something_readable():
    bad = MagicMock()
    bad.status_code = 200
    bad.json.return_value = {"candidates": []}
    with _vertex_enabled(bad):
        with pytest.raises(RuntimeError) as exc:
            transcription.transcribe_and_summarise(b"\x00", "audio/mp4")
    assert "unexpected vertex response" in str(exc.value)


def test_unparseable_json_keeps_the_transcript_and_drops_the_summary():
    """The words matter more than the summary. A broken wrapper must not lose
    what the patient said."""
    res = MagicMock()
    res.status_code = 200
    res.json.return_value = {
        "candidates": [{"content": {"parts": [{"text": "fever since Tuesday"}]}}]
    }
    with _vertex_enabled(res):
        transcript, summary = transcription.transcribe_and_summarise(b"\x00", "audio/mp4")
    assert transcript == "fever since Tuesday"
    assert summary == ""


def test_a_response_with_a_summary_but_no_transcript_is_a_failure():
    """A summary with nothing behind it is unreviewable — the doctor cannot
    check it against the patient's words."""
    res = MagicMock()
    res.status_code = 200
    res.json.return_value = {"candidates": [{"content": {"parts": [
        {"text": json.dumps({"transcript": "", "summary": "Fever."})}
    ]}}]}
    with _vertex_enabled(res):
        with pytest.raises(RuntimeError):
            transcription.transcribe_and_summarise(b"\x00", "audio/mp4")


# ── backend selection and fallback ───────────────────────────────────────────

def test_vertex_writes_the_summary_and_names_the_model():
    """Which model wrote a summary is the first question asked when one is
    disputed."""
    media = make_chain(list_data=[{"id": "im-1"}])
    db = make_supabase({"intake_media": media})
    with patch(SVC_DB, db), _vertex_enabled():
        transcription.transcribe_media("im-1", b"\x00", "a.m4a", "audio/mp4")

    written = media.update.call_args[0][0]
    assert written["transcript_text"] == "मुझे दो दिन से बुखार है"
    assert written["transcript_summary"] == "Fever for two days."
    assert written["summary_model"].startswith("vertex:")
    assert "asia-south1" in written["summary_model"]
    assert written["transcript_status"] == "done"


def test_vertex_failing_falls_back_to_whisper_without_a_summary():
    """A transcript with no summary is a working intake; losing the transcript
    too would not be."""
    media = make_chain(list_data=[{"id": "im-1"}])
    db = make_supabase({"intake_media": media})

    def _boom(*a, **k):
        raise RuntimeError("vertex 503")

    with ExitStack() as stack:
        for target, value in VERTEX_ON.items():
            stack.enter_context(patch(target, value))
        stack.enter_context(patch(SVC_DB, db))
        stack.enter_context(patch("app.services.transcription.OPENAI_API_KEY", "sk-test"))
        stack.enter_context(
            patch("app.services.transcription.transcribe_and_summarise", _boom))
        stack.enter_context(
            patch("app.services.transcription.transcribe_bytes", lambda *a: "fever"))
        transcription.transcribe_media("im-1", b"\x00", "a.m4a", "audio/mp4")

    written = media.update.call_args[0][0]
    assert written["transcript_text"] == "fever"
    assert written["transcript_status"] == "done"
    # No summary, and nothing claiming to have produced one.
    assert written["transcript_summary"] is None
    assert written["summary_model"] is None


def test_vertex_failing_with_no_whisper_configured_records_the_error():
    media = make_chain(list_data=[{"id": "im-1"}])
    db = make_supabase({"intake_media": media})

    def _boom(*a, **k):
        raise RuntimeError("vertex 503")

    with ExitStack() as stack:
        for target, value in VERTEX_ON.items():
            stack.enter_context(patch(target, value))
        stack.enter_context(patch(SVC_DB, db))
        stack.enter_context(patch("app.services.transcription.OPENAI_API_KEY", ""))
        stack.enter_context(
            patch("app.services.transcription.transcribe_and_summarise", _boom))
        transcription.transcribe_media("im-1", b"\x00", "a.m4a", "audio/mp4")

    written = media.update.call_args[0][0]
    assert written["transcript_status"] == "failed"
    assert "vertex 503" in written["transcript_error"]


def test_backend_name_reports_what_is_actually_in_use():
    with ExitStack() as stack:
        for target, value in VERTEX_ON.items():
            stack.enter_context(patch(target, value))
        assert transcription.backend_name().startswith("vertex:")

    with patch("app.services.transcription.VERTEX_PROJECT_ID", ""), \
         patch("app.services.transcription.OPENAI_API_KEY", "sk-test"):
        assert transcription.backend_name() == "openai:whisper-1"

    with patch("app.services.transcription.VERTEX_PROJECT_ID", ""), \
         patch("app.services.transcription.OPENAI_API_KEY", ""):
        assert transcription.backend_name() == "none"
