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

import logging
import uuid
from typing import Optional

from ..db import supabase
from ..errors import AppError

logger = logging.getLogger(__name__)

# ── Buckets ──────────────────────────────────────────────────────────────────
BUCKET_DOCTOR_PHOTOS = "doctor-photos"        # public: shown in the directory
BUCKET_VERIFICATION  = "verification-docs"    # private: licences and IDs
BUCKET_INTAKE        = "intake-media"         # private: patient health information
BUCKET_PRESCRIPTIONS = "prescriptions"        # private: PDFs, handwritten uploads, signatures

PRIVATE_BUCKETS = (BUCKET_VERIFICATION, BUCKET_INTAKE, BUCKET_PRESCRIPTIONS)

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
    # A handwritten prescription, photographed or scanned.
    "prescription_upload": (DOCUMENT_TYPES, 15 * MB),
    # The doctor's signature for prescription PDFs: a small PNG or JPEG.
    "signature":    ({"image/png": "png", "image/jpeg": "jpg"}, 2 * MB),
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


def _is_iso_media(head: bytes) -> bool:
    """MP4-family container (mp4, m4a, mov, heic): a ``ftyp`` box at offset 4."""
    return head[4:8] == b"ftyp"


def _is_mpeg_audio(head: bytes) -> bool:
    """MP3 (with or without an ID3 tag) or ADTS AAC: 11-bit frame sync."""
    return head[:3] == b"ID3" or (
        len(head) >= 2 and head[0] == 0xFF and head[1] & 0xE0 == 0xE0
    )


# What the first bytes of each accepted type must look like. The declared
# Content-Type comes from the client and is trivially forged, so it only picks
# the extension once the bytes agree with it: an HTML or SVG page labelled
# image/png is refused rather than stored (and, in the public photo bucket,
# served from Charak's storage domain).
_SIGNATURES = {
    "image/jpeg":      lambda h: h[:3] == b"\xff\xd8\xff",
    "image/png":       lambda h: h[:8] == b"\x89PNG\r\n\x1a\n",
    "image/webp":      lambda h: h[:4] == b"RIFF" and h[8:12] == b"WEBP",
    "image/heic":      _is_iso_media,
    "application/pdf": lambda h: h[:5] == b"%PDF-",
    "audio/mpeg":      _is_mpeg_audio,
    "audio/aac":       _is_mpeg_audio,
    "audio/mp4":       _is_iso_media,
    "audio/wav":       lambda h: h[:4] == b"RIFF" and h[8:12] == b"WAVE",
    "audio/x-wav":     lambda h: h[:4] == b"RIFF" and h[8:12] == b"WAVE",
    "audio/webm":      lambda h: h[:4] == b"\x1a\x45\xdf\xa3",
    "audio/ogg":       lambda h: h[:4] == b"OggS",
    "video/mp4":       _is_iso_media,
    "video/quicktime": lambda h: _is_iso_media(h) or h[4:8] in (b"moov", b"mdat", b"wide", b"free"),
    "video/webm":      lambda h: h[:4] == b"\x1a\x45\xdf\xa3",
}


def check_signature(content_type: str, content: bytes) -> None:
    """Refuse a file whose bytes do not match its declared type."""
    check = _SIGNATURES.get(content_type)
    if check is None or not check(content[:16]):
        raise AppError(
            "That file's contents don't match its type — it may be damaged "
            "or not really a " + content_type.split("/")[-1].upper() + " file",
            415,
        )


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


def thumb_url(bucket: str, path: str, width: int = 256, height: int = 256) -> str:
    """
    A resized, cacheable render URL for a public image.

    Uses Supabase Storage's image-transform render endpoint so the apps download
    a small thumbnail (a directory list of doctor photos) instead of full-size
    originals — the single biggest data saving on a mobile directory screen.
    Falls back to the untransformed public URL if the path is empty.
    """
    base = public_url(bucket, path)
    if not path:
        return base
    # /object/public/<...>  →  /render/image/public/<...>?width=&height=&resize=cover
    render = base.replace("/object/public/", "/render/image/public/")
    sep = "&" if "?" in render else "?"
    return f"{render}{sep}width={width}&height={height}&resize=cover&quality=75"


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


def download(bucket: str, path: str) -> Optional[bytes]:
    """Read a private object's bytes (the backend's own use, such as a doctor's
    signature for a PDF). None if it can't be read."""
    try:
        return supabase.storage.from_(bucket).download(path)
    except Exception as exc:
        logger.warning("could not read %s/%s: %s", bucket, path, exc)
        return None


def remove(bucket: str, path: str) -> None:
    """
    Delete an object. Best-effort: a failed cleanup of a replaced file is not
    worth failing the request the user actually made.
    """
    try:
        supabase.storage.from_(bucket).remove([path])
    except Exception as exc:  # pragma: no cover
        logger.error("could not delete %s/%s: %s", bucket, path, exc)


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
    for name in (BUCKET_DOCTOR_PHOTOS, BUCKET_VERIFICATION, BUCKET_INTAKE, BUCKET_PRESCRIPTIONS):
        if name in existing:
            continue
        supabase.storage.create_bucket(
            name, options={"public": name not in PRIVATE_BUCKETS}
        )
        created.append(name)

    return {"created": created, "existing": sorted(existing)}
