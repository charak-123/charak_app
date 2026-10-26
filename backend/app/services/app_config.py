"""
Runtime settings ops can change without a deploy (``app_config``, migration
0023): the minimum app version each app must run, store links, and flags such
as ``request_expiry_minutes``.

Read on every app launch, so values are cached per process for a minute. A
change takes effect within that minute on every Cloud Run instance.
"""
from __future__ import annotations

import re
import threading
import time
from typing import Any, Optional

from ..db import supabase

CACHE_SECONDS = 60

_lock = threading.Lock()
_cache: dict[str, Any] = {}
_loaded_at = 0.0

_VERSION = re.compile(r"^\d+(\.\d+){0,3}$")


def _load() -> dict[str, Any]:
    global _cache, _loaded_at
    with _lock:
        if time.monotonic() - _loaded_at < CACHE_SECONDS and _cache:
            return _cache
        rows = supabase.table("app_config").select("key, value").execute().data or []
        _cache = {r["key"]: r["value"] for r in rows}
        _loaded_at = time.monotonic()
        return _cache


def get(key: str, default: Any = None) -> Any:
    value = _load().get(key)
    return default if value is None else value


def clear_cache() -> None:
    """For tests, and for an admin change that must apply at once."""
    global _cache, _loaded_at
    with _lock:
        _cache, _loaded_at = {}, 0.0


def parse_version(version: str) -> Optional[tuple[int, ...]]:
    """'1.4.2' or '1.4.2+17' → (1, 4, 2). None when it isn't a version."""
    core = (version or "").strip().split("+", 1)[0]
    if not _VERSION.match(core):
        return None
    parts = tuple(int(p) for p in core.split("."))
    return parts + (0,) * (3 - len(parts)) if len(parts) < 3 else parts


def update_status(app: str, platform: Optional[str], version: str) -> dict:
    """
    Whether this build of ``app`` must update before it can be used, and where
    to send the user. An unreadable minimum never blocks anyone: a bad config
    value must not lock every patient out of the app.
    """
    minimum = (get("min_app_version", {}) or {}).get(app)
    store = ((get("store_urls", {}) or {}).get(app) or {}).get(platform or "")
    current, required = parse_version(version), parse_version(minimum or "")
    return {
        "update_required": bool(current and required and current < required),
        "min_version": minimum,
        "store_url": store,
    }
