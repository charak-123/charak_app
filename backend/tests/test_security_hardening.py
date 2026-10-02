"""
Regression tests for strix-reported hardening fixes that don't fit an existing
router test file: the verification-document URL validator (stored-XSS vector)
and cryptographically secure OTP generation.
"""
import pytest
from pydantic import ValidationError

from app.routers.doctors import VerificationSubmit
from app.services import otp_store


# ── stored-XSS: verification document URL must be http(s) ─────────────────────

@pytest.mark.parametrize("bad", [
    "javascript:alert(document.cookie)",
    "data:text/html,<script>1</script>",
    "vbscript:msgbox(1)",
    "  javascript:alert(1)",
])
def test_verification_submit_rejects_non_http_document_urls(bad):
    with pytest.raises(ValidationError):
        VerificationSubmit(license_number="MH-1", document_url=bad)


@pytest.mark.parametrize("ok", [
    "https://files.example.com/doc.pdf",
    "http://files.example.com/doc.pdf",
    None,
    "",
])
def test_verification_submit_accepts_http_urls_and_empty(ok):
    assert VerificationSubmit(license_number="MH-1", document_url=ok).document_url == ok


# ── predictable OTP: generation must use the secure generator ─────────────────

def test_otp_generation_uses_secrets_not_the_random_module():
    import inspect
    src = inspect.getsource(otp_store)
    assert "import secrets" in src
    assert "secrets.choice" in otp_store.generate_code.__code__.co_names or "secrets" in src
    # The insecure general-purpose PRNG must not be imported.
    assert "\nimport random" not in src and "import random\n" not in src


def test_otp_generation_produces_a_code_of_the_configured_length():
    code = otp_store.generate_code()
    assert len(code) == otp_store.CODE_LENGTH
    assert code.isdigit()
