"""
Razorpay access in one place: whether the deployment is live, the client, and
the timeout every call carries.

The SDK uses ``requests`` with no timeout unless one is passed per call, so a
hung Razorpay endpoint would hold a Cloud Run request (and a worker) until the
platform killed it. Every call made through ``call()`` gets ``TIMEOUT_SECONDS``.

The SDK is imported lazily so it stays optional until keys are configured.
"""
from __future__ import annotations

from ..config import RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET

TIMEOUT_SECONDS = 15


def live_mode() -> bool:
    return bool(RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET)


def client():
    import razorpay  # type: ignore — optional until credentials are configured

    return razorpay.Client(auth=(RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET))


def is_permanent_error(exc: BaseException) -> bool:
    """
    True when Razorpay refused the request itself (a 4xx ``BadRequestError``:
    amount too large, payment already fully refunded, unknown id), so retrying
    the same request cannot succeed. Network errors, timeouts and 5xx are
    transient and worth retrying.

    Matched by class name so the SDK need not be importable to classify.
    """
    return type(exc).__name__ == "BadRequestError"
