# AKASHA — Firebase setup (optional)

**You do not need any of this to use AKASHA.** The app ships with an offline-first
architecture and a `LocalOnlyBackend`, so water logging, reminders, medicine
tracking, journaling, mood, breathing, reports and the calendar all work with the
phone in aeroplane mode forever.

This guide adds two things:

1. **Cloud backup & multi-device sync** (Firestore + Auth)
2. **The AI companion's real replies** (a Cloud Function that holds the API key)

Neither step is required. Do them in order, and skip anything you do not want.

---

## 0. What you need

| Tool | Install |
|---|---|
| A Google account | — |
| Node.js 20 | https://nodejs.org |
| Firebase CLI | `npm install -g firebase-tools` |
| The Android package name | `com.akasha.wellness` (already set) |

---

## 1. Create the project

1. <https://console.firebase.google.com> → **Add project** → name it e.g. `akasha`.
2. Google Analytics is **not** needed. Turning it off is recommended: AKASHA
   promises no analytics.
3. Wait for provisioning, then open the project.

---

## 2. Register the Android app

1. Project overview → **Add app** → Android.
2. Android package name: **`com.akasha.wellness`** (must match exactly).
3. App nickname: `AKASHA`.
4. Debug signing SHA-1 is only needed for Google Sign-In. This app uses email +
   password, so you can skip it. (If you later add Google Sign-In, get it with
   `cd android && ./gradlew signingReport`.)
5. **Download `google-services.json`** and place it at:

   ```
   android/app/google-services.json
   ```

   It is already listed in `.gitignore`. **Never commit it.**

---

## 3. Enable Authentication

1. Build → **Authentication** → *Get started*.
2. **Sign-in method** → **Email/Password** → Enable → Save.
3. Optional: *Settings → User actions* → enable email verification if you want it.

Anonymous auth is not used; a cloud account is a deliberate, explicit choice.

---

## 4. Create Firestore

1. Build → **Firestore Database** → *Create database*.
2. **Production mode** (rules are deployed in the next step; they are not the
   defaults).
3. Location: the one closest to you. This cannot be changed later.
4. Do **not** enable multi-region for a personal app.

---

## 5. Deploy the security rules and indexes

From the repository root:

```bash
firebase login
firebase use --add            # select your project, alias it "default"

# Deploy rules + indexes only (fast, no code upload)
firebase deploy --only firestore:rules,firestore:indexes
```

What the rules enforce (`firebase/firestore.rules`):

* **Deny by default.** Anything not explicitly allowed is refused.
* A signed-in user can only read/write `users/{their-own-uid}/**`.
* Every record must carry `id` (string, <80 chars) and `updated_at` (int), and may
  not exceed 40 fields — a malformed or hostile client cannot store a 10 MB
  journal body.
* Subcollections are white-listed to exactly the entities the app syncs:
  `water_logs`, `water_reminders`, `medicines`, `medicine_logs`, `mood_entries`,
  `journal_entries`, `gratitude_entries`, `breathing_sessions`, `reflections`,
  `love_notes`.
  Notification history and AI conversations are deliberately **not** synced: the
  first is device-specific, the second should never leave the phone.
* Deletion is a **tombstone update** (`deleted_at` set, `updated_at` bumped), which
  the rules allow; a hard delete is also permitted on her own records so cloud
  deletion actually removes data when she asks for it.
* Nothing is readable by another account, by an API key, or by an unauthenticated
  request.

The indexes file (`firebase/firestore.indexes.json`) contains the composite
indexes used by the sync queries (`day_key` + `updated_at` on `water_logs`,
`medicine_logs` and `journal_entries`). Deploying them avoids
the "the query requires an index" error on first sync; Firestore's console link in
that error also works if you prefer clicking.

---

## 6. Enable the app's Firebase plugin lines

Two lines are commented out so that people **without** Firebase config can still
build. Uncomment both:

`android/settings.gradle`
```gradle
id "com.google.gms.google-services" version "4.4.2" apply false
```

`android/app/build.gradle`
```gradle
id "com.google.gms.google-services"
```

Then:

```bash
flutter clean
flutter pub get
flutter run
```

> If you enable these plugin lines **without** `google-services.json` in place, the
> build fails with `File google-services.json is missing`. That error means exactly
> what it says.

### Tell the app where the backend is

The app's Firebase classes are plain Dart over the `firebase_*` packages; there is
no pinned project id in the code. `FirestoreBackend.tryCreate()` calls
`Firebase.initializeApp()` and, if it throws (no config), falls back to
`LocalOnlyBackend` and Settings → Cloud backup shows "not configured on this
build". Nothing else changes.

---

## 7. (Optional) Deploy the AI Cloud Function

The companion is **off by default** and needs an endpoint. The function keeps the
model key server-side; the app never contains a secret.

```bash
cd firebase
npm --prefix functions install

# Set the provider key as a secret (never in a file, never committed)
firebase functions:secrets:set AI_PROVIDER_KEY

# Optional: point at a specific model/provider base URL
firebase functions:secrets:set AI_BASE_URL

# Deploy
firebase deploy --only functions
```

The function name is `akashaCompanion` (Node 20, region `us-central1` — change the
region in `index.js` if you prefer something closer).

Then build the app with the endpoint baked in:

```bash
flutter build apk --release \
  --dart-define=AKASHA_AI_ENDPOINT=https://us-central1-<project>.cloudfunctions.net/akashaCompanion
```

Without that `--dart-define`, the companion screen runs `localReflection` — a real,
deterministic reflective-prompt generator — and labels itself as offline. It is a
supported mode, not an error state.

### What the function does

1. Applies **strict CORS** — an `ALLOWED_ORIGINS` allow-list, never `*`.
2. Requires a **verified Firebase ID token** (`Authorization: Bearer …`). The
   identity comes from the verified token; **no uid is read from the body**.
3. Optionally requires a valid **App Check** token (`ENFORCE_APP_CHECK=true`).
4. Validates the request: message ≤1 200 chars, ≤10 history items of ≤1 200
   chars, roles limited to `user`/`assistant`.
5. **Re-checks crisis language server-side** before any model call. On a hit it
   returns the fixed supportive message and emergency guidance — no generation.
6. Applies **rate limits**: 6 requests/minute and 120/day per user (sliding
   window in Firestore), plus a global 600/minute circuit breaker.
7. Applies a system prompt that forbids diagnosis, dosage advice and shame.
8. Calls an OpenAI-compatible chat-completions endpoint with the secret key,
   with a 20 s abort timeout.
9. Returns `{ reply }`, truncating anything over the response cap.
10. Returns only opaque error codes (`companion_unavailable`, `temporary_failure`)
    — provider status and internal detail are logged, never sent to the client.
11. Never logs message content.

### Required configuration before the AI endpoint is safe

| Setting | Where | Why |
|---|---|---|
| `AI_PROVIDER_KEY` | `firebase functions:secrets:set AI_PROVIDER_KEY` | keeps the key in Secret Manager, never in a file or the APK |
| `ALLOWED_ORIGINS` | `firebase/functions/.env` | comma-separated origins; a browser request from any other origin gets 403. The Android app sends no `Origin` header and needs no entry |
| `ENFORCE_APP_CHECK` | `.env` | leave `false` until the Android app is registered with **Play Integrity** in the Firebase console — turning it on too early rejects every request |

`firebase/functions/.env.example` contains placeholders only. Never commit `.env`.

### Authentication: what the app must send

The client must attach a fresh ID token per request; the function verifies it
with revocation checking enabled. A request without one receives `401
auth_required` and is never forwarded to a model. This is what stops a stranger
with the URL from spending the project's budget.

### Firestore rules

`firebase/firestore.rules` enforces: per-user scoping on every path, an explicit
entity allow-list (an unlisted subcollection is denied), required-field
validation on create **and** update, a `user_id`-must-match-the-authenticated-user
check, a document-size bound, `recordId == data.id`, `ai_rate_limits` completely
client-inaccessible, and a catch-all deny.

**Not executed here.** Validating rules requires `firebase emulators:start`,
which needs a JDK. Run the emulator suite before deploying to production.

Client-side, `AiCompanionService.detectSafety()` performs the same check first, so
a crisis message never even leaves the phone in the normal case.

---

## 8. Testing the cloud layer

```bash
firebase emulators:start    # auth 9099, firestore 8080, functions 5001, ui 4000
```

Then run the app with the emulator host, or point the Firestore client at it in
`FirestoreBackend` during development. A typical manual pass:

1. Settings → Cloud backup → **Enable** → accept the consent dialog.
2. Create an account with an email you control.
3. Tap **Sync now** → `SyncPhase` reports progress and then success.
4. Check the Firestore console → `users/{uid}/water_logs` contains your real rows.
5. Log a glass on device A, open device B, tap **Sync now** → the glass appears.
6. Delete a record on device B, sync both → the tombstone wins on A.
7. Settings → Cloud backup → **Delete cloud data** → the subtree is gone.

### Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `[cloud_firestore/unavailable]` | no network / emulator off | expected; the app queues and stays usable |
| `permission-denied` | rules deployed to the wrong project, or not signed in | `firebase use`, re-deploy, sign in again |
| `The query requires an index` | indexes not deployed | `firebase deploy --only firestore:indexes` |
| `File google-services.json is missing` | plugin enabled without config | add the file or re-comment the plugin |
| `Failed to load FirebaseOptions` | package name mismatch | the Android app in Firebase must be `com.akasha.wellness` |
| Function returns 401 | `AI_PROVIDER_KEY` not set | `firebase functions:secrets:set AI_PROVIDER_KEY` |
| Function returns 500 | provider base URL/model wrong | check `AI_BASE_URL` and the function logs |

---

## 9. Cost

Everything here fits comfortably in Firebase's free tier for a single person:
Firestore's 1 GiB storage and 50k reads/day are far beyond a wellness journal, and
Cloud Functions' free invocations cover a lot of companion messages. If you do not
want any risk, leave Firebase unconfigured — the app is complete without it.
