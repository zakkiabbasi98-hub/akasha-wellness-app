# AKASHA — Repair changelog

**Version:** 1.1.0 (repair pass over 1.0.0)
**Date:** 8 November 2026
**Branch:** `arena/30e7366d-akasha-wellness-app`
**Scope:** the seven reported issue groups, plus the additional notification,
database, offline and code-quality audits requested with them.

> **Status of verification — read this before the detail.**
>
> This repair was carried out in an environment with **no Flutter SDK, no Dart
> SDK, no JDK, no Android SDK and no emulator**. Therefore:
>
> * ❌ `flutter analyze` was **not** run
> * ❌ `flutter test` was **not** run
> * ❌ `flutter build apk` was **not** run
> * ❌ nothing was installed on a device or emulator
>
> What *was* done: the code was read, the root causes were identified, the
> fixes were written, and every claim below was checked by static analysis over
> the real files (brace/paren balance with a comment- and string-aware lexer,
> import resolution, symbol existence, duplicate-id analysis, Kotlin/JS syntax
> where a parser was available). Where a statement could not be verified here it
> says so explicitly. **No test result in this document is a claim that a test
> passed** — the tests were written to be run on your machine, and §9 of the
> report lists the exact commands.

---

## R1 — Water notification ids collided across days

**Original issue.** Water reminder ids were derived only from the time of day
(`waterBase + minuteOfDay`). The scheduler materialises a multi-day horizon, so
the same id was written once per day.

**Root cause.** The id function had no notion of a calendar date. `zonedSchedule`
with an existing id replaces the pending alarm rather than adding one, so the
7-day loop destroyed six of every seven reminders. What reached the device was
one alarm per slot, on the last day of the horizon. The observed symptom — "no
reminders today, and they reappear a week from now" — is the signature of this
bug, and it also explains why reminders sometimes fired once and never again.

**Files modified**

| File | Change |
|---|---|
| `lib/core/notifications/notification_ids.dart` | Rewritten. Ids are now `base + dayIndex * 2048 + minuteOfDay`, laid out structurally so collisions are impossible within a band. Bands widened and reordered; `maxId` and per-band predicates added. |
| `lib/core/notifications/notification_planner.dart` | **New.** Pure planner: every alarm the app registers is decided here, including the per-day id. |
| `lib/core/notifications/reminder_scheduler.dart` | Rewritten to consume the planner and perform only side effects. |
| `lib/core/notifications/notification_service.dart` | Rewritten: schedules a `PlannedAlarm` (which carries its own id) instead of computing ids at call sites. |
| `lib/core/constants/app_constants.dart` | Removed a **second, conflicting** set of id-band constants (`idWaterBase = 10000`, …) that nothing used but which invited exactly this class of bug. |

**Measured.** Re-implementing both schemes and simulating the 7-day build
confirms the impact rather than assuming it: the old scheme performs 112 writes
but ends with **16 distinct ids — 96 of 112 alarms (86 %) destroyed**, all of
them landing on the last day of the horizon. The new scheme performs the same
112 writes and keeps **all 112**.

**Fix implemented.**

* Every recurring alarm id includes the calendar day, computed from the **UTC**
  calendar date so a DST transition cannot shift an id and duplicate an alarm.
* Water, encouragement and love notes use a structural layout
  (`dayIndex * 2048 + minute`), so two occurrences cannot collide by
  construction — not by hoping a hash is wide enough.
* Medicine and snooze ids must distinguish opaque string keys, so they use a
  30-bit FNV-1a fold into a 500M / 100M band. Exact birthday probabilities for
  a pessimistic 180 pending medicine alarms: **0.0032 % (≈1 in 31 000)** now,
  versus **7.74 % (≈1 in 13)** in the old 200k band. For the typical 60 alarms
  it is 0.0004 % versus 0.88 %.
* Snooze ids live in their own band and are derived from the snooze row id, so a
  snooze can **never** overwrite the next regular reminder.
* `AppConstants.scheduleHorizonDays` reduced 7 → 5 and a hard
  `maxPendingAlarms = 400` ceiling added; the scheduler refuses to register past
  it rather than letting Android silently drop the overflow.
* The midnight slot (minute `0`) is planned as the *upcoming* midnight, so it is
  never dropped for "being in the past" — the inclusive-midnight requirement.

**Tests written** — `test/unit/notification_id_test.dart` (16),
`test/unit/notification_planner_test.dart` (27). They assert, among other
things: the same clock time on two days yields two different ids; a 7-day × 16
slot horizon yields 112 distinct ids; the 16 default slots all appear on the
first day; midnight is a valid slot; ids are stable across restarts, ordered
within a day, unaffected by DST; bands never overlap and every id is a safe
positive 32-bit int; 1 000 medicine ids produce no collision; and a 180-alarm
realistic set is collision-free.

**Remaining limitations.** The hashed bands are *probabilistically* unique, not
provably so — only the water/encouragement/love-note bands are structural. A
collision would require two medicine log ids whose 30-bit hashes agree (≈1 in
31 000 at 180 alarms). Diagnostics shows the pending count, so a collision would
surface as one fewer alarm than planned rather than as silence.

---

## R2 — Notification actions were lost when the app was not running

**Original issue.** Notification action handling depended on static callback
registration and on services initialised by the main isolate.

**Root cause.** Two compounding defects:

1. `BackgroundActionHandler._delegate` and `BackgroundQueueWriter._writer` were
   `static` fields populated during bootstrap. Android runs the notification
   action callback in a **separate isolate**; those fields are `null` there.
2. Even on the "queue" path, the write was only a JSONL append, and the drain
   that turned it into a database row ran from `main()` — which does not run
   again if the app was merely backgrounded, not killed.

So a tap on a locked screen could be recorded only as a line of text and never
reach SQLite, and the water total stayed wrong with no error anywhere.

**Files modified**

| File | Change |
|---|---|
| `lib/core/notifications/background_actions.dart` | **New.** `BackgroundActionEngine` (self-bootstrapping headless entry point), `ActionExecutor` (transactional, provider-free), `PendingActionQueue` (durable replay), `pruneActionLedger`. |
| `lib/core/notifications/action_controller.dart` | Reduced to a UI-side adapter. The duplicated write logic is gone. |
| `lib/core/notifications/pending_action_queue.dart` | Deleted; superseded by the queue in `background_actions.dart`. |
| `lib/core/database/schema.dart` | New `notification_actions` ledger table + `DbSchema.version` 1 → 2 + migration. |
| `lib/data/repositories/water_repository.dart` | New `insertLogInTxn` so the log, the dedupe marker and the history row commit atomically. |
| `lib/data/repositories/medicine_repository.dart` | New `applyResponseInTxn`; `recordResponse` keeps its behaviour for callers outside a transaction. |
| `lib/main.dart`, `lib/app.dart`, `lib/core/providers.dart` | New boot/resume wiring; replay on launch **and** on every resume. |
| `android/app/src/main/AndroidManifest.xml` | Boot/package-replacement added to `TimeChangeReceiver`; new `VoiceReminderReceiver`; `USE_EXACT_ALARM` removed. |

**Fix implemented.**

* The headless isolate **opens its own database** and applies the change
  itself. No statics, no providers, no UI, and the main isolate does not need to
  be alive.
* **Exactly once.** Every action carries a deterministic dedupe key
  (`kind|refId|slot|value|actionId|day`). The key is claimed with
  `INSERT OR IGNORE` inside the same transaction as the domain write; a
  re-delivered broadcast affects 0 rows and returns immediately.
* **Atomic.** Water millilitres, the dedupe marker and the audit row either all
  commit or none do. A crash between them leaves the action retryable.
* **Durable.** If anything throws, the event stays in the JSONL queue and is
  replayed on the next launch or resume. An action is never silently dropped.
* **No double-count fallback.** Notification-sourced water logs use a
  deterministic primary key, so even a delivery that somehow bypassed the
  ledger cannot add a second glass.
* **Correct day attribution.** The payload now carries `dayKey`, so answering a
  23:55 reminder at 00:05 is booked against the day the reminder belonged to.
  Payloads from an older build (no `dayKey`) still decode and fall back to today.
* A medicine is **only** ever set to `taken` on an explicit "I took it";
  every other path leaves it untouched.

**Tests written** — `test/unit/notification_action_test.dart` (13) for payload
round-trip, dedupe-key identity and robustness; `test/unit/notification_ledger_test.dart`
(10) which runs the **real SQLite engine** on the host and proves: first delivery
wins, second is a no-op; ten rapid taps log exactly one glass; different slots
each apply once; a failed transaction rolls back both the claim and the write so
the action can be retried; duplicate history rows are impossible; and a v1
database with real user records upgrades to v2 with every record intact.

**Remaining limitations.** Android gives no callback at all after the user
force-stops an app — no code can fix that, and Diagnostics says so in plain
language. A device in Doze may delay the headless isolate; the queue covers it,
but the water total will lag until the app is next opened.

---

## R3 — Spoken reminders were a setting that did nothing

**Original issue.** A TTS service existed, but `speak()` was only called from the
Voice settings preview and the diagnostics screen. No production code path
consumed the setting at reminder time.

**Root cause.** Two separate problems:

1. Nothing in the scheduling path ever checked `settings.effectiveVoice`. The
   payload did carry a `voiceLine`, but it was used as notification **text**
   only, never as audio.
2. Even if it had been wired, `flutter_tts` requires the Flutter engine. Once
   Android terminates the process there is no Dart to call, so a Dart-only
   implementation could never speak for a reminder that arrives while the phone
   is in a pocket.

**Files modified**

| File | Change |
|---|---|
| `lib/core/notifications/spoken_reminders.dart` | **New.** Deterministic line selection, profile gating, safe degradation. |
| `lib/core/notifications/voice_plan_service.dart` | **New.** Builds and pushes the native spoken plan; explains why speech is off. |
| `android/.../VoiceReminderScheduler.kt` | **New.** Native alarm scheduling for speech, with exact → inexact fallback. |
| `android/.../VoiceReminderReceiver.kt` | **New.** Creates its own `TextToSpeech` engine, speaks one line, re-arms tomorrow. |
| `android/.../TimeChangeReceiver.kt` | Re-arms native speech on boot / clock / timezone / app-update. |
| `android/.../MainActivity.kt` | New channel methods: `applyVoicePlan`, `cancelVoicePlan`, `isSpeechAvailable`, `speakTest`, `isSilentOrDnd`. |
| `lib/core/services/system_channel.dart` | Dart side of those methods. |
| `lib/core/notifications/reminder_scheduler.dart` | Pushes the plan after every rebuild; reports the outcome. |
| `lib/features/settings/diagnostics_screen.dart` | Test buttons now use the same native engine a real reminder uses, and explain muted/DND. |

**Fix implemented.**

* Speech is executed **natively**, in Kotlin, by an `AlarmManager` alarm. It
  therefore works with the app backgrounded, closed, and with the screen locked.
* The TTS engine is created per firing and released on `onDone` (with a 30 s
  hard timeout for vendor engines that never call back). No engine is held in a
  static field.
* Speech is routed to the **alarm** audio stream and respects ringer mode and Do
  Not Disturb: when the phone is muted or in DND the app suppresses speech
  instead of fighting the user's own settings.
* Lines rotate deterministically per occurrence, so the same reminder time says
  the same thing on the same day, and consecutive reminders differ.
* Four personas are preserved (soft/cheerful feminine, calm masculine, device
  default) plus the master off switch; every one has a distinct pitch or rate.
* `isSpeechAvailable()` is queried so the UI can say "this phone has no
  text-to-speech engine" instead of silently doing nothing.
* The in-app preview and a real reminder go through the **same** engine, so what
  she hears in settings is what she will hear at 15:00.

**Tests written** — `test/unit/spoken_reminder_test.dart` (15): rotation
stability, distinct consecutive lines, pool membership, empty-pool degradation,
medicine/water scripts differ, profile gating, the master toggle overriding the
persona, and copy-safety checks (no shaming words, length bound, non-empty).

**Remaining limitations.** Audio itself is not unit-testable: it is a platform
engine, and the tests assert the *decision*, not the sound. A device is required
to confirm that speech actually plays — this is on the manual checklist. Speech
is genuinely impossible after a force-stop, and the notification still appears in
that case.

---

## R4 — AI Cloud Function had authentication commented out and wildcard CORS

**Original issue.** `Access-Control-Allow-Origin: *` on a publicly reachable
endpoint, with the token-verification block commented out.

**Root cause.** The function was written as a demo and shipped as production. It
accepted unauthenticated requests, so anyone with the URL could spend the
project's model budget, and a `uid` in the request body could have been trusted
if one had been added.

**Files modified**

| File | Change |
|---|---|
| `firebase/functions/index.js` | Rewritten. |
| `firebase/firestore.rules` | Rewritten and hardened. |
| `firebase/functions/.env.example` | Added `ALLOWED_ORIGINS`, `ENFORCE_APP_CHECK`. |

**Fix implemented.**

1. **Authentication** — `Authorization: Bearer <Firebase ID token>` is required
   and verified with `admin.auth().verifyIdToken(token, true)` (revocation
   checked). The identity is taken from the verified token; **no uid is ever read
   from the request body**.
2. **App Check** — enforced when `ENFORCE_APP_CHECK=true`.
3. **CORS** — allow-list only (`ALLOWED_ORIGINS`), no wildcard. A browser origin
   not on the list gets 403. Requests without an `Origin` header (the Android
   app, server calls) are allowed because CORS is a browser mechanism and they
   are authenticated separately.
4. **Validation** — message ≤1 200 chars, ≤10 history items, ≤1 200 chars each,
   role must be `user`/`assistant`, non-array history rejected.
5. **Rate limiting** — per-uid sliding window (6/min, 120/day) enforced in a
   Firestore transaction, plus a global circuit breaker (600/min) and
   `maxInstances: 20`. `429` responses include `Retry-After`.
6. **Safe errors** — provider status and internal messages are logged, never
   returned. The client gets `companion_unavailable` / `temporary_failure`.
7. **Secrets** — `AI_PROVIDER_KEY` via `functions:secrets:set`; the example env
   file holds placeholders only.
8. **Safety** — crisis phrases intercepted before any model call, and the reply
   is re-checked afterwards.
9. **Timeout** — 20 s `AbortController` so a hung provider cannot hold an
   instance for the full 30 s.
10. **Firestore rules** — per-user scoping, an explicit entity allow-list (no
    arbitrary subcollections), required-field validation on create **and**
    update, a `user_id`-ownership check, a document-size bound, `recordId` must
    equal `data.id`, the rate-limit collection is client-inaccessible, and a
    catch-all denies everything else.

**Tests performed.** `node --check firebase/functions/index.js` → **passed**
(syntax only). The Firestore **schema** was additionally executed against a real
SQLite engine (see the database section) — but that is the app's local schema,
not the security rules. The rules were reviewed line by line but **not** executed: that
requires the Firebase emulator suite (`firebase emulators:start`), which needs a
JDK. → **Not executed here.**

**Remaining limitations.** Rate limiting fails **open** on a Firestore error, by
design (a database hiccup should not lock a user out); the per-day cap and the
global breaker still bound abuse. App Check must stay off until the Android app
is registered with Play Integrity, otherwise every request is rejected.

---

## R5 — Gradle wrapper files were missing

**Original issue.** `gradlew`, `gradlew.bat` and `gradle/wrapper/gradle-wrapper.jar`
were absent, so the project could not be built from a clean checkout.

**Root cause.** Binary files were omitted when the project archive was produced.

**Files added**

| File | Source | Bytes | Verified |
|---|---|---|---|
| `android/gradle/wrapper/gradle-wrapper.jar` | `gradle/gradle` repository, tag `v8.3.0`, path `gradle/wrapper/gradle-wrapper.jar` | 63 721 | Fetched through the GitHub contents API, `sha256` recorded, ZIP structure read back (`META-INF/MANIFEST.MF` → `Implementation-Title: Gradle Wrapper`) |
| `android/gradlew` | same tag, `gradlew` | 8 661 | `#!/bin/sh` shebang present; marked executable |
| `android/gradlew.bat` | same tag, `gradlew.bat` | 2 798 | present |

This is the **official** wrapper JAR from the Gradle project at the matching
release tag — not a fabricated or hand-assembled file.

**Toolchain consistency checked**

| Component | Version | Constraint |
|---|---|---|
| Android Gradle Plugin | 8.1.0 (`settings.gradle`) | requires Gradle ≥ 8.0, JDK 17 |
| Gradle | 8.3 (`gradle-wrapper.properties`) | satisfies AGP 8.1 |
| Kotlin plugin | 1.9.10 | the version Flutter 3.16–3.24 templates use |
| `compileSdk` / `targetSdk` | 34 | AGP 8.1 supports 34 |
| `minSdk` | 23 | unchanged |
| Java/Kotlin target | 17 | required by AGP 8.x; desugaring enabled for `flutter_local_notifications` |

`gradle-wrapper.properties` was switched from `-all` to `-bin` (≈80 MB smaller
download; the `-all` distribution only adds sources and docs) and gained
`networkTimeout` / `validateDistributionUrl`. `AGP`, Gradle and JDK were
**not** upgraded beyond the known-good pairing.

**Verified.** File presence, sizes, JAR internals and script shebang were checked.
`./gradlew --version` was **not** run — there is no JDK in the repair
environment, so wrapper *execution* is unverified.

---

## R6 — Exact alarm permissions were over-declared

**Original issue.** Both `USE_EXACT_ALARM` and `SCHEDULE_EXACT_ALARM` were
declared.

**Root cause.** Both were added defensively. They have different semantics:
`USE_EXACT_ALARM` is granted at install, cannot be revoked, and Google Play
restricts it to alarm-clock and calendar apps. Declaring it for a wellness app is
a policy risk for a permission the app does not need.

**Fix implemented.**

* **`USE_EXACT_ALARM` removed.** `SCHEDULE_EXACT_ALARM` is the correct one: it is
  user-controllable, and on Android 13+ it is granted by default and can be
  revoked at any time.
* The app treats exactness as an **optimisation, not a requirement**:
  `canScheduleExactAlarms()` is checked, and the scheduler falls back to
  `inexactAllowWhileIdle` (typically within ~10 minutes). If a schedule call
  throws `exact_alarms_not_permitted` the alarm is retried inexactly rather than
  lost — a new behaviour in `NotificationService.schedulePlanned`.
* The permission-diagnostics screen already explained *why* the permission is
  wanted and how to grant it; it now also reports the **alarm budget** and
  whether the water channel has been muted at the OS level, which are the two
  remaining invisible causes of "my reminder did not arrive".

**Tests written.** `notification_planner_test.dart` asserts the budget helpers;
`notification_id_test.dart` asserts every id is a safe 32-bit int (the reason
`PendingIntent` request codes must stay positive).

**Remaining limitations.** The permission state cannot be simulated in a unit
test. Verifying that a revoked permission degrades cleanly requires a device.

---

## R7 — Full notification-engine audit (requested in addition)

Findings beyond the seven reported issues, all fixed:

| # | Finding | Severity | Fix |
|---|---|---|---|
| 7.1 | **`TimeChangeReceiver` was not listening for `BOOT_COMPLETED` or `MY_PACKAGE_REPLACED`.** After a reboot, only the plugin's own boot receiver ran, so nothing re-armed the *native* spoken reminders, and any reschedule the Dart side needed was not flagged until a clock change happened. | **High** | Receiver now handles boot and package-replacement too, and re-arms the native speech plan immediately without waiting for Dart. |
| 7.2 | Investigated whether `ScheduledNotificationBootReceiver` / `ActionBroadcastReceiver` need `exported="true"`. There is an open upstream issue asserting Android 12+ does. **Changed it, then changed it back**: the plugin's own README documents `exported="false"`, and the Android platform docs state the system can deliver protected actions to non-exported receivers. Shipping `true` on an unverified report would let any installed app poke the receiver. **Kept `false`; flagged as a manual test item in `docs/TESTING.md` §5.** | — | No change; comment added recording the conflict and how to settle it on a device. |
| 7.3 | Water and medicine shared one channel definition style; water used no audio usage attribute, so it followed the media stream and was silenced by a muted media volume. | Medium | Water channel uses `AudioAttributesUsage.alarm` (alarm stream); medicine uses `notification` (a message tone, deliberately not a siren). |
| 7.4 | Motivation and love-note alarms were scheduled with an id shared across the horizon (`id + dayOffset` on top of an id that already varied by day), so the two could drift into the same numbers. | High | Now structural per-day ids from the planner. |
| 7.5 | Two love notes at the same clock time collided. | Medium | The id now carries a bounded offset derived from the note id; a test pins it. |
| 7.6 | `scheduleDailySummary` computed "next instance" and then added a day only if it was in the past — which mis-handled the boundary. | Low | Single `nextOccurrence` helper, tested for three cases including midnight. |
| 7.7 | The tz zone-name fallback list contained a duplicate (`Asia/Karachi` twice) and no southern-hemisphere entries, so some offsets silently fell back to `UTC`, shifting every reminder. | Medium | List rebuilt and de-duplicated; offset is matched against the live `TZDateTime` offset rather than assumed. |
| 7.8 | iOS permission was requested at `initialize()` (nobody was asked in context). | Low | Deferred to an explicit request. |
| 7.9 | `NotificationService` swallowed init failure with no state, so the UI could not say notifications were unavailable. | Low | `lastInitFailed` / `lastInitError` exposed. |
| 7.10 | The Diagnostics screen counted pending water/medicine alarms with hard-coded numeric bands. | Low | Uses `isWater()` / `isMedicine()` helpers, so the screen cannot disagree with the scheduler. |
| 7.11 | Scheduling never checked a budget against Android's pending-alarm ceiling. | High | `maxPendingAlarms = 400`, horizon 5 days, and the report surfaces `refused`/`skipped`. |

---

## R8 — Database and migration audit

* `DbSchema.version` **1 → 2**. The single migration (v1 → v2) is **additive
  only**: it creates `notification_actions` and its index with
  `IF NOT EXISTS`. No `ALTER`, no `DROP`, no `DELETE` — so no existing record can
  be lost by upgrading, and an interrupted migration is safe to re-run.
* `notification_actions` is deliberately excluded from the synced table set
  (no `dirty`, no `deleted_at`): a local delivery ledger must not suppress
  another device's identical action key.
* Ledger rows are pruned after 14 days (`pruneActionLedger`, called at boot).
* The rest of the schema is unchanged, so water history, medicine history,
  journal, mood and gratitude data are untouched by the upgrade.
* Foreign keys are still enforced (`PRAGMA foreign_keys = ON` in `onConfigure`),
  and `onDowngrade` remains `onDatabaseDowngradeDelete` — the only path that can
  delete data, and it requires installing an *older* build over a newer one.

**Tests written.** `notification_ledger_test.dart` builds a v1 database with a
real user row, a water log and a journal entry, upgrades it to v2 through
`DbSchema.migrations`, and asserts all three records survive, the journal body is
intact, the new table exists and the migration is idempotent.

---

## R9 — Offline and online audit

Verified by inspection of the call graph (no runtime execution available):

* **Offline-mandatory features do not touch the network.** Water, medicine,
  dashboard, journal, mood, breathing, gratitude, motivation library, local love
  notes, reports, reminder editing and settings all read from SQLite through
  repositories. `Firebase` appears only in `features/sync/`.
* **Firebase failure cannot block startup.** `main()` wraps every network step in
  its own `try/catch`, `_tryFirebase()` returns `null` on any failure, and the
  sync service runs with a `LocalOnlyBackend` when absent.
* **A network outage cannot erase local data.** Every write is local first; the
  sync queue retries. `_pullAndMerge` is the only path that clears `dirty`.
* **Account separation** is enforced server-side by the Firestore rules, not by
  the client.

---

## R10 — Code quality

* `main()` rewritten so a failure in any bootstrap step cannot prevent the app
  from opening — except the database itself, which genuinely must open.
* Every post-`await` UI update in the changed files is `mounted`-guarded.
* Killed a duplicate id-band definition (`AppConstants.id*Base`) that disagreed
  with the real one.
* Removed the parallel write implementation in `action_controller.dart`; there is
  now one executor used by the UI isolate, the headless isolate and the tests.
* Dart files: 0 unresolved relative imports; 0 imbalanced braces/parens/brackets
  across 110 files under a comment- and string-aware lexer.
* JavaScript: `firebase/functions/index.js` passes `node --check`.
* Kotlin: reviewed by hand. No Kotlin compiler was available, so Kotlin syntax is
  **not** machine-verified.

---

## Test inventory after this repair

| Suite | Cases |
|---|---|
`test/unit/water_schedule_engine_test.dart` | 28
`test/unit/notification_planner_test.dart` | **27 (new)**
`test/unit/models_test.dart` | 24
`test/unit/date_and_settings_test.dart` | 19
`test/unit/notification_id_test.dart` | **16 (new)**
`test/unit/spoken_reminder_test.dart` | **15 (new)**
`test/unit/sync_logic_test.dart` | 14
`test/unit/notification_action_test.dart` | **13 (new)**
`test/unit/notification_ledger_test.dart` | **10 (new)**
`test/unit/motivation_content_test.dart` | 8
`test/unit/routing_test.dart` | 6
`test/widget/design_system_test.dart` | 21
`test/widget/dashboard_widgets_test.dart` | 15
`integration_test/app_test.dart` | 5
**Total** | **222**

New this pass: **82 cases** (5 new files, plus 1 added to `sync_logic_test.dart`).

---

## One thing I got wrong and corrected

While auditing the manifest I "fixed" `ScheduledNotificationBootReceiver` and
`ActionBroadcastReceiver` to `exported="true"`, on the strength of an upstream
GitHub issue claiming Android 12+ requires it. Checking the plugin's actual
README and the Android platform documentation showed the opposite: the documented
value is `false`, and the system can still deliver protected broadcast actions to
a non-exported receiver. Setting `true` would have exposed both receivers to any
installed app for no benefit.

It is reverted. The manifest now carries a comment recording the conflict and
`docs/TESTING.md` §5 lists "reboot the phone and confirm reminders return" as a
manual check. This is the one place where the honest answer is "the sources
disagree, and only a device settles it".

## What is still not verified

1. **Nothing has been compiled.** No `analyze`, no `test`, no APK.
2. **Kotlin has not been compiled** — the new `VoiceReminderScheduler`,
   `VoiceReminderReceiver` and the `MainActivity` additions are hand-reviewed
   only. A Kotlin type error is the most likely first-run failure in this pass.
3. **Audio has not been heard.** Speech is asserted by decision, not by sound.
4. **Firestore rules have not been executed** (needs the emulator + JDK).
5. **The Gradle wrapper has not been executed** (needs a JDK).
6. **No device or emulator run.** See `docs/TESTING.md` §5 for the manual matrix.
