# AKASHA — Architecture

> A wellness app that must never lose a glass of water, never show a number it
> did not measure, and never depend on a network.

---

## 1. Principles

| # | Principle | Consequence in the code |
|---|-----------|--------------------------|
| 1 | **Local is truth.** | Every write commits to SQLite before any UI state changes. Network is an optional mirror. |
| 2 | **The phone is allowed to be offline forever.** | No feature is gated on connectivity. Cloud code lives behind interfaces with a `LocalOnly` implementation. |
| 3 | **One owner, one user row.** | Multi-user is not a feature; the schema is user-scoped so sync is possible, but the app always resolves a single local user. |
| 4 | **Pure logic is isolated and testable.** | Schedule maths, date maths, conflict resolution, crisis detection and copy rules have zero Flutter imports. |
| 5 | **Notification ids are deterministic.** | Re-scheduling replaces alarms instead of stacking duplicates. |
| 6 | **Nothing shames the user.** | Enforced in copy, in the states model (no red "failed" for a skipped dose), and asserted in tests. |
| 7 | **Honest UI.** | If a permission is missing, the screen says exactly which one and what it disables. |

---

## 2. Layers

```
┌──────────────────────────────────────────────────────────────┐
│  Presentation      lib/features/**            (37 screens)   │
│                    lib/shared/widgets/**      (design system) │
└───────────────▲──────────────────────────────────────────────┘
                │ watch / read (never direct repository access)
┌───────────────┴──────────────────────────────────────────────┐
│  Wiring            lib/core/providers.dart                    │
│                    the whole Riverpod graph in one file       │
└───────────────▲──────────────────────────────────────────────┘
                │
┌───────────────┴──────────────────────────────────────────────┐
│  Domain/services   core/services/     (schedule engine, voice…)│
│                    core/notifications/(scheduler, actions)     │
│                    data/repositories/ (water, medicine, mind…) │
└───────────────▲──────────────────────────────────────────────┘
                │
┌───────────────┴──────────────────────────────────────────────┐
│  Data              core/database/app_database.dart  (SQL only) │
│                    + schema.dart (19 tables)                   │
│                    data/models/ (typed rows, fromMap/toMap)    │
└──────────────────────────────────────────────────────────────┘
```

**Rules that keep it from rotting**

* `features/` may import `core/providers.dart`, `core/theme`, `core/routing`,
  `shared/widgets`, and `data/models`. It may **not** import `core/database`.
* `data/repositories` may not import anything from `features/`.
* SQL exists **only** in `AppDatabase` and the repository query builders built on
  it. A `rawQuery` in a widget is a bug.
* A service that needs the network takes a backend interface, not an
  implementation.

---

## 3. Riverpod graph (`lib/core/providers.dart`)

One file, deliberately. With 37 screens, provider sprawl is the main source of
"why is this screen empty?" bugs; a single wiring point makes the dependency
graph reviewable in one screenful.

```
databaseProvider ─┬─ profileRepository      ─┬─ profileProvider
notificationService│                        ├─ settingsProvider (FutureProvider)
voiceService      ├─ waterRepository        └─ settingsControllerProvider
lockService       ├─ medicineRepository          (StateNotifier<UserSettings>)
systemChannel     ├─ mindRepository
                  ├─ motivationRepository
                  ├─ loveNoteRepository ─────── loveNotesProvider
                  ├─ notificationHistoryProvider
                  ├─ reportsRepository ──────── todayReportProvider
                  ├─ seedServiceProvider ────── (first-run seeding, messageCount)
                  └─ reminderSchedulerProvider ─ schedulingStatusProvider
                                            └─ syncServiceProvider
```

### State shapes

* **`FutureProvider` for reads.** Records are small; re-reading on invalidation is
  cheap and removes a whole class of cache-coherence bugs.
* **`StateNotifier<AsyncValue<UserSettings>>` for settings.** Settings are the only
  thing written often enough (toggles) to need optimistic local state.
* **`dataRevisionProvider`** is a monotonically increasing `int`. Any write bumps
  it; derived providers (dashboard, reports, stats) `watch` it, so a glass of
  water logged from *any* screen refreshes *every* screen. This is why the app
  never shows a stale total — the alternative (manual invalidation calls sprinkled
  across 37 files) always misses one.

### Composition root

`main.dart` does, in order:

1. `WidgetsFlutterBinding.ensureInitialized()`
2. open the database (`AppDatabase.instance`)
3. build a `ProviderContainer` for boot-time work
4. initialise notifications (channels, action handlers, launch-details)
5. drain any queued notification action (`PendingActionQueue`)
6. seed content on first run
7. `runApp(UncontrolledProviderScope(container: …))`

Boot work happens **before** `runApp` only where the first frame would otherwise
show wrong data (e.g. the onboarding decision). Everything else is a provider.

---

## 4. Feature internals

### 4.1 Hydration

```
WaterScheduleEngine.generate(start, end, interval)  → generic slot list
        ↓
WaterRepository.restoreDefaults(userId)             → rows in water_reminders
        ↓
ReminderScheduler._scheduleWater(...)                → zonedSchedule per slot
        ↓ (fires)
NotificationService (channel: akasha_water)          → action buttons
        ↓ (tap)
PendingActionQueue → NotificationActionController      → WaterRepository.logGlass()
```

The engine is pure arithmetic and knows nothing about Flutter, time zones or
notifications; that's what makes the 16-slot / midnight requirement provable in a
test rather than by tapping around.

**Single write path.** `showQuickWaterSheet(context, ref)` is the only UI affordance
that logs a glass, and `WaterHeroCard.onQuickAdd` delegates to it. Notification
actions land in the same repository method with `source: notification|snooze`.

### 4.2 Medication

Doses are materialised per day from `medicines.reminder_minutes` × weekday mask ×
date range, keyed uniquely by `(medicine_id, day_key, scheduled_minute)` — so a
double schedule attempt is harmless, and a timezone change cannot duplicate a dose.

State machine:

```
scheduled ──took───────→ taken
          ──skip───────→ skipped
          ──later──────→ snoozed ──(elapses)──→ scheduled
          ──(day ends, still scheduled)──────→ missed
```

`taken` is **never** inferred. If she does not answer, it stays `scheduled` and
becomes `missed` only after the day has passed. A missed dose is rendered as
information, never as failure, and the app never suggests taking a late dose —
that is a clinician's call.

### 4.3 Mind & Soul

* **Motivation** — `motivation_content.dart` holds 104 original messages in eight
  categories. `MotivationRepository.next()` avoids repeating the last N shown and
  respects favourites. Scheduling uses `AkashaNotificationIds.motivation(minute)`.
* **Journal** — long-form body, optional title/mood/tags, pinning, search.
  Local only unless sync is enabled.
* **Overthinking helper** — a six-field structured reflection (`situation`,
  `assumption`, `evidence_for`, `alternative`, `action_step`, `completed`). It
  asks questions; it never tells her what her feelings mean.
* **Breathing** — 4-4-6 pattern with a `CustomPainter` circle, `HapticFeedback`
  on phase change, sessions shorter than 30 s are not persisted (they were a
  mis-tap, not a practice).
* **Mood** — eight feelings × intensity 1–5 + optional note, aggregated into
  patterns over 7/30 days.
* **Gratitude** — three fields per day.

### 4.4 Reports

`ReportsRepository` composes `DailyReport` from real queries only:
water total vs target, dose counts by status, mood average, journal count,
gratitude presence, breathing minutes. `wellnessPoints` weights: water 40,
medicine 30 (full 30 when there are no doses to take), mood 10, journal 10,
gratitude 5, breathing 5. Weekly/monthly reports sum the day reports — no
separate code path, therefore no chance of the two disagreeing.

### 4.5 AI companion (optional, off by default)

* Off until she gives explicit consent (`ai_enabled` + `ai_consent_given`).
* Client calls `--dart-define=AKASHA_AI_ENDPOINT`; **no key ever ships**. If the
  define is absent the companion runs `localReflection`, a deterministic
  reflective prompt generator, and the UI labels it as offline.
* Before any outbound request, `AiCompanionService.detectSafety()` scans for crisis
  language. On a hit it returns `kCrisisSupportMessage` (emergency numbers, "tell
  someone you trust") and **does not call the model**.
* The Cloud Function re-checks the same phrases server-side before calling the
  provider — a defence that survives a modified client.

---

## 5. Notification architecture

See `docs/NOTIFICATIONS.md` for the operational detail. Architecturally:

* **`NotificationService`** owns the plugin: init, channels, permission requests,
  display, cancel, launch payload.
* **`ReminderScheduler`** owns *what* is scheduled: a rolling horizon
  (`scheduleHorizonDays`) of exact alarms, rebuilt on launch, resume, settings
  change, timezone/time change and boot.
* **`AkashaNotificationIds`** derives stable `int` ids from domain + minute
  (water, motivation, love notes) or a deterministic FNV-1a hash
  (medicine, snoozes), each in its own numeric band.
* **`PendingActionQueue`** persists payloads that arrive while the app is dead;
  `NotificationActionController.drainPending()` applies them once the DB is open.
  This is what makes "I drank water" work from a terminated app.

**Wire format** for action payloads: `kind|refId|value|slotMinute`
(e.g. `water||250|540`). Action ids: `drankWater=1, skipWater=2, snoozeWater=3,
tookMedicine=10, skipMedicine=11, snoozeMedicine=12, openApp=20`.

---

## 6. Offline-first sync

### 6.1 Record contract

Every syncable table carries:

| Column | Meaning |
|---|---|
| `id` | UUID v4, generated on-device |
| `created_at` | epoch ms, immutable |
| `updated_at` | epoch ms, bumped on every local change |
| `deleted_at` | tombstone, `NULL` when alive |
| `dirty` | `1` until the row is confirmed uploaded |

### 6.2 Flow

```
local write → row(dirty=1) → sync_queue (collapsed per record) → push → dirty=0
                                                          ↓
                          pull (remote updated_at > local updated_at) → merge
```

* **Collapsing:** a record edited five times produces one queue entry, not five.
* **Backoff:** `next_attempt_at` doubles per failure; `status` moves
  `pending → in_flight → done | failed`.
* **Conflict resolution: last-writer-wins per record on `updated_at`.**
  Deterministic, symmetric, and it cannot resurrect stale data in either
  direction. Deletion is a tombstone with a fresh `updated_at`, so a delete beats
  an older edit and an edit made *after* the delete beats the tombstone. Field-level
  merging is deliberately not attempted: with one owner on at most two devices,
  LWW is honest and explainable, and it is proven by
  `test/unit/sync_logic_test.dart`.
* **Never destructive:** merging never deletes a local row that the remote does not
  know about, and a pull never overwrites a locally dirty row with older data.

### 6.3 Backends

```
abstract class CloudBackend {
  Future<CloudAuthResult> signIn / signUp / signOut;
  Future<void> push / Future<List<Map>> pull;
  bool get isConfigured;
}
```

* `FirestoreBackend` — `users/{uid}/{entity}/{recordId}`, only used when
  `Firebase.initializeApp` succeeded.
* `LocalOnlyBackend` — returns "not configured", makes every sync call a no-op
  success. This is the default and it is a real implementation, not a stub: it is
  what the app uses in the shipped default configuration, and the tests exercise
  it directly.

---

## 7. Error handling

`Result<T>` (`lib/core/utils/result.dart`) is used for operations that can fail in
ways the UI must narrate (sync, export, TTS). Failures carry a human sentence,
never a stack trace, never an error code alone.

* Repository reads throw; providers convert to `AsyncError`, and the UI shows
  `ErrorStateView` with a retry.
* Reminder failures are collected into `SchedulingReport` rather than thrown —
  one bad slot must not stop the other fifteen from being scheduled.
* All swallowed exceptions log through `debugPrint` in debug builds only.

---

## 8. Performance notes

* Indexes on every hot filter: `(user_id, day_key)` on all day-bucketed tables,
  unique `(user_id, minute_of_day)` on reminders, unique
  `(medicine_id, day_key, scheduled_minute)` on logs.
* Dashboards read pre-aggregated summaries (e.g. `DailyWaterSummary`) rather than
  N+1 queries.
* Charts receive at most 30 points.
* `StatefulShellRoute.indexedStack` keeps each tab alive: switching tabs costs
  nothing and never re-runs the boot path.
* Only `AppDurations`-based animations; no infinite animations except the breathing
  circle (which stops when the screen is not visible).

---

## 9. Deliberate deviations from the specification

| Spec asked for | Built | Why |
|---|---|---|
| Drift (codegen ORM) | `sqflite` behind repositories | Zero codegen = opens and builds in Android Studio on any recent Flutter, no generated-code drift. Same features: migrations, FKs, indexes, transactions. |
| A reference screenshot | Palette/gradient tokens from the brief | The Google Drive link was not reachable from the build environment. |
| Bundled fonts/audio | System font + system TTS, with asset folders documented | Shipped binaries that cannot be licence-verified are worse than none; `assets/fonts/README.md` explains how to drop in Poppins. |
| `fl_chart` for every chart | `fl_chart` for week/month trends, custom painters for the ring/droplet | The two hero visuals need exact art direction; a charting library cannot produce them. |

---

## 10. Extension points

* **New tracked metric** → table + model + repository + a provider in
  `providers.dart` + a card. Touch nothing else.
* **New notification type** → new band in `AkashaNotificationIds`, a channel in
  `NotificationService`, a branch in `ReminderScheduler.rescheduleAll`, an action
  id in `NotificationActionController`.
* **Real ML/cloud AI** → implement `CloudBackend` (or extend the function in
  `firebase/functions/index.js`); the UI already renders a degraded offline mode,
  so the feature is never "broken", just less clever.
