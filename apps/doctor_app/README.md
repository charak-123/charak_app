# Charak Partner — doctor app

CHARAK Doctor App (Flutter), running the ink scheme of CHARAK Design System V2.

The doctor side of Charak. A doctor signs up, submits their licence for
verification, configures a live practice (channels, schedule, service radius,
pricing), then receives patient requests, calls to clarify, treats, bills, and
sees what they have earned.

UI is built entirely from the shared components in `packages/charak_core` —
this app declares no fonts or brand assets of its own. Before changing any
screen, read [`design-system/README.md`](../../design-system/README.md) (the
spec) and the root `CLAUDE.md` (the rules and checks).

## Running it

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
flutter analyze
```

`API_BASE_URL` is the only define the app needs. It authenticates with a
FastAPI JWT and reaches everything through the backend — there is no
client-side Supabase access, because the apps carry no Supabase auth session
and every RLS policy is written against `auth.uid()`.

`10.0.2.2` is the Android emulator's route to the host, where `backend/` runs.
`scripts/run-app.sh doctor` at the repo root does this for you, pointed at
this machine's LAN address instead, which is what a real phone needs.

## Layout

```
lib/
  router.dart          go_router routes, the auth redirect, push-tap routing
  screens/
    auth/              phone entry → OTP
    onboarding/        profile, verification submission, pending
    setup/             channels, online consult, home visit, pricing, schedule
    home/              the four-tab shell: requests, schedule, earnings, profile
    requests/          request detail, clarification call, active visit
```

Anything shared with the patient app — design tokens, the API client, auth,
components, the call session, push — lives in `packages/charak_core`, not here.

## Things worth knowing

- **State** is Riverpod. The router is built once (`ref.read`, never `ref.watch`
  — see the comment in `router.dart`), and reads fresh auth state per
  navigation instead.
- **Where a doctor lands on launch** is decided by `splash_screen.dart` from
  `/doctors/me`: no profile → profile setup, no licence *and* document →
  verification, pending → the waiting screen, no channels → setup, else home.
- **Files never go to Supabase Storage from the client.** These apps
  authenticate with a FastAPI JWT rather than a Supabase auth session, so RLS
  rejects a direct write. Photos and verification documents go through
  `POST /uploads/...` via `ApiClient.postFile`.
- **The requests tab and verification-pending screen poll, not stream.**
  Supabase Realtime cannot work here for the same RLS reason above — see
  `CharakPoller` in `charak_core`. Push is the immediate signal when configured;
  polling is the safety net.
- **Video calls degrade cleanly.** Without `AGORA_APP_ID` /
  `AGORA_APP_CERTIFICATE` the backend mints a stub token, no engine is created,
  and the call screen says so rather than hanging on "Connecting…".
- **Push degrades cleanly too.** Without `google-services.json` Firebase fails
  to initialize, `CharakPush` records why, and the app runs without
  notifications. See `docs/runbooks/backend_go_live.md`.

## Tests

Shared logic is tested in `packages/charak_core/test`; the backend contract
these screens depend on is covered by `backend/tests`.
