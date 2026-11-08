# Changelog

## 1.1.0+2 — repair pass

A repair pass over 1.0.0. Full detail, including what could **not** be verified,
is in [`docs/REPAIR_CHANGELOG.md`](docs/REPAIR_CHANGELOG.md).

### Fixed — critical

* **Water reminder ids collided across days.** Ids were derived from the clock
  time only, so a 7-day horizon wrote the same id seven times and Android
  replaced the alarm each time: **96 of 112 alarms (86 %) were destroyed.** Ids
  are now unique per calendar occurrence.
* **Notification actions were lost when the app was not running.** The headless
  callback depended on static state the main isolate populated. It now opens its
  own database, writes transactionally, and deduplicates every action so a
  repeated delivery cannot double-count a glass of water.
* **Spoken reminders were a setting that did nothing.** No production code path
  consumed it, and a Dart TTS engine cannot run after Android kills the process.
  Speech is now native (Kotlin + `TextToSpeech` from a broadcast receiver) and
  works with the app closed.
* **The AI endpoint accepted unauthenticated requests with wildcard CORS.** It
  now requires a verified Firebase ID token, supports App Check, uses an origin
  allow-list, validates input, rate-limits per user and globally, and returns
  only opaque errors.

### Fixed — high

* `USE_EXACT_ALARM` removed: it is auto-granted, irrevocable, and Play-restricted
  to alarm-clock apps. `SCHEDULE_EXACT_ALARM` is the correct permission, and a
  refused exact alarm now retries inexactly instead of being lost.
* Restored `gradlew`, `gradlew.bat` and `gradle-wrapper.jar` from the official
  Gradle `v8.3.0` release (the version paired with AGP 8.1.0).
* `TimeChangeReceiver` now also handles boot and package-replacement, and re-arms
  native spoken reminders without waiting for Dart.
* Changing the glass sizes or the voice setting did not reschedule, so
  already-scheduled alarms carried stale amounts and never spoke.
* Scheduling had no ceiling; the horizon is now 5 days with a hard cap of 400
  pending alarms, because Android silently drops the overflow.
* `flutter_tts` removed — two speech paths was the root of the spoken-reminder
  bug.

### Database

* Schema **v1 → v2**, additive only: a `notification_actions` dedupe ledger.
  No existing table is altered, so no user record can be lost by upgrading.

### Tests

* 140 → **222** cases. New: notification ids (16), planner contract (27),
  action dedupe (13), a real-SQLite ledger/migration suite (10), spoken reminders
  (15), plus one AI-auth fallback case.

---

All notable changes to AKASHA. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); versions follow
[semantic versioning](https://semver.org/).

## [1.0.0] — 2026-11-08

First complete release. Offline-first, no account required.

### Hydration
- 16 default reminders: 09:00 → 12:00 AM hourly, **midnight included**
  (asserted verbatim in `test/unit/water_schedule_engine_test.dart`).
- Custom windows (start / end / interval), individual slot add / edit / delete /
  enable / disable, pause all, resume all, duplicate-safe restore defaults.
- Glass logging from the dashboard, the water screen, and notification actions
  with `manual` / `notification` / `snooze` / `quick_add` provenance.
- "Remind me later" snoozes persisted in SQLite and re-armed across restarts.
- Timeline, weekly and monthly charts, streaks, editable history.

### Medication
- Multiple medicines with multiple daily times, weekday masks and date ranges.
- States: scheduled / taken / skipped / snoozed / missed — `taken` is never
  inferred; unanswered doses reconcile to `missed` only after the day ends.
- Notification actions: I took it / Skip / Later.
- History with status filters; no dosage advice anywhere in the app.

### Mind & Soul
- 104 original supportive messages across 8 categories, favourites,
  anti-repetition rotation.
- Private journal with moods, tags, pinning and search.
- Mood check-ins with intensity and 7/30-day patterns.
- Structured overthinking helper (6 fields, saved reflections).
- Guided breathing, 4-4-6 pattern, haptics, <30 s sessions discarded.
- Gratitude journaling, three things per day.
- Little Love Notes.
- Optional AI companion: off by default, consent-gated, crisis-guarded on both
  client and server, honest offline fallback.

### Insight
- Daily wellness report, weekly and monthly reports, all computed from real rows.
- Calendar view with per-day drill-down.
- Reminder history showing what fired and what was done about it.

### Platform & privacy
- Biometric / device-credential app lock with a 2-minute grace period.
- Diagnostics: notification permission, exact alarms, battery optimisation, DND,
  full-screen-intent capability, pending reminder counts, rebuild + test actions.
- Reboot recovery, timezone/time-change rescheduling (native receiver + marker).
- JSON data export, per-record deletion, full wipe.
- Optional Firebase Auth + Firestore sync: durable queue, per-record
  last-writer-wins, tombstones, strict owner-only security rules.

### Notes on the build
- Local database uses `sqflite` instead of Drift to avoid a codegen step that
  would break first-open builds. Documented in `docs/DATABASE.md` §8.
- No bundled fonts or audio; system font + system TTS, with asset folders
  documented for adding Poppins later.
- Firebase is optional and disabled by default; the app ships with
  `LocalOnlyBackend`.
