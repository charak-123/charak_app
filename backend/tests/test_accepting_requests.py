"""
Design system V2: the doctor's "Accepting requests" switch, and the patient's
own words on each incoming request card.
"""
from unittest.mock import patch

from fastapi.testclient import TestClient

from app.main import app
from app.routers.bookings import _with_issue
from tests.conftest import make_chain, make_supabase
from tests.test_doctors_directory import VERIFIED, DOCTORS_DB

client = TestClient(app)


def test_a_paused_doctor_drops_out_of_search():
    paused = {**VERIFIED, "id": "doc-2", "accepting_requests": False}
    doctors = make_chain(list_data=[VERIFIED, paused])
    with patch(DOCTORS_DB, make_supabase({"doctors": doctors})):
        ids = [d["id"] for d in client.get("/doctors/search").json()["items"]]
    assert ids == ["doc-1"]


def test_search_works_before_the_column_exists():
    """Migration 0016 not applied yet: no column, nobody hidden."""
    doctors = make_chain(list_data=[VERIFIED])
    with patch(DOCTORS_DB, make_supabase({"doctors": doctors})):
        assert client.get("/doctors/search").json()["total"] == 1


def test_the_typed_note_is_the_issue():
    row = _with_issue({"id": "bk", "intake_media": [
        {"media_type": "voice", "transcript_summary": "Ear pain", "created_at": "1"},
        {"media_type": "text", "transcript_text": "Fever for two days", "created_at": "2"},
    ]})
    assert row["issue"] == "Fever for two days"
    assert "intake_media" not in row


def test_a_voice_summary_stands_in_when_nothing_was_typed():
    row = _with_issue({"id": "bk", "intake_media": [
        {"media_type": "voice", "transcript_summary": "Ear pain since morning", "created_at": "1"},
    ]})
    assert row["issue"] == "Ear pain since morning"


def test_no_intake_means_no_issue():
    assert _with_issue({"id": "bk"})["issue"] is None


def test_profile_update_accepts_the_switch():
    from app.routers.doctors import DoctorProfileUpdate
    assert DoctorProfileUpdate(accepting_requests=False).model_dump(exclude_none=True) == {
        "accepting_requests": False
    }
