#!/usr/bin/env bash
#
# Run a Charak app on a connected device.
#
#   scripts/run-app.sh doctor              # debug, on the only connected device
#   scripts/run-app.sh patient -d <id>     # pick a device
#   scripts/run-app.sh doctor --release    # anything after the app name is
#                                          # passed straight to `flutter run`
#
# The apps no longer talk to Supabase directly — they authenticate with a
# FastAPI JWT and reach everything through the backend, so API_BASE_URL (plus
# the Google client id, read from backend/.env) is all they need. A phone on Wi-Fi cannot reach the host's localhost, so
# it defaults to this machine's LAN address rather than 10.0.2.2 (which is
# emulator-only).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP="${1:-}"
case "$APP" in
  doctor)  APP_DIR="$ROOT/apps/doctor_app" ;;
  patient) APP_DIR="$ROOT/apps/patient_app" ;;
  *) echo "usage: $(basename "$0") {doctor|patient} [flutter run args...]" >&2; exit 2 ;;
esac
shift

# Where the phone should look for the backend. Over USB, `adb reverse` maps the
# phone's own localhost:8000 to this machine, which works even when the Wi-Fi
# router blocks phone-to-PC traffic. Without a USB device, use the LAN address.
if [[ -z "${API_BASE_URL:-}" ]] && command -v adb >/dev/null \
   && adb get-state >/dev/null 2>&1 && adb reverse tcp:8000 tcp:8000 >/dev/null 2>&1; then
  API_BASE_URL="http://127.0.0.1:8000"
fi
if [[ -z "${API_BASE_URL:-}" ]]; then
  LAN_IP="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
  if [[ -z "$LAN_IP" ]]; then
    echo "Could not work out this machine's LAN address — set API_BASE_URL yourself." >&2
    exit 1
  fi
  API_BASE_URL="http://$LAN_IP:8000"
fi

# Google Sign-In wants the *Web* OAuth client id, the same one the backend
# checks tokens against, so default to the first id in backend/.env.
if [[ -z "${GOOGLE_SERVER_CLIENT_ID:-}" && -f "$ROOT/backend/.env" ]]; then
  GOOGLE_SERVER_CLIENT_ID="$(sed -n 's/^GOOGLE_CLIENT_IDS=//p' "$ROOT/backend/.env" | cut -d, -f1 | tr -d ' ')"
fi

echo "app          : $APP"
echo "API_BASE_URL : $API_BASE_URL"
echo "Google client: ${GOOGLE_SERVER_CLIENT_ID:-<unset: Google sign-in disabled>}"
echo

# Fail early and clearly rather than after a two-minute build.
if ! curl -fsS --max-time 3 "${API_BASE_URL/127.0.0.1/localhost}/healthz" >/dev/null 2>&1; then
  echo "WARNING: $API_BASE_URL is not answering."
  echo "  Start it with:  cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000"
  echo "  --host 0.0.0.0 matters: bound to 127.0.0.1 the phone cannot reach it."
  echo
fi

cd "$APP_DIR"
exec flutter run \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=GOOGLE_SERVER_CLIENT_ID="${GOOGLE_SERVER_CLIENT_ID:-}" \
  "$@"
