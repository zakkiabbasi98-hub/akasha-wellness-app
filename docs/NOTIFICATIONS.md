# AKASHA — Notifications

Notifications are the spine of this app. If a reminder does not arrive, everything
else is decoration — so the whole path is one owner, deterministic ids, and an
idempotent rebuild.

---

## 1. The pipeline

```
            ┌──────────────────────── ReminderScheduler ───────────────────────┐
            │  reads settings + reminders + medicines + schedules + notes      │
            │  cancels everything, then re-materialises a 7-day horizon        │
            └───────────────┬──────────────────────────────────────────────────┘
                            │ zonedSchedule(exact or inexact)
                    ┌───────▼────────┐
                    │ NotificationService │  channels, permission, display
                    └───────┬────────┘
             fires          │
      ┌─────────────────────▼──────────────────────┐
      │ Notification (channel akasha_water)        │
      │ [ I drank water ] [ Skip ] [ Later ]       │
      └───────┬───────────────┬────────────┬───────┘
              │ action id 1   │ 2          │ 3
              ▼               ▼            ▼
      PendingActionQueue → NotificationActionController.drainPending()
              │
              ▼
      WaterRepository / MedicineRepository  →  SQLite  →  dataRevision++  →  UI
```

**Why a queue?** When the app is terminated, a notification action starts a
receiver process with no Flutter engine and no open database. The action payload is
written to durable storage immediately; the repository write happens the moment the
database is available (usually milliseconds later on launch, or instantly if the
app is alive). No tap is ever lost.

---

## 2. Channels

| Channel id | Name | Importance | Sound | Used for |
|---|---|---|---|---|
| `akasha_water` | Water reminders | High | yes | hydration slots + snoozes |
| `akasha_medicine` | Medicine reminders | High | yes | scheduled doses |
| `akasha_motivation` | Encouragement | Default | yes | motivation nudges |
| `akasha_love_notes` | Little love notes | Default | yes | love notes |
| `akasha_daily` | Daily summary | Low | no | 20:30 wind-down summary |

Channels are created once at startup. Importance is deliberately `High` for water
and medicine so heads-up banners are possible, and `Low` for the daily summary so
it never interrupts.

**Android will not let an app raise a channel's importance after creation.** If you
change these values, existing installs keep the old importance until the channel is
removed by the user. This is documented rather than worked around, because working
around it would mean silently deleting her customised channels.

Custom status-bar icons: `android/app/src/main/res/drawable/ic_stat_water.xml` and
`ic_stat_medicine.xml` (monochrome, 24 dp, white) are set explicitly on each
`AndroidNotificationDetails`, so the status bar shows a droplet or a pill instead of
a white square.

---

## 3. Notification ids

`lib/core/notifications/notification_ids.dart` — **the only** source of ids. Two
schemes existed during development; anything that does not use this class is a bug.

| Domain | Formula | Band |
|---|---|---|
| Water | `100000 + minuteOfDay` | 100 000–101 439 |
| Medicine | `300000 + FNV1a('$medicineId|$dayKey|$minute') % 200000` | 300 000–499 999 |
| Motivation | `500000 + minuteOfDay` | 500 000–501 439 |
| Love notes | `600000 + minuteOfDay` | 600 000–601 439 |
| Snoozes | `700000 + FNV1a('$snoozeId') % 200000` | 700 000–899 999 |
| Daily summary | `800001` | — |

Determinism is the point: re-scheduling the 09:00 water reminder with the same id
**replaces** it. If ids were random, every rebuild would stack a second alarm and
she would get two notifications at 09:00 forever.

Medicine ids include `dayKey` and `minute`, so a three-times-daily medicine produces
three independent alarms and a weekday-only medicine never fires on a Sunday.

---

## 4. Scheduling window

* `AppConstants.scheduleHorizonDays = 7` — a rolling week is materialised.
* `zonedSchedule` with `DateTimeComponents.time` semantics is **not** used; every
  slot is an individual absolute instant in the device's timezone, which is why
  quiet-hours suppression and DST are handled explicitly rather than hoped for.
* The horizon is rebuilt on: app launch, resume (after ≥15 min away, or when a
  clock/timezone change marker is pending), any settings write, any reminder edit,
  boot (`ScheduledNotificationBootReceiver`), and package update.
* Each rebuild starts with `cancelAll()`. Because ids are deterministic, even a
  rebuild that fails halfway cannot duplicate an alarm — the worst case is a
  missing one, which the next rebuild restores.

### Exact vs inexact

`exact: true` is used only when `canScheduleExactAlarms()` returns true (always on
< Android 12, a user grant on 12+). Otherwise `androidScheduleMode: inexactAllowWhileIdle`
is used, which may deliver a few minutes late. The app never silently upgrades
itself to exact alarms, and the diagnostics screen shows the current mode.

---

## 5. Quiet hours

Default window 22:30 → 07:00 (`quiet_start_min = 1350`, `quiet_end_min = 420`).
`AkashaDates.isWithinQuietHours` handles both same-day and overnight windows.

| Type | Default behaviour in quiet hours |
|---|---|
| Water | suppressed (a nudge to drink at 23:00 is noise, not care) |
| Motivation | suppressed |
| Medicine | **not** suppressed by default |
| Love notes | suppressed |
| Daily summary | 20:30 — outside the default window |

Each is a separate toggle in Notification settings. Silencing medication by default
would be the app making a medical decision on her behalf.

---

## 6. Action buttons

Payload wire format: **`kind|refId|value|slotMinute`**

| Kind | Example | Meaning |
|---|---|---|
| `water` | `water||250|540` | water slot 09:00, suggested 250 ml |
| `medicine` | `medicine|medlog:<medicineId>:2026-11-08:480||480` | that day's 08:00 dose |
| `motivation` | `motivation|msg-uuid||600` | open the message |
| `snooze` | `snooze|snooze-uuid|250|540` | a snooze re-fire |

Action ids (`lib/core/notifications/notification_service.dart`):

| Id | Action | Effect |
|---|---|---|
| 1 | I drank water | logs a glass (`source: notification`), marks history `taken` |
| 2 | Skip | marks history `skipped`, no log |
| 3 | Later | creates a `water_snoozes` row + re-arms at now + `snooze_minutes` |
| 10 | I took it | dose → `taken`, `responded_at = now` |
| 11 | Skip | dose → `skipped` |
| 12 | Later | dose → `snoozed`, `snoozed_until = now + snooze` |
| 20 | Open AKASHA | launches the app to the relevant screen |

The medicine payload carries the **deterministic log-row id**
(`MedicineRepository.logIdFor`), not just the medicine id, because "I took it"
must address one specific dose on one specific day. If that row has not been
materialised yet (fresh install, or the app slept past midnight),
`recordResponse` recreates it from the id rather than dropping the tap — a press
is never silently lost.

`flutter_local_notifications` **cannot** change a notification's content in place
for these actions (no `markAsCompleted` / semantic-action API in 17.2.3), so the
tapped notification is dismissed and the audit trail in `notification_history` is
what proves the action happened. The Reminder history screen reads that table.

### Working in every app state

| App state | Path | Verified how |
|---|---|---|
| Foreground | plugin callback → `NotificationActionController` directly | reasoning + code path |
| Background | `ActionBroadcastReceiver` → callback → queue → drain | reasoning + code path |
| Terminated | receiver starts the isolate → callback → queue → next launch drains | reasoning + code path |
| Device locked | same as background; **full-screen intent** when granted | reasoning + code path |

> **Honest status:** these four paths are implemented and wired end-to-end, but
> they have **not been executed on a physical device in this build environment**
> (no Android SDK/emulator available). `docs/TESTING.md` lists the exact manual
> procedure to verify each one before you trust it. Claiming otherwise would be a
> lie.

### Full-screen (lock-screen) reminders

`USE_FULL_SCREEN_INTENT` + `alarm_style` settings. When Android grants it, a
reminder can appear over the lock screen. When it does not (Android 14 can revoke
it, and users can turn it off), the same reminder arrives as a heads-up
notification. The app detects the capability and says so in Diagnostics; it never
pretends the stronger behaviour is available.

---

## 7. Reboot and time changes

| Event | Handler | Result |
|---|---|---|
| `BOOT_COMPLETED`, `QUICKBOOT_POWERON`, `MY_PACKAGE_REPLACED` | `ScheduledNotificationBootReceiver` (plugin-provided) | pending alarms restored by the plugin |
| Clock set / timezone changed | `TimeChangeReceiver.kt` → marker in `akasha_native_events` SharedPreferences | on next launch/resume the marker is consumed and the full horizon is rebuilt |
| App resumed after ≥15 min | `AkashaApp._onResume` | full rebuild |

`TimeChangeReceiver` deliberately does **not** start a Flutter engine: that would
cost ~200 ms of RAM and a cold isolate just to write a timestamp. It writes
`reschedule_requested_at`; `MainActivity.consumeRescheduleRequest()` returns the
timestamp once and clears it, and `main.dart` clears the marker after the boot
rebuild so a change is never applied twice.

---

## 8. Permissions

| Permission | Requested when | If denied |
|---|---|---|
| `POST_NOTIFICATIONS` (33+) | first reminder flow, and Diagnostics | no reminders at all; the app is still fully usable |
| `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM` | Diagnostics "Fix" | reminders become inexact |
| `USE_FULL_SCREEN_INTENT` | settings toggle | heads-up instead of full screen |
| `RECEIVE_BOOT_COMPLETED` | manifest only | reminders lost after reboot until the app opens |
| `VIBRATE` | manifest only | silent feedback |

Permission requests are always preceded by a plain-language explanation and are
never repeated naggingly: once denied, the diagnostics screen offers a link to the
system settings instead of re-prompting.

---

## 9. What the app deliberately does not do

* ❌ No overlays, no floating bubbles, no "draw over other apps".
* ❌ No accessibility-service abuse.
* ❌ No bypassing Do Not Disturb or silent mode.
* ❌ No re-posting a dismissed notification to get attention.
* ❌ No more than `WaterScheduleEngine.maxSlots` (96) reminders per day — the
  engine throws rather than let a bad interval spam the phone.
* ❌ No "you failed" follow-up when a reminder is missed.
* ❌ No notification that cannot be turned off in settings.

Android's own rules (force-stop cancels alarms, OEM battery managers delay
background work) are surfaced in Diagnostics and the README rather than worked
around with tricks that break policy.

---

## 10. Testing notifications manually

1. Launch the app, complete onboarding, accept notification permission.
2. Settings → Diagnostics → confirm all rows are green (or use the Fix buttons).
3. Tap **Test reminder** → a water notification appears within a second.
4. Lock the phone, wait for a scheduled slot (or set one for 2 minutes ahead).
5. Press **I drank water** on the lock screen → unlock → Home shows the glass.
6. Force-stop the app (Settings → Apps → AKASHA → Force stop), wait for the next
   slot, press **Later** → reopen → the snooze is queued and re-armed.
7. Reboot the phone → confirm reminders still fire.
8. Change timezone → reopen the app → Diagnostics shows the rebuilt horizon.
