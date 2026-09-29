import os
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL             = os.environ["SUPABASE_URL"]
SUPABASE_ANON_KEY        = os.environ["SUPABASE_ANON_KEY"]
SUPABASE_SERVICE_ROLE_KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
JWT_SECRET               = os.environ["JWT_SECRET"]

MSG91_API_KEY    = os.getenv("MSG91_API_KEY", "")
MSG91_SENDER_ID  = os.getenv("MSG91_SENDER_ID", "CHARAK")
MSG91_TEMPLATE_ID = os.getenv("MSG91_TEMPLATE_ID", "")

RAZORPAY_KEY_ID     = os.getenv("RAZORPAY_KEY_ID", "")
RAZORPAY_KEY_SECRET = os.getenv("RAZORPAY_KEY_SECRET", "")
RAZORPAY_WEBHOOK_SECRET = os.getenv("RAZORPAY_WEBHOOK_SECRET", "")

AGORA_APP_ID          = os.getenv("AGORA_APP_ID", "")
AGORA_APP_CERTIFICATE = os.getenv("AGORA_APP_CERTIFICATE", "")

# ── Voice-note transcription + summary ───────────────────────────────────────
# Requirements Doc 3.8: voice becomes transcript + summary for the doctor.
# Nothing diagnostic, and nothing reads photos or video.
#
# Vertex AI is preferred over the public Gemini API for one reason: patient
# voice notes describing symptoms are health data, and a regional endpoint
# (asia-south1 = Mumbai) keeps processing in India. The global endpoint would
# silently defeat that, so the region is always part of the URL.
VERTEX_PROJECT_ID = os.getenv("VERTEX_PROJECT_ID", "")
VERTEX_LOCATION   = os.getenv("VERTEX_LOCATION", "asia-south1")
# Pin the model. APAC regions lag US on new releases, so "whatever is newest"
# is not a safe default here.
GEMINI_MODEL      = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")

# Legacy: Whisper. Kept as a fallback while Vertex is being switched on, and so
# a deployment without GCP credentials still transcribes.
OPENAI_API_KEY = os.getenv("OPENAI_API_KEY", "")

# ── Push ─────────────────────────────────────────────────────────────────────
# FCM HTTP v1 (preferred): set FCM_PROJECT_ID + GOOGLE_APPLICATION_CREDENTIALS.
# Legacy server key is still honoured for a quicker switch-on.
FCM_PROJECT_ID = os.getenv("FCM_PROJECT_ID", "")
FCM_SERVER_KEY = os.getenv("FCM_SERVER_KEY", "")
GOOGLE_APPLICATION_CREDENTIALS = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "")

# ── Money ────────────────────────────────────────────────────────────────────
# Charak's cut of every confirmed consult fee and procedure bill, as a
# percentage. A per-doctor override lives in doctors.commission_pct.
PLATFORM_COMMISSION_PCT = float(os.getenv("PLATFORM_COMMISSION_PCT", "15"))

# How long an accepted booking is held for the patient to pay before it is
# released back to the doctor's calendar.
PAYMENT_HOLD_MINUTES = int(os.getenv("PAYMENT_HOLD_MINUTES", "10"))

# ── Ops ──────────────────────────────────────────────────────────────────────
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "charak-admin-2024")

# Shared secret for internal/cron endpoints (hold sweeper, payout runs).
CRON_SECRET = os.getenv("CRON_SECRET", "")
