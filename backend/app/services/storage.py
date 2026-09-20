"""
File storage, mediated by the backend.

Why the backend and not the client: both apps authenticate with a JWT this API
issues, not with Supabase Auth. Inside a Storage policy ``auth.uid()`` is
therefore null, so no RLS policy can ever authorise those clients — which is why
the app code carries comments about uploads being "unauthorised" and degrades to
saving without the file. A doctor consequently could not submit a licence
document at all, leaving the admin verification queue with nothing to review.

The backend holds the service-role key, so it can write to Storage and decide
authorisation itself using the same JWT the rest of the API trusts.

Two rules worth stating because they are easy to get wrong:

* **Client filenames are never used.** Paths are derived from the owning entity's
  id plus a random component, with an extension mapped from the *sniffed* content
  type. A caller-supplied name like ``../../../other-doctor/photo.jpg`` cannot
  escape its prefix.
* **Private objects have no durable URL.** They are read through short-lived
  signed URLs minted per request, after the caller's right to see that specific
  object has been checked. Only the doctor-photos bucket is public.
"""
from __future__ import annotations

import uuid
from typing import Optional

from ..db import supabase
from ..errors import AppError

# ── Buckets ──────────────────────────────────────────────────────────────────
BUCKET_DOCTOR_PHOTOS = "doctor-photos"        # public: shown in the directory
BUCKET_VERIFICATION  = "verification-docs"    # private: licences and IDs
BUCKET_INTAKE        = "intake-media"         # private: patient health information

PRIVATE_BUCKETS = (BUCKET_VERIFICATION, BUCKET_INTAKE)

SIGNED_URL_TTL_SECONDS = 300   # 5 minutes — long enough to open, short enough
                               # that a leaked link is not a standing grant

# ── Accepted types and limits ────────────────────────────────────────────────
# Extensions are derived from these, never from the caller's filename.
IMAGE_TYPES = {
    "image/jpeg": "jpg",
    "image/png": "png",
    "image/webp": "webp",
    "image/heic": "heic",
}
DOCUMENT_TYPES = {**IMAGE_TYPES, "application/pdf": "pdf"}
AUDIO_TYPES = {
    "audio/mpeg": "mp3",
    "audio/mp4": "m4a",
    "audio/aac": "aac",
    "audio/wav": "wav",
    "audio/x-wav": "wav",
    "audio/webm": "webm",
    "audio/ogg": "ogg",
}
VIDEO_TYPES = {
    "video/mp4": "mp4",
    "video/quicktime": "mov",
    "video/webm": "webm",
}

MB = 1024 * 1024

# Limits are per kind because the risk differs: a profile photo has no reason to
# be large, while a phone-shot video of a wound legitimately is. These sit below
# Supabase's own per-object ceiling so a rejection is ours, with a clear message,
# rather than an opaque storage error.
LIMITS = {
    "photo":        (IMAGE_TYPES,    5 * MB),
    "document":     (DOCUMENT_TYPES, 15 * MB),
    "intake_image": (IMAGE_TYPES,    10 * MB),
    "intake_audio": (AUDIO_TYPES,    25 * MB),
    "intake_video": (VIDEO_TYPES,    50 * MB),
}


def validate(kind: str, content_type: Optional[str], size: int) -> str:
    """
    Check a upload against its kind's allowlist and size cap.

    Returns the file extension to store it under. Raises AppError with a message
    worth showing a user — "that file is 62MB, the limit is 50MB" is actionable
    in a way that "upload failed" is not.
    """
    if kind not in LIMITS:
        raise AppError(f"Unknown upload kind '{kind}'", 400)

    allowed, max_bytes = LIMITS[kind]
    ct = (content_type or "").split(";")[0].strip().lower()

    if ct not in allowed:
        raise AppError(
            f"Unsupported file type '{ct or 'unknown'}'. Accepted: "
            + ", ".join(sorted(allowed)),
            415,
        )
    if size <= 0:
        raise AppError("The file is empty", 400)
    if size > max_bytes:
        raise AppError(
            f"That file is {size / MB:.1f}MB — the limit is {max_bytes // MB}MB",
            413,
        )
    return allowed[ct]


def build_path(*prefix: str, extension: str) -> str:
    """
    Deterministic-prefix, random-suffix object path.

    The prefix locates the object by owner so authorisation can be decided from
    the path alone; the random suffix stops one upload silently overwriting
    another and makes paths unguessable.
    """
    safe = [str(p).replace("/", "").replace("..", "") for p in prefix if p]
    return "/".join(safe) + f"/{uuid.uuid4().hex}.{extension}"


def upload(bucket: str, path: str, content: bytes, content_type: str) -> str:
    """Write bytes to Storage and return the stored path."""
    try:
        supabase.storage.from_(bucket).upload(
            path,
            content,
            {"content-type": content_type, "upsert": "false"},
        )
    except Exception as exc:
        raise AppError(f"Could not store the file: {str(exc)[:200]}", 502)
    return path


def public_url(bucket: str, path: str) -> str:
    """Durable URL for an object in a public bucket."""
    if bucket in PRIVATE_BUCKETS:
        raise AppError(f"{bucket} is private; mint a signed URL instead", 500)
    return supabase.storage.from_(bucket).get_public_url(path)


def signed_url(bucket: str, path: str, ttl: int = SIGNED_URL_TTL_SECONDS) -> str:
    """
    Short-lived read URL for a private object.

    The caller is responsible for having already checked that *this* user may see
    *this* object — this function does not know who is asking.
    """
    try:
        result = supabase.storage.from_(bucket).create_signed_url(path, ttl)
    except Exception as exc:
        raise AppError(f"Could not create a download link: {str(exc)[:200]}", 502)

    url = (result or {}).get("signedURL") or (result or {}).get("signedUrl")
    if not url:
        raise AppError("Could not create a download link", 502)
    return url


def remove(bucket: str, path: str) -> None:
    """
    Delete an object. Best-effort: a failed cleanup of a replaced file is not
    worth failing the request the user actually made.
    """
    try:
        supabase.storage.from_(bucket).remove([path])
    except Exception as exc:  # pragma: no cover
        print(f"[storage] could not delete {bucket}/{path}: {exc}")


def ensure_buckets() -> dict:
    """
    Create any missing bucket, idempotently.

    Called from the ops bootstrap endpoint rather than at import time: creating
    buckets is a change to shared infrastructure and should happen when someone
    asks for it, not as a side effect of a process starting.
    """
    existing = {}
    try:
        for b in supabase.storage.list_buckets():
            existing[getattr(b, "name", None) or b["name"]] = b
    except Exception as exc:
        raise AppError(f"Could not list buckets: {str(exc)[:200]}", 502)

    created = []
    for name in (BUCKET_DOCTOR_PHOTOS, BUCKET_VERIFICATION, BUCKET_INTAKE):
        if name in existing:
            continue
        supabase.storage.create_bucket(
            name, options={"public": name not in PRIVATE_BUCKETS}
        )
        created.append(name)

    return {"created": created, "existing": sorted(existing)}
