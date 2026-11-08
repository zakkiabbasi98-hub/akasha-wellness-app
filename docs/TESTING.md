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
| `test/unit/sync_logic_test.dart` | 14 | The real `SyncConflictRules` implementation (not a copy): clean row accepts cloud, newer local change never overwritten, newer cloud wins, tie keeps the local row for re-upload, pushed rows are not requeued, tombstones; `LocalOnlyBackend` never reports itself as available; AI `detectSafety` distinguishes sadness from crisis; the offline fallback never claims to be a therapist; crisis messages return real-world support and set `isCrisis` |

Total: **93 unit tests.**

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

**Grand total: 134 test cases** (93 unit + 36 widget + 5 integration).

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
| Notifications fire on a real device, in every state | **NOT verified** — implemented and wired end-to-end; requires the matrix in §5 |
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
