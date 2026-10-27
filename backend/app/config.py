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

# ── Google Sign-In ───────────────────────────────────────────────────────────
# OAuth client ids whose Google ID tokens the backend accepts, comma-separated.
# The apps request tokens for the *Web* client (serverClientId), so that one id
# is normally all that is needed. Empty disables POST /auth/google.
GOOGLE_CLIENT_IDS = [c.strip() for c in os.getenv("GOOGLE_CLIENT_IDS", "").split(",") if c.strip()]

# ── Firebase ID token sign-in ────────────────────────────────────────────────
# A second, separate sign-in path from POST /auth/google above — that one
# verifies a raw Google OAuth token from the apps' own google_sign_in package.
# This one verifies a Firebase Auth ID token (the website's Google sign-in
# already goes through Firebase; phone sign-in will too). Different token
# shape, different verification library, so it gets its own endpoint rather
# than trying to make one accept both.
#
# The full service-account JSON, not a path — Cloud Run secrets mount as env
# vars, not files. Empty disables POST /auth/firebase, same fail-closed
# pattern as GOOGLE_CLIENT_IDS above.
FIREBASE_ADMIN_CREDENTIALS_JSON = os.getenv("FIREBASE_ADMIN_CREDENTIALS_JSON", "")

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
# FCM HTTP v1 (preferred): set FCM_PROJECT_ID. Credentials are the same
# service-account JSON as FIREBASE_ADMIN_CREDENTIALS_JSON above (Firebase ID
# token verification and FCM send are two capabilities of the one
# charak-backend-firebase service account) — no second credential to manage.
# GOOGLE_APPLICATION_CREDENTIALS (a file path) is still accepted too, for a
# deployment that already has one sitting on disk; not required if the JSON
# env var is set. Legacy server key is honoured for a quicker switch-on.
FCM_PROJECT_ID = os.getenv("FCM_PROJECT_ID", "")
FCM_SERVER_KEY = os.getenv("FCM_SERVER_KEY", "")
GOOGLE_APPLICATION_CREDENTIALS = os.getenv("GOOGLE_APPLICATION_CREDENTIALS", "")

# ── Money ────────────────────────────────────────────────────────────────────
# Charak's cut of every confirmed consult fee and procedure bill, as a
# percentage. Zero at launch: the whole fee goes to the doctor. A per-doctor
# override lives in doctors.commission_pct.
PLATFORM_COMMISSION_PCT = float(os.getenv("PLATFORM_COMMISSION_PCT", "0"))

# Senior review of procedure bills. A doctor may set a lower threshold for their
# own bills, never a higher one, and a doctor who sets none gets this one. The
# doctor is the party under review, so the ceiling cannot be theirs to choose.
PROCEDURE_REVIEW_THRESHOLD_MAX = float(os.getenv("PROCEDURE_REVIEW_THRESHOLD_MAX", "5000"))

# How long an accepted booking is held for the patient to pay before it is
# released back to the doctor's calendar.
PAYMENT_HOLD_MINUTES = int(os.getenv("PAYMENT_HOLD_MINUTES", "10"))

# Upper bound on payment attempts (orders + reported failures) for one booking.
# Caps the payment-hold extension so a patient cannot keep a doctor's slot held
# indefinitely by reporting a "failure" on a timer without ever paying.
PAYMENT_MAX_ATTEMPTS = int(os.getenv("PAYMENT_MAX_ATTEMPTS", "6"))

# Explicit opt-in for insecure local-dev payment shortcuts: the /stub-complete
# endpoint and processing unsigned webhooks. MUST stay false in any real
# deployment. Absence of Razorpay keys alone no longer enables these — otherwise
# a production deploy that simply forgot to set keys would accept free payments.
ALLOW_INSECURE_PAYMENTS = os.getenv("ALLOW_INSECURE_PAYMENTS", "").lower() in ("1", "true", "yes")

# Explicit opt-in for printing OTP codes to the server log instead of sending
# them by SMS. Local development only. Without it, and without MSG91 keys, phone
# sign-in is switched off (send-otp returns 503) — the apps sign in with Google.
ALLOW_OTP_STUB = os.getenv("ALLOW_OTP_STUB", "").lower() in ("1", "true", "yes")

# ── Ops ──────────────────────────────────────────────────────────────────────
# Admin login is per-account (admin_users table + mandatory TOTP — see
# services/admin_auth.py), created with scripts/create_admin.py. There is no
# shared password any more.
#
# Short-lived on purpose: this is a staff dashboard used in a browser session,
# not a mobile app someone keeps signed into for weeks. A stolen laptop with a
# browser left logged in is dead within hours, not a month.
ADMIN_TOKEN_TTL_HOURS = int(os.getenv("ADMIN_TOKEN_TTL_HOURS", "12"))

# How many X-Forwarded-For entries, counted from the right, our own proxies
# append. The client's real address is that entry; anything further left came
# from the client and is not trusted. 1 = Cloud Run serving its run.app URL
# directly. Set 2 if an external HTTPS load balancer is put in front.
TRUSTED_PROXY_HOPS = max(1, int(os.getenv("TRUSTED_PROXY_HOPS", "1")))

# Phone sign-in only sends SMS to these country codes. Every OTP is a paid SMS,
# and an open international range is what SMS-pumping fraud farms: request
# codes to premium-rate numbers, collect a share of the termination fee.
OTP_ALLOWED_COUNTRY_CODES = [
    c.strip() for c in os.getenv("OTP_ALLOWED_COUNTRY_CODES", "+91").split(",") if c.strip()
]

# Shared secret for internal/cron endpoints (hold sweeper, payout runs).
CRON_SECRET = os.getenv("CRON_SECRET", "")

# How long a self-deleted patient account is retained before its personal data
# is purged. The grace window lets a user cancel by logging back in.
ACCOUNT_DELETION_GRACE_DAYS = int(os.getenv("ACCOUNT_DELETION_GRACE_DAYS", "30"))

# Demo login for App Store / Play review. Reviewers cannot receive the SMS OTP,
# so when this is enabled a hidden endpoint mints a session for a seeded demo
# account. MUST be false in a public production deployment.
DEMO_LOGIN_ENABLED = os.getenv("DEMO_LOGIN_ENABLED", "").lower() in ("1", "true", "yes")

# Legal document versions are no longer configured here: the published
# versions live in the legal_documents table (migration 0024, runbook §6c).
