# Phase 3 — on-device test script

The last two Phase 3 items are verification, not construction: the senior-review
flow and a full scripted run. This is the script to follow with a phone in hand.

Everything below works **without** Agora or Firebase credentials — the call
screens say "Dev stub · Agora not configured" and no push arrives. Sections
marked **[needs credentials]** are the only ones that do not.

---

## 0. Setup

**Phone:** Developer options → USB debugging on, plug in, accept the RSA prompt.
Confirm with `flutter devices` — the phone should be listed.

**Backend**, bound so the phone can reach it (not `127.0.0.1`):

```bash
cd backend && .venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
```

**Apps:**

```bash
scripts/run-app.sh doctor       # or: patient
```

The script reads Supabase config from `backend/.env` and points the app at this
machine's LAN address. Same Wi-Fi for phone and laptop. If the phone cannot
reach the backend, check the host firewall on port 8000 first — that is the
usual cause.

Two phones is the comfortable setup (doctor on one, patient on the other). One
phone works if you run the patient app on an emulator or swap builds between
steps.

---

## 1. Doctor onboarding

| # | Do | Expect |
|---|---|---|
| 1.1 | Launch, enter phone, submit OTP | Lands on profile setup |
| 1.2 | Name + specialty, **skip the photo**, Continue | Saves; verification screen |
| 1.3 | Enter licence number only | **Submit stays disabled** — the document is required now |
| 1.4 | Attach a PDF or photo | Submit enables |
| 1.5 | Submit | "Verification Pending" screen |
| 1.6 | Kill and relaunch the app | Returns to Verification Pending, not to the start |

Check the document actually landed — it should be readable by ops and nobody
else:

```bash
# as ops
curl -s -H "Authorization: Bearer $OPS_TOKEN" \
  localhost:8000/uploads/doctor/<doctor_id>/verification-document
```

| # | Do | Expect |
|---|---|---|
| 1.7 | Approve the doctor in the admin dashboard | |
| 1.8 | Relaunch the doctor app | Goes to channel setup, not back to Pending |
| 1.9 | Set channels, schedule, radius, pricing — **including the senior-review threshold** | Home shell, Requests tab |

> Set the threshold low (say ₹1,000). Step 4 depends on crossing it.

### Photo upload

Retry 1.2 with a photo. It must appear in the profile tab and in the patient
app's directory. This previously wrote to Supabase Storage from the client and
silently failed every time; it now goes through the backend.

---

## 2. A live request

| # | Do | Expect |
|---|---|---|
| 2.1 | On the patient app, book this doctor | |
| 2.2 | Watch the doctor's Requests tab **without touching it** | The request slides in on its own (Supabase Realtime) |
| 2.3 | Open the request | Intake, photos, voice transcript, AI summary all render |
| 2.4 | Confirm the address | **Hidden** until accept — this is deliberate |

---

## 3. The clarification call

| # | Do | Expect |
|---|---|---|
| 3.1 | Tap "Call patient" | Call screen opens; subtitle reads **"Dev stub · Agora not configured"**; timer runs |
| 3.2 | Type a note, End call | Toast "Call note saved"; returns to the request |
| 3.3 | Call again, "Mark missed" | Call recorded as missed |

**[needs credentials]** With `AGORA_APP_ID` / `AGORA_APP_CERTIFICATE` set and
both apps restarted:

| # | Do | Expect |
|---|---|---|
| 3.4 | Doctor taps "Call patient" | Android asks for camera + mic once; self-view shows the doctor's camera |
| 3.5 | Patient opens the call | Each side fills with the other's video; the name strip moves to the bottom-left |
| 3.6 | Toggle mute, then camera | The other side loses audio, then video; the self-view falls back to the camera glyph |
| 3.7 | End the call | Both sides leave cleanly — no frozen frame, no audio still running |

The doctor joins as uid 0 and the patient as 1001, both on
`charak_<first 8 of booking id>`. If one side sees nothing, check they agree on
that channel before suspecting the SDK.

---

## 4. Visit and senior review

| # | Do | Expect |
|---|---|---|
| 4.1 | Accept the request | Patient's address becomes visible |
| 4.2 | Navigate button | Opens maps at the patient's address |
| 4.3 | "Running late" | Patient is notified |
| 4.4 | Tick procedures **over the threshold** | Running total updates live; senior-review banner appears |
| 4.5 | Mark Visit Complete | |
| 4.6 | Earnings tab | Shows **"Awaiting senior review — ₹X"**; the amount is *not* in the total |
| 4.7 | Approve the bill in the admin dashboard | |
| 4.8 | Earnings tab | Amount moves from pending into the total |

Repeat 4.4–4.6 with a bill **under** the threshold: it should be approved
immediately and count straight away.

This whole path is covered by `backend/tests/test_e2e_phase3.py`. What the phone
adds is the parts tests cannot see: that the banner appears, that the total is
right on screen, and that the earnings tab updates without a manual refresh.

---

## 5. Push notifications **[needs credentials]**

Needs a Firebase project and a `google-services.json` per app — see
`backend_go_live.md` §3. Until then the apps run normally and receive nothing.

| # | Do | Expect |
|---|---|---|
| 5.1 | Log in on the doctor app | `doctors.fcm_token` is populated for that doctor |
| 5.2 | Background the app, have the patient book | Notification arrives |
| 5.3 | Tap it | Opens **that request**, not the requests list |
| 5.4 | Patient app, backgrounded, doctor accepts | Notification opens the **payment** screen |
| 5.5 | Approve a reviewed bill | Doctor's notification opens the **earnings** tab |
| 5.6 | Log out | `fcm_token` is cleared — the next user of the phone must not get the previous doctor's requests |

Routing is unit-tested in each app's `test/push_routes_test.dart`; 5.3–5.5 are
checking delivery, not the mapping.

---

## 6. Things that have bitten before

- **Backend on `127.0.0.1`** — phone cannot reach it. Use `--host 0.0.0.0`.
- **`10.0.2.2`** is the emulator's route to the host and means nothing on a real
  phone. `scripts/run-app.sh` handles this; a hand-rolled `flutter run` may not.
- **Expired JWT** — any screen 401s and the app bounces to login. Expected.
- **A permission denied once** is remembered. Clear app data to be asked again.
- **Disk** — a full Android build needs ~3 GB. `flutter clean` between apps if
  the machine is tight.
