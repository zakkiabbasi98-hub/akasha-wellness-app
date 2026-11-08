# Changelog

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
