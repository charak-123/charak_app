"""
The optional SDKs are imported lazily, only when their credentials are set,
so nothing in the rest of the suite ever imports them. That is how
razorpay 1.4.2 shipped broken: it imports pkg_resources at import time,
python:3.13-slim has no setuptools, and every live order and refund raised a
500 in production while CI stayed green.

CI installs exactly requirements.txt, like the Docker image, so importing
each SDK here fails the build the same way production would.
"""
import importlib

import pytest


@pytest.mark.parametrize("module", [
    "razorpay",
    "agora_token_builder",
    "google.oauth2.service_account",
    "google.auth.transport.requests",
    "firebase_admin",
])
def test_optional_sdk_imports_in_a_clean_environment(module):
    importlib.import_module(module)


def test_razorpay_client_can_be_built_and_does_not_retry_posts():
    """Auto-retried POSTs could send a refund twice; services/refunds.py
    handles retries itself, idempotently."""
    from app.services.razorpay_gateway import client

    rzp = client()
    assert rzp.retry_enabled is False
