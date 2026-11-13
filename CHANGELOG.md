# Changelog

## Unreleased — first-run blocker repair

"Begin my journey" failed every time with
*"Something interrupted the system. Please try once more."* Four defects, one
of which affected **every table** rather than the two in the logs.

### Fixed — critical

* **`NOT NULL constraint failed: users.created_at` / `water_reminders.created_at`.**
  Root cause: every model's `toRow()` called `AppDatabase.stamp({...})` without
  `isInsert: true`, and no model ever emitted `created_at`, so **all 20 tables**
  failed on insert — the profile and the water slots were just the first two.
  Rows are now built with `insertRow()` (always carries `created_at`) and update
  patches with `touch()` (never rewrites it). Covered by
  `test/unit/first_run_repair_test.dart`.
* **`cannot start a transaction within a transaction`.** Root cause: seeding,
  onboarding and the notification executor each opened a transaction and then
  called repository methods that opened their own. `Database.transaction` is not
  re-entrant. Every write method now takes `Transaction? txn`, and
  `AppDatabase.write(txn, …)` joins the caller's transaction instead of starting
  a second one. First-run seeding is a single transaction, so a failure rolls the
  whole run back and onboarding is never marked complete on a half-seeded
  database.
* **The first-run error was swallowed.** `_finish()` caught everything and showed
  a generic toast, discarding the exception and stack trace. Both are now logged
  (`debugPrint('AKASHA onboarding failed: $e\n$st')`), a database failure gets a
  specific user-facing message, and the flow verifies `onboarded_at` was actually
  persisted before navigating.
* **`ListTile background color or ink splashes may be invisible`.** Root cause:
  `SoftCard` painted its white fill with a `Container`/`DecoratedBox` between the
  ListTiles and the nearest `Material`. The card's chrome now lives *on* a
  `Material` (fill = `color`, 24px radius + hairline = `shape`, violet shadow =
  a colourless `DecoratedBox` behind it), so ink and selected rows paint
  correctly. The design is unchanged.

### Fixed — high

* **Restoring the default water schedule could never work twice.**
  `idx_water_reminders_slot` was `UNIQUE(user_id, minute_of_day)` without
  excluding soft-deleted rows, so a tombstone kept its minute reserved forever.
  Replaced (migration v2 → v3) by a partial index on live rows; tombstones have
  their minute parked above 1440.
* **`INSERT OR REPLACE` reset `created_at`.** Repositories now use an upsert that
  keeps the original creation time, and can revive a soft-deleted row with the
  same deterministic id instead of silently skipping it.
* **Sync pulled Firestore documents straight into SQLite.** A document carrying
  `server_updated_at` (a Firestore Timestamp) or missing required columns aborted
  the whole pull with `NOT NULL constraint failed`. Remote rows are now
  normalised against the real table shape (`PRAGMA table_info`) and skipped with
  a log line if they genuinely cannot be applied.
* **`markShown` / `markDelivered` used `rawQuery` to run an `UPDATE`** and never
  set `dirty`, so rotation counters and delivery counts never synced.
* **App lock could be skipped on a cold start**: `_evaluate()` read
  `settingsProvider.valueOrNull`, which is null while loading and was treated as
  "lock disabled".

### Changed

* Schema version **3** (additive repair migration; no data is deleted).
* `SeedService` now requires the `AppDatabase` and is idempotent by content, so
  an interrupted seed cannot duplicate the message library.
* If SQLite cannot be opened at all, the app shows a retry screen instead of a
  blank one — and never deletes the database to "recover".

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
  Gradle `v8.14.0` release (the version paired with AGP 8.11.1).
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
