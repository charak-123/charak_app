"""
Minimal structured-enough logging setup.

Cloud Run (and Fly, and `docker logs`) capture stdout/stderr automatically, so
the `print(...)` calls scattered through the services worked in the sense that
the text wasn't lost — but it all arrived as one undifferentiated stream with
no level, timestamp or logger name, so a real failure couldn't be filtered out
from routine noise or alerted on. This gives every module a `logging.Logger`
that writes one line per record, with a level, to stdout.

Call `configure_logging()` once, at process startup (see main.py). Call sites
elsewhere just do `logger = logging.getLogger(__name__)`.
"""
from __future__ import annotations

import logging
import os
import sys


def configure_logging() -> None:
    level_name = os.getenv("LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)

    root = logging.getLogger()
    if root.handlers:
        # Already configured (e.g. a second import, or pytest's own setup) —
        # just make sure the level is right rather than add a duplicate handler.
        root.setLevel(level)
        return

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter(
        fmt="%(asctime)s %(levelname)s %(name)s: %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S%z",
    ))
    root.addHandler(handler)
    root.setLevel(level)

    # These two libraries log every outbound HTTP call at INFO, which drowns
    # out application logs. Leave them at WARNING unless LOG_LEVEL=DEBUG.
    if level > logging.DEBUG:
        logging.getLogger("httpx").setLevel(logging.WARNING)
        logging.getLogger("httpcore").setLevel(logging.WARNING)
