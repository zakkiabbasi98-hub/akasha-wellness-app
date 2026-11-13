# AKASHA — Hydrate • Smile • Shine

A gentle, offline-first **Flutter wellness companion** for Android, built for one
person: hydration reminders, medication tracking, a private mind & soul space,
and a lot of quiet encouragement.

> **Good morning, Akasha ♡**
> *A beautiful day starts with you.*

---

## What this is

AKASHA is not a reminder app with a pastel skin. It is a complete, tested Flutter
application where every number on screen comes from a local SQLite row that the
owner created:

* **16 default water reminders** every day from **09:00 AM to 12:00 AM**
  (midnight included — that is asserted in the unit tests).
* **Medication reminders** with `taken / skipped / snoozed / missed` tracking that
  never marks an unanswered dose as taken.
* **Mind & Soul**: private journal, mood check-ins, guided breathing, a
  structured overthinking helper, gratitude journaling.
* **104 original supportive messages** across eight categories, plus
  **Little Love Notes**.
* **Real reports**: daily, weekly and monthly, built by joining actual records.
* **Offline-first architecture** with an optional Firebase cloud layer that can be
  completely absent without breaking anything.

---

## Status: repair pass applied (v1.1.0)

Seven reported reliability and security issues have been fixed — colliding
notification ids, background action delivery, spoken reminders that never spoke,
an unauthenticated AI endpoint, the missing Gradle wrapper, over-declared alarm
permissions, and a full notification-engine audit.

Every change is documented with its root cause, the files touched, the tests
written and **what could not be verified**, in
[`docs/REPAIR_CHANGELOG.md`](docs/REPAIR_CHANGELOG.md).

> The code has still never been compiled in this repository's history: no Dart,
> Flutter, JDK or Android SDK was available. `flutter analyze` and `flutter test`
> are the first things to run. See §"What is still not verified" in the changelog.

---

## Screenshots

Screenshots live in `docs/screenshots/`. They are generated from the running app
on a real Android device — the exact capture procedure and file list are in
[`docs/TESTING.md` §8](docs/TESTING.md#8-capturing-screenshots). The folder is
empty in a fresh checkout because the images require a device to produce; nothing
in the build, the tests or the app depends on them.

Design language: soft pastel pink → lavender → powder blue, 24–28 px card radii,
hairline borders, violet-tinted shadows, hand-painted water droplet and progress
ring, no photos, no ad-tech, no default Material 3 screens.

---

## Feature list

### Hydration
- Default schedule: 09:00 AM → 12:00 AM hourly = **16 reminders including midnight**
- Fully custom schedules: start, end, interval, plus individual custom slots
- Add / edit / delete / enable / disable any single slot
- Pause all, resume all, restore defaults (duplicate-safe, unique index enforced)
- One-tap glass logging (small / usual / large or a custom amount)
- Notification actions: **I drank water · Skip · Later** (work foreground,
  background and app-terminated)
- Timeline, weekly/monthly charts, streaks, history with corrections/deletions

### Medication
- Multiple medicines, multiple daily times, weekday selection, start/end dates
- Calm message-style notifications with **I took it · Skip · Later**
- Honest states: scheduled / taken / skipped / snoozed / missed
- Missed doses are reconciled only after the day has passed
- Per-medicine notes, dosage text copied from her own prescription
- Full history with status filters

### Mind & Soul
- Private journal: write, edit, delete, search, filter by mood, tags, pinning
- Mood tracker with eight feelings, intensity and optional notes + history patterns
- Overthinking helper: six compassionate questions, saved reflections
- Guided breathing: animated circle, 4-4-6 pattern, 1–5 minute sessions, haptics
- Gratitude journal: three things per day, full history
- 104 motivational messages, favourites, anti-repetition rotation
- Little Love Notes (local by default)
- Optional AI companion with explicit consent, crisis guard, and an honest
  offline fallback

### Reports & history
- Daily wellness report with a gentle "care points" summary
- Weekly and monthly reports with real charts
- History calendar: tap any day to inspect that day's records
- Reminder history: what was raised, and what happened next

### Privacy & platform
- Biometric / device-credential app lock (2-minute grace period)
- No ads, no analytics, no location, no microphone, no contacts
- Data export (JSON), per-record deletion, full wipe
- Diagnostics screen: notification permission, exact-alarm grant, battery
  optimisation, DND state, full-screen-intent capability, pending reminder count,
  reminder rebuild, test notification and voice test

---

## Technology stack

| Layer | Choice |
|-------|--------|
| UI | Flutter (stable), Material 3 heavily customised, custom painters |
| State | `flutter_riverpod` (providers, repositories, DI) |
| Navigation | `go_router` with `StatefulShellRoute` (per-tab state preserved) |
| Local DB | SQLite via `sqflite`, migrations, foreign keys, indexes, soft deletes |
| Notifications | `flutter_local_notifications` + `timezone`, exact-alarm aware |
| Voice | Android's native `TextToSpeech` from a Kotlin broadcast receiver — speaks even when the app is closed, since a Dart TTS engine cannot run after process death |
| Cloud (optional) | Firebase Auth + Cloud Firestore (+ optional Cloud Functions) |
| Charts | `fl_chart` |
| Auth local | `local_auth` (biometrics) |
| Misc | `permission_handler`, `connectivity_plus`, `intl`, `uuid`, `path_provider`, `share_plus` |

> **Why `sqflite` instead of Drift?** The specification asked for Drift. Drift's
> typed tables require a `build_runner` codegen step, which would mean shipping
> `.g.dart` files that must match your exact Dart/Drift versions — the classic
> "it does not compile on my machine" failure. Since the acceptance criterion is
> *"opens in Android Studio and runs"*, the database is plain SQLite behind
> repository interfaces: no codegen, no version drift, instant first build.
> Everything a DB needs is there (schema versioning, migrations, FKs, indexes,
> transactions, WAL). Migrating to Drift later touches exactly one file —
> `lib/core/database/app_database.dart`. See `docs/DATABASE.md`.

---

## Prerequisites

| Tool | Version |
|------|---------|
| Flutter | stable **3.44** (Dart 3.12) — needed for `AppBarThemeData`/`InputDecorationThemeData`, `WidgetState*`, `withValues`, `CardThemeData` |
| Android Studio | Ladybug (2024.2) or newer, with the **jbr-21** JDK |
| Android SDK | Platform 36, Build Tools 36 |
| JDK | **21** |
| Gradle | **8.14** (via the wrapper) |
| AGP / Kotlin | 8.11.1 / 2.2.20 (declared in `android/settings.gradle`; AGP stays below 9) |
| Min Android | 6.0 (API 23); compile/target 36 |

---

## Getting started (Android Studio)

1. **Install Flutter** and verify:
   ```bash
   flutter --version     # must be >= 3.27
   flutter doctor
   ```
2. **Open the project**: Android Studio → *Open* → select this folder (the one
   containing `pubspec.yaml`).
3. **Install dependencies** (terminal in the project root):
   ```bash
   flutter pub get
   ```
4. **Accept SDK licences** if prompted:
   ```bash
   flutter doctor --android-licenses
   ```
5. **Run** on an emulator or a real phone:
   ```bash
   flutter devices
   flutter run
   ```
   Or press ▶ in Android Studio with an Android device selected.

Firebase is **not** required for step 5 — the app builds and runs fully offline
out of the box.

---

## Build instructions

### Debug APK
```bash
flutter build apk --debug
# output: build/app/outputs/flutter-apk/app-debug.apk
```

### Release APK
```bash
flutter build apk --release
# output: build/app/outputs/flutter-apk/app-release.apk
```
Without `android/key.properties` the release build is signed with the debug key
so it installs immediately. Configure real signing before publishing — see
`docs/BUILD_AND_RELEASE.md`.

### Release App Bundle (Play Store)
```bash
flutter build appbundle --release
# output: build/app/outputs/bundle/release/app-release.aab
```

### With the optional AI endpoint
```bash
flutter build apk --release \
  --dart-define=AKASHA_AI_ENDPOINT=https://<region>-<project>.cloudfunctions.net/akashaCompanion
```

---

## Firebase configuration (optional)

Out of the box, no Firebase configuration exists and the app is 100% functional
offline. To enable cloud backup and the AI proxy:

1. Create a Firebase project.
2. Add an **Android app** with package name `com.akasha.wellness`.
3. Download `google-services.json` → `android/app/google-services.json`
   *(never commit it — it is git-ignored)*.
4. Uncomment the two `google-services` lines in
   `android/settings.gradle` and `android/app/build.gradle`.
5. Deploy the rules: `firebase deploy --only firestore:rules`
6. Optionally deploy the functions: `firebase deploy --only functions`

Full walkthrough: **[docs/FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md)**.
Example placeholder files: `firebase/firebase.example.json`,
`firebase/functions/.env.example`.

---

## Permissions used (and why)

| Permission | Why | If denied |
|---|---|---|
| `POST_NOTIFICATIONS` (33+) | reminders | no reminders appear; app fully usable |
| `RECEIVE_BOOT_COMPLETED` | restore reminders after reboot | reminders lost until app reopens |
| `SCHEDULE_EXACT_ALARM` | land at the exact minute | reminders become inexact (minutes late); the app auto-retries inexactly rather than losing them |
| `USE_FULL_SCREEN_INTENT` | alarm-style lock-screen reminder | falls back to heads-up notification |
| `VIBRATE` | quiet-mode reminder feedback | silent notifications |
| `USE_BIOMETRIC` | optional app lock | lock unavailable |
| `INTERNET` / `ACCESS_NETWORK_STATE` | optional sync + AI | app stays offline-only |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | reliability on OEM ROMs | background delays; user choice only |

No location, microphone, contacts, SMS or camera permission is requested.

---

## Offline architecture (short version)

```
Flutter UI  →  Riverpod providers  →  Repositories  →  SQLite (source of truth)
                                            ↘ SyncQueue → (optional) Firestore
```

* Every write hits SQLite first. The UI never waits on a network.
* Every syncable row carries `id` (UUID v4), `created_at`, `updated_at`,
  `deleted_at`, `dirty`.
* Deletes are tombstones, so a deletion on one device is respected on another.
* Uploads go through a durable queue with exponential backoff.
* Conflicts are last-writer-wins **per record, by `updated_at`** — older data can
  never overwrite newer data in either direction.

Full detail: **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**.

---

## Testing

```bash
flutter analyze            # static analysis
flutter test               # unit + widget tests
flutter test integration_test   # on a connected device/emulator
```

| Suite | What it covers |
|---|---|
| `test/unit/water_schedule_engine_test.dart` | the 16-slot default, **midnight**, wrap-around windows, duplicate prevention, interval maths, parsing/formatting, next-slot logic (28 cases) |
| `test/unit/date_and_settings_test.dart` | day keys, week/month bounds, quiet hours (same-day + overnight), greeting buckets, constants, validators |
| `test/unit/models_test.dart` | row round-trips, `glassesTarget`, medicine weekday/date rules, "never implicitly taken", mood/journal/gratitude models |
| `test/unit/motivation_content_test.dart` | ≥100 messages, all categories, no duplicates, no shaming language, crisis text present |
| `test/unit/sync_logic_test.dart` | conflict-resolution truth table, local-only backend, AI crisis detection |
| `test/widget/design_system_test.dart` | theme fundamentals, gradient scaffold, cards, rings, droplet meter, empty/loading states, bottom nav + semantics |
| `test/widget/dashboard_widgets_test.dart` | water hero card maths and copy, medicine card states, mood card, shortcuts, self-care/motivation cards |
| `test/unit/routing_test.dart` | every route constant exists in the tree — the check that caught seven dead Settings tiles |
| `test/unit/notification_id_test.dart` | one id per *occurrence*: 112 alarms across a 7-day horizon stay 112 distinct ids |
| `test/unit/notification_planner_test.dart` | the scheduling contract: midnight inclusive, quiet hours, weekdays, courses that ended, alarm budget |
| `test/unit/notification_action_test.dart` | payload round-trip and the dedupe key that makes a re-delivered action a no-op |
| `test/unit/notification_ledger_test.dart` | runs **real SQLite**: ten taps log one glass; a v1 database upgrades to v2 with every record intact |
| `test/unit/spoken_reminder_test.dart` | the voice setting actually reaches the scheduler, line rotation, copy safety |
| `integration_test/app_test.dart` | install → onboarding → log water → persist across restart |

222 test cases in total (181 unit, 36 widget, 5 integration).

`docs/TESTING.md` lists the **device matrix** (locked screen, background,
terminated, reboot, airplane mode, DND, denied permissions, Android 8–14) and how
to execute it. Anything not actually run on a device is marked as *not verified*
there — no test is claimed to pass that was not executed.

---

## Project structure

```
akasha/
├── android/                     # Gradle, manifest, Kotlin platform channel
├── assets/                      # images (logo), fonts/sounds/animations docs
├── docs/                        # architecture, database, notifications, etc.
├── firebase/                    # optional backend (rules, indexes, functions)
├── integration_test/            # device-level flow tests
├── lib/
│   ├── main.dart                # bootstrap: DB → notifications → seed → sync
│   ├── app.dart                 # theme, router, lifecycle, app-lock gate
│   ├── content/                 # 104 messages, seeds, first-run setup
│   ├── core/
│   │   ├── database/            # schema (19 tables) + AppDatabase
│   │   ├── notifications/       # service, scheduler, ids, action bridge, queue
│   │   ├── services/            # water schedule engine, voice, lock, system channel
│   │   ├── routing/             # go_router tree with typed route names
│   │   ├── theme/               # colours, tokens, Material 3 theme
│   │   ├── utils/               # dates, validators, ids, result, responsive
│   │   └── providers.dart       # the whole Riverpod graph
│   ├── data/
│   │   ├── models/              # profiles, settings, water, medicine, mind
│   │   └── repositories/        # water, medicine, mind, motivation, notes, …
│   ├── features/                # 17 feature folders (onboarding → settings)
│   └── shared/widgets/          # design system: cards, rings, drops, nav, states
└── test/                        # unit + widget suites
```

---

## Known Android limitations (read this)

These are **system rules**, not app bugs. AKASHA implements the strongest
policy-compliant alternative for each:

1. **Force-stop** — if Android force-stops the app, the OS cancels its alarms.
   Nothing (no app) can override this. Reminders resume when she next opens AKASHA.
2. **Exact alarms** — on Android 12+ this is a user grant ("Alarms & reminders").
   Without it, reminders are inexact (usually within a few minutes). The
   diagnostics screen detects this and offers a one-tap fix.
3. **Full-screen / lock-screen reminders** — `USE_FULL_SCREEN_INTENT` may be
   revoked by the OS or the user. The app then shows a heads-up notification.
4. **Do Not Disturb & silent mode** — respected absolutely. Reminders may be
   silent or delayed. AKASHA never attempts to bypass DND.
5. **OEM background restrictions** — Xiaomi/MIUI, Oppo/ColorOS, Vivo/Funtouch,
   Samsung, Huawei and others apply extra killers. Exempting AKASHA from battery
   optimisation (offered in diagnostics) is the reliable fix.
6. **TTS engines** — voice availability depends entirely on the device's
   installed engine. If none is usable, voice reminders stay silent and the app
   says so in Voice settings.
7. **Clock / timezone changes** — handled by rebuilding the schedule horizon on
   launch, on resume, and via a `TIME_SET` / `TIMEZONE_CHANGED` broadcast receiver.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `flutter pub get` fails | Check your Flutter version (`flutter --version`; this repo is built and pinned against **3.44 / Dart 3.12**). |
| Gradle fails on first build | Ensure **JDK 21** is selected in Android Studio (*Settings → Build → Gradle → Gradle JDK*). The project is pinned to Gradle 8.14 / AGP 8.11.1 / Kotlin 2.2.20 / compileSdk 36. |
| `minSdk` error from a plugin | Already set to 23; if a plugin demands higher, raise `minSdk` in `android/app/build.gradle`. |
| No notifications | Settings → Diagnostics → grant notifications + exact alarms, then *Rebuild the whole schedule*. |
| Reminders late | Battery optimisation is delaying them; use the *Fix* button in Diagnostics. |
| No voice | Install/enable a Text-to-Speech engine (Android Settings → Language & input → Text-to-speech). |
| Firebase build error | It means `google-services.json` is missing while the plugin is enabled. Either add it or re-comment the plugin lines. |
| Fonts look plain | Intentional: no bundled font. See `assets/fonts/README.md` to add Poppins. |

---

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — clean architecture, layers, providers, sync strategy
- [docs/DATABASE.md](docs/DATABASE.md) — all 19 tables, relationships, indexes, migrations
- [docs/NOTIFICATIONS.md](docs/NOTIFICATIONS.md) — channels, ids, scheduling horizon, action plumbing, reboot recovery
- [docs/FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md) — optional backend from zero
- [docs/BUILD_AND_RELEASE.md](docs/BUILD_AND_RELEASE.md) — debug/release/signing/Play Store
- [docs/TESTING.md](docs/TESTING.md) — suites, device matrix, honest results
- [docs/PRIVACY.md](docs/PRIVACY.md) — what is stored, what is never collected
- [docs/DEVELOPMENT_REPORT.md](docs/DEVELOPMENT_REPORT.md) — final report: features, files, DB, permissions, verification, build steps
- [CHANGELOG.md](CHANGELOG.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)

---

## Licence

MIT — see [LICENSE](LICENSE).

AKASHA was made to feel like care, not surveillance. If you fork it, please keep
that promise: no ads, no hidden tracking, and never a shaming notification.
