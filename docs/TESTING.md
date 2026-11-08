# AKASHA — Testing

> **Read this first, honestly:** the suites below are written, complete and
> consistent with the application code, but **they were not executed while this
> project was authored** — the authoring environment had no Flutter or Dart SDK
> installed. Nothing in this repository claims a green test run. What follows is
> exactly what to run, what it protects, and the manual device matrix that covers
> the parts no automated test can reach (notifications, OEM battery managers,
> lock-screen behaviour).

---

## 1. Commands

```bash
flutter pub get            # resolve dependencies first
flutter analyze            # static analysis (treat warnings as real)
flutter test               # unit + widget suites (no device needed)
flutter test test/unit     # unit only — runs in well under a second
flutter test test/widget   # widgets only

# device-level flow tests (needs a connected device/emulator)
flutter test integration_test/app_test.dart -d <device-id>
```

Useful extras:

```bash
flutter test --coverage && genhtml coverage/lcov.info -o coverage/html
flutter test --reporter expanded      # named tests, easier to read failures
flutter run --profile                 # performance profiling on a device
```

---

## 2. Unit suites

| File | Tests | What it pins down |
|---|---|---|
| `test/unit/water_schedule_engine_test.dart` | 27 | The 16-slot default **verbatim** (09:00 … 23:00 + **12:00 AM**), interval maths, inclusive end, non-grid end exclusion, midnight wrap, `start == end` = full day without a duplicate slot, duplicate prevention, parsing (`12:00 AM` → 0, never 1440), formatting round-trips, `windowSpanMinutes`, `nextSlot` rollover, `remainingToday` including the midnight slot, `maxSlots` cap, invalid-interval rejection |
| `test/unit/date_and_settings_test.dart` | 19 | Day keys, Monday-based weeks, month bounds (incl. leap February), millis round-trip, `minutesToLabel` wrapping, time parsing, quiet hours both same-day and overnight, "identical start/end means no quiet window", `lastNDays`, greeting buckets, constant values (540 / 0 / 60 / 16 / glass sizes), validator bounds |
| `test/unit/models_test.dart` | 23 | Row round-trips for settings/logs/medicines/journal/mood, `glassesTarget` rounding (incl. zero target), dirty-on-write, theme + voice + source + status key round-trips, weekday/date-range due rules, **"an unanswered dose is never implicitly taken"**, `isAnswered` for terminal statuses only, `scheduledAt` composition, gratitude `items` skipping empty slots, `MoodType.fromKey('nonsense')` → `null` |
| `test/unit/motivation_content_test.dart` | 8 | ≥100 messages with no empty category, every category present, no duplicates, **no shaming language** (banned-phrase scan), ≤160 chars, water/medicine notification copy well formed, crisis text points to a real person and emergency help |
| `test/unit/notification_id_test.dart` | 16 | One id per occurrence: same clock time on two days must differ; 112 alarms over a 7-day horizon stay 112 distinct; midnight valid; DST-proof; bands never overlap; every id a safe positive 32-bit int |
| `test/unit/notification_planner_test.dart` | 27 | The scheduling contract — multi-day materialisation, midnight inclusive, past occurrences dropped, quiet hours (water vs medicine asymmetry), weekday courses, ended courses, alarm budget |
| `test/unit/notification_action_test.dart` | 13 | Payload round-trip incl. legacy payloads, dedupe-key identity across repeated delivery, robust decoding of garbage |
| `test/unit/notification_ledger_test.dart` | 10 | **Real SQLite via `sqflite_common_ffi`**: schema executes, ten taps log one glass, failed transaction rolls back, v1→v2 migration keeps every record |
| `test/unit/spoken_reminder_test.dart` | 15 | Voice setting reaches the scheduler, deterministic rotation, profile gating, master toggle, copy safety |
| `test/unit/routing_test.dart` | 6 | Every `Routes.*` constant exists in the real route tree; no duplicate or malformed paths; settings stay under Profile and reports/calendar/history under Home (this suite caught **seven dead navigation tiles**) |
| `test/unit/sync_logic_test.dart` | 14 | The real `SyncConflictRules` implementation (not a copy): clean row accepts cloud, newer local change never overwritten, newer cloud wins, tie keeps the local row for re-upload, pushed rows are not requeued, tombstones; `LocalOnlyBackend` never reports itself as available; AI `detectSafety` distinguishes sadness from crisis; the offline fallback never claims to be a therapist; crisis messages return real-world support and set `isCrisis` |

Total: **99 unit tests.**

Because `MainActivity` also exposes a native channel, the tests that touch
Platform code (`SystemChannel`, notifications, TTS, biometrics) are deliberately
kept out of the unit suites — they are covered by the device matrix in §5.

---

## 3. Widget suites

| File | Tests | What it pins down |
|---|---|---|
| `test/widget/design_system_test.dart` | 21 | Material 3 is on; the palette is AKASHA's (primary `AppColors.purple`, and **never** the Material default `#6750A4`); dark theme exists; no text below 10 px; card radii ≥20 and ≤28; shadows are never pure black; `GradientScaffold` renders/hides blobs; `SoftCard` tap + accent; `ProgressRing` clamps >1.0 and survives negative progress; `DropletMeter` handles `0/0`, over-full and `maxVisible`; `AkashaBottomNav` renders 5 labelled destinations, reports the tapped index, and exposes `isSelected` semantics |
| `test/widget/dashboard_widgets_test.dart` | 15 | `WaterHeroCard` shows a real percentage (750/2000 → 38%), the remaining-ml copy, the goal-reached state, the empty state, and fires `onQuickAdd(250, 'medium')`; `MedicineTodayCard` invites adding when empty, shows "1 of 2 taken", and reports `DoseStatus.taken` from the tick; `MoodCard` empty vs populated; `ShortcutGrid` hides the companion unless AI is enabled; `SelfCareCard` and `MotivationCard` copy + fallback |

Total: **36 widget tests.** Widget tests wrap the widget in the real
`AppTheme.light()` inside a phone-sized surface, so a theme regression fails a
widget test rather than shipping.

**Grand total: 222 test cases** (181 unit + 36 widget + 5 integration).

---

## 4. Integration flow (`integration_test/app_test.dart`)

Runs the **real** app (real SQLite file, real repositories) on a device:

1. **Boot** — `main()` runs, a `MaterialApp` renders, no `ErrorWidget` appears.
2. **First-run seed** — a profile exists; exactly 16 water reminders, unique
   minutes, containing 00:00, 09:00 and 23:00; ≥100 messages.
3. **Persistence** — logs a 250 ml glass, asserts the summary grows, closes and
   reopens the SQLite file, and asserts the glass is still there.
4. **Medicine honesty** — creates a medicine, asserts today's dose exists as
   `scheduled` (never `taken` without an action), records `taken` explicitly and
   re-reads it, then soft-deletes the test record so re-runs are clean.
5. **Navigation** — taps every bottom-nav tab and asserts no error widget. (On a
   fresh install this step self-skips if the onboarding wizard is showing.)

---

## 5. Manual device matrix (the part only a phone can prove)

No automated test can prove that a reminder actually appears behind a lock screen
on a Xiaomi ROM. Do this once on the target device, ideally twice: once with
battery optimisation **on** (to see the failure mode) and once **off**.

### 5.1 Environment

| # | Check | Expected |
|---|---|---|
| E1 | Fresh install, no network, no Firebase config | app opens, onboarding completes |
| E2 | Aeroplane mode for a full day | every feature except sync/AI works |
| E3 | Android 8, 10, 12, 13, 14 (as available) | no layout breakage, no crash |
| E4 | Font scale 1.3 and display size large | text does not clip |
| E5 | Dark mode toggled while running | all screens re-theme correctly |

### 5.2 Notifications (the critical set)

| # | Steps | Expected |
|---|---|---|
| N1 | Settings → Diagnostics → *Test reminder* | notification appears within ~1 s |
| N2 | Set a water slot 2 min ahead, **app foreground** | reminder fires with 3 actions |
| N3 | …**app backgrounded** | same |
| N4 | …**app swiped away (terminated)** | same |
| N5 | …**screen locked** with full-screen intent granted | reminder visible on lock screen |
| N6 | …with full-screen intent **revoked** | heads-up notification, no crash |
| N7 | Press **I drank water** from the lock screen | glass appears in Home after unlock |
| N8 | Press **Skip** | history records `skipped`, **no** water logged |
| N9 | Press **Later** | a snoozed reminder fires `snooze_minutes` later |
| N10 | **Reboot** the phone, wait for the next slot | reminders still fire |
| N11 | Change timezone (Settings → Date & time) then open the app | diagnostics shows a rebuilt schedule; times stay local-correct |
| N12 | Enable quiet hours covering a slot | that slot is silent; medicine (if not muted) still fires |
| N13 | Turn on Do Not Disturb | reminders are silent/blocked — the **expected** Android behaviour, not a bug |
| N14 | Deny notification permission at first prompt | diagnostics shows it as the blocker + a Fix button; app remains usable |
| N15 | Force-stop the app from system settings | reminders stop (documented Android rule); they return on next launch |

### 5.3 Data integrity

| # | Steps | Expected |
|---|---|---|
| D1 | Log water, kill the app, reopen | total unchanged |
| D2 | Edit a reminder time | no duplicate slot, no double notification |
| D3 | Restore defaults | exactly 16 slots, never duplicated |
| D4 | Medicine taken → history shows `taken` with a timestamp | correct |
| D5 | Leave a dose unanswered overnight | becomes `missed`, never `taken` |
| D6 | Export data | a JSON file opens and contains real rows |
| D7 | Wipe data | onboarding returns; no stale reminders fire |
| D8 | Cross a midnight boundary with the app closed | yesterday's doses reconcile correctly |

### 5.4 Optional cloud (only if configured)

| # | Steps | Expected |
|---|---|---|
| C1 | Enable sync, sign in, sync now | `pushedRecords` > 0, rows appear in Firestore |
| C2 | Log water on device A, sync both | appears on B |
| C3 | Delete on B, sync both | tombstone wins; still deleted on A |
| C4 | Sign out | local data intact, sync disabled |
| C5 | Delete cloud data | Firestore subtree empty; local data untouched |
| C6 | Turn aeroplane mode on mid-sync | queue retains entries; no data loss |

---

## 6. What is verified, and what is not

| Claim | Status |
|---|---|
| Every file imports only files that exist | **verified** — a script resolved all relative and `package:akasha/` imports across `lib/`, `test/`, `integration_test/`: 0 broken |
| Every provider referenced by a screen is defined | **verified** — scripted audit over `ref.watch`/`ref.read`: 0 undefined |
| Every shared widget used by a screen is imported | **verified** — scripted audit; the 7 missing imports it found were added |
| Shared design tokens (`AppColors`, `AppRadius`, `AppShadows`) referenced exist | **verified** — 0 undefined symbols |
| Dart code compiles | **NOT verified** — no Dart SDK in the authoring environment |
| `flutter analyze` is clean | **NOT verified** — never run |
| Unit/widget/integration tests pass | **NOT verified** — never run |
| An APK builds | **NOT verified** — no Android SDK/Gradle |
| Notifications fire on a real device, in every state | **NOT verified** — implemented and wired end-to-end; requires the matrix in §9 |
| Notification **ids are unique per occurrence** | **Verified by simulation** — the old and new schemes were re-implemented and run: old = 96 of 112 alarms lost (86 %), new = 0 lost. Asserted by `test/unit/notification_id_test.dart` |
| The local schema actually executes | **Verified against real SQLite** (`node:sqlite`): all 20 tables + 18 indexes create cleanly, and the v1→v2 migration preserves seeded user rows |
| The v1→v2 migration is idempotent | **Verified against real SQLite**: run twice, no error, records intact |
| Background action is exactly-once at the SQL level | **Verified against real SQLite**: `INSERT OR IGNORE` claims once; ten inserts produce one row |
| Spoken reminders play with the app closed | **NOT verified** — the Kotlin engine is written and reviewed; needs a device (§9 S1) |
| The Gradle wrapper executes | **NOT verified** — the official JAR, scripts and version pairing are in place; no JDK here to run it |
| Firestore rules behave as documented | **NOT verified** — written and reviewed; deploy to a test project and run §5.4 |

Anything not marked *verified* above must be established on your machine before
being relied on. The honest summary: **the code is complete, the reasoning is
sound, and the proof is yours to run.**

---

## 7. Adding tests

* Put pure logic in `test/unit` and **do not** import Flutter there — it keeps the
  suite fast and prevents accidental platform dependencies.
* Widget tests must not hit the network, the filesystem, notifications or Firebase.
  Override providers instead.
* If a test encodes a product requirement (16 slots, midnight, no shaming copy,
  "never implicitly taken"), treat the requirement as authoritative: change the
  code, not the test.
* Pin user-visible copy only where the wording *is* the requirement (safety text,
  crisis guidance, empty states). Otherwise assert structure, not sentences.

---

## 8. Capturing screenshots

`docs/screenshots/` is deliberately empty in this repository — the images are
produced on a real device, because the design language (soft gradients,
hairline borders, hand-painted droplet) does not survive an emulated renderer
faithfully enough to be worth publishing.

To generate them:

1. `flutter run --release` on a physical Android device (or an emulator at
   1080 × 2340, 400 dpi).
2. Complete onboarding so the screens are not all empty states.
3. Capture in this order, so the repository listing matches the README narrative:

   | File | Screen |
   |---|---|
   | `01-onboarding.png` | Onboarding, page 1 |
   | `02-home.png` | Home dashboard, water goal part-met |
   | `03-water.png` | Water tab |
   | `04-medicine.png` | Medicine tab with one active medicine |
   | `05-mind.png` | Mind tab |
   | `06-journal.png` | Journal editor, mid-entry |
   | `07-breathing.png` | Breathing session, animation mid-cycle |
   | `08-reports.png` | Weekly report |
   | `09-calendar.png` | Calendar with a month of dots |
   | `10-settings.png` | Settings |

4. `adb exec-out screencap -p > docs/screenshots/02-home.png` (or
   `flutter screenshot`).
5. Use a device with a **light** system theme: the app follows the system
   brightness, and a dark capture will not match the palette quoted in
   `ARCHITECTURE.md`.

Nothing in the build, the tests or the app depends on these files.

---

## 9. Manual device matrix

Nothing in this table has been executed. It exists because the behaviours below
cannot be checked by `flutter test`: they depend on Android's alarm delivery, Doze
mode, OEM background restrictions and the notification shade. **Do not report
these as verified until you have ticked them on real hardware.**

Record the device and OS for each run — behaviour differs sharply between stock
Android and Xiaomi/Oppo/Vivo/Samsung/Huawei builds.

| # | Scenario | Steps | Expected |
|---|---|---|---|
| 1 | Fresh install | Install, open | Onboarding appears; no crash; no notification permission prompt yet |
| 2 | Initial launch | Complete onboarding | Home dashboard populates; Diagnostics shows a non-zero reminder count |
| 3 | Notifications granted | Allow when asked | Reminders appear at their slot time |
| 4 | Notifications denied | Deny | App works; Diagnostics says reminders cannot appear and offers a settings link |
| 5 | Exact alarms granted | Diagnostics → Grant | "Reminders land at the exact minute" |
| 6 | Exact alarms denied | Diagnostics, deny/revoke | Reminders still arrive, a few minutes late; Diagnostics explains; **no reminder is lost** |
| 7 | Phone locked | Lock, wait for a slot | Notification appears on the lock screen; action buttons work |
| 8 | App backgrounded | Home, wait for a slot | Notification + speech; tapping "I drank water" adds exactly one glass |
| 9 | App terminated | Swipe from recents, wait | Notification appears; **tapping an action updates the water total** — open the app and confirm the count changed. This is the core Issue-2 test |
| 10 | Phone rebooted | Reboot, wait | Reminders reappear without opening the app. **This is the highest-risk unverified item** — see `REPAIR_CHANGELOG.md` R7.2 |
| 11 | Internet disconnected | Airplane mode, use every feature | Everything works; no error dialogs; no data loss |
| 12 | Internet restored | After offline edits | Sync uploads; nothing is duplicated |
| 13 | Silent mode | Enable, wait for a slot | Notification appears silently; **no speech** (by design) |
| 14 | Do Not Disturb | Enable, wait | Reminder suppressed or silent per DND rules; never overridden |
| 15 | Battery saver | Enable, wait a full day | Reminders still fire; if they slip, Diagnostics says why |
| 16 | App updated | Install a new build over the old one | Pending alarms survive (`MY_PACKAGE_REPLACED`); spoken reminders re-arm |
| 17 | Timezone changed | Change zone in settings | Future reminders shift to the correct local time; no duplicates |
| 18 | Device time changed | Move the clock forward/back | Schedule is rebuilt once; **no storm of duplicate alarms** |

### Specifically for spoken reminders (Issue 3)

| # | Scenario | Expected |
|---|---|---|
| S1 | Voice on, app closed, screen locked, wait for a slot | The line is spoken aloud (not just a notification tone) |
| S2 | Voice off | Notification only, silence |
| S3 | Phone with no TTS engine | Voice settings says so; notifications still work |
| S4 | Voice settings → "Hear it" | Speaks the same line a real reminder would |
| S5 | Change persona | Next spoken reminder uses the new pitch/rate |
| S6 | Reboot, wait for a slot | Speech still works (native plan re-armed) |

### How to check background actions actually persisted

The only trustworthy check is the data, not the toast:

1. Note today's water total on the Home card.
2. Lock the phone, wait for a reminder, tap **I drank water**.
3. Open the app. The total must have risen by exactly one glass.
4. Tap the same action twice quickly (where the shade allows) — the total must
   still rise once.
5. `adb logcat -s flutter` and look for `AKASHA: failed to replay queued action`.
   No such line means the headless write succeeded directly; the line appearing
   followed by a correct total means the queue recovery worked.
