"""
docs/legal/publish.py: the published migration matches the documents in the
repo, and the documents use only what the apps can render.
"""
import importlib.util
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("publish", ROOT / "docs" / "legal" / "publish.py")
publish = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(publish)

PUBLISHED = {"2026-10-28": "0031", "2026-10-29": "0034"}


@pytest.mark.parametrize("version,number", PUBLISHED.items())
def test_each_published_migration_matches_its_documents(version, number):
    path = publish.migration_path(version, number)
    assert path.read_text(encoding="utf-8") == publish.migration(version, number), (
        f"run: python3 docs/legal/publish.py {version} {number}")


def test_every_role_has_its_documents():
    docs = {d["type"]: d for d in publish.documents("2026-10-28")}
    assert set(docs) == {"tos", "practitioner_terms", "privacy", "refund_policy", "telemedicine"}
    assert docs["tos"]["audience"] == ["patient"]
    assert docs["practitioner_terms"]["audience"] == ["doctor"]
    assert docs["refund_policy"]["audience"] == ["patient", "doctor"]


def test_the_online_rule_and_its_policy_text_agree():
    """0033's rules and the 2026-10-29 policy text promise the same refunds."""
    import json
    import re
    from app.services import cancellation

    sql = (ROOT / "supabase" / "migrations" / "0033_online_cancellation_15_minutes.sql").read_text()
    rules = json.loads(re.search(r"'(\[\{.*?\}\])'", sql, re.S).group(1))
    rows = cancellation._patient_points("online_consult", rules)
    assert [(r["when"], r["outcome"]) for r in rows] == [
        ("15 minutes or more before the consultation", "Full refund"),
        ("Less than 15 minutes before the consultation", "No refund"),
    ]
    text = next(d for d in publish.documents("2026-10-29") if d["type"] == "refund_policy")["body"]
    assert "**15 minutes or more before the consultation: full refund.**" in text
    assert "**Less than 15 minutes before the consultation: no refund.**" in text
    assert "Any time before the consultation starts" not in text


def _write(tmp_path, body, **header):
    fields = {"type": "tos", "version": "2026-10-28", "title": "T", "audience": "patient",
              "url": "https://x", "summary": "S", **header}
    text = "---\n" + "".join(f"{k}: {v}\n" for k, v in fields.items()) + "highlights:\n- One.\n---\n" + body
    path = tmp_path / "doc.md"
    path.write_text(text)
    return path


@pytest.mark.parametrize("body,problem", [
    ("# Title\n", "use ##"),
    ("- a\n  - nested\n", "can't show"),
    ("> quoted\n", "can't show"),
    ("| a | b | c |\n", "two columns"),
    ("```\ncode\n```\n", "can't show"),
])
def test_what_the_apps_cant_show_is_refused(tmp_path, body, problem):
    with pytest.raises(publish.DocumentError, match=problem):
        publish.parse(_write(tmp_path, body))


def test_a_header_mistake_is_refused(tmp_path):
    with pytest.raises(publish.DocumentError, match="audience"):
        publish.parse(_write(tmp_path, "Text.\n", audience="ops"))
    with pytest.raises(publish.DocumentError, match="type"):
        publish.parse(_write(tmp_path, "Text.\n", type="cookies"))
