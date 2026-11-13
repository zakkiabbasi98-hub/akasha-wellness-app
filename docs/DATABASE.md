# AKASHA — Database

SQLite, one file, opened once, wrapped in transactions. Access is funnelled
through `AppDatabase` (`lib/core/database/app_database.dart`); the schema lives in
`lib/core/database/schema.dart`.

* File: `<app documents>/akasha.db`
* Engine: `sqflite` (no codegen — see §8)
* `PRAGMA foreign_keys = ON` on every connection
* Schema version: **3**

---

## 1. Conventions

| Convention | Detail |
|---|---|
| Primary keys | `TEXT`, UUID v4 (`lib/core/utils/id.dart`). Client-generated so offline devices never collide. |
| Timestamps | `INTEGER` epoch **milliseconds**. `created_at`, `updated_at`, `deleted_at`, plus domain stamps (`logged_at`, `started_at`, `delivered_at`). |
| Day bucket | `day_key TEXT 'yyyy-MM-dd'` in **local** time — cheap grouping, indexable, timezone-safe at write time. |
| Soft delete | `deleted_at IS NOT NULL`. Used for everything that syncs. Hard deletes only for caches (pruned notification history, resolved queue entries). |
| Sync flag | `dirty INTEGER DEFAULT 1` — set on every local mutation, cleared after a successful push. |
| Booleans | `INTEGER 0/1`. |
| Enums | `TEXT` with the allowed values listed in a trailing comment; parsing is total (unknown → documented fallback, never a crash). |
| Free text | Never `NOT NULL` unless the feature is meaningless without it. |

### The common column block

```sql
id          TEXT PRIMARY KEY,
created_at  INTEGER NOT NULL,
updated_at  INTEGER NOT NULL,
deleted_at  INTEGER,
dirty       INTEGER NOT NULL DEFAULT 1
```

Present on all 20 tables so a future sync engine needs no migration.

### Writing a row (the rule that fixes `NOT NULL constraint failed: …created_at`)

`created_at` is `NOT NULL` on every table, so **every INSERT map must carry it**.
The helpers exist so that is impossible to forget:

| Helper | Use for | Writes |
|---|---|---|
| `AppDatabase.insertRow(map, createdAt:)` | INSERT, or a REPLACE-style overwrite | `created_at` (model's own value, else now), `updated_at`, `dirty = 1` |
| `AppDatabase.touch(map)` | an UPDATE patch | `updated_at`, `dirty = 1` — **never** `created_at` |
| `AppDatabase.upsert(executor, table, row, markDirty:)` | create-or-update by `id` | as above; keeps the existing `created_at`, can resurrect a soft-deleted row |

Every model's `toRow()` is insert-shaped through `insertRow`, so it is valid for
an INSERT *and* for an UPDATE (where writing the row's real `created_at` back is
exactly what "preserve created_at" means).

`ConflictAlgorithm.replace` is avoided throughout: SQLite implements REPLACE as
**DELETE + INSERT**, which silently resets `created_at` and bypasses the
foreign-key cascade. `AppDatabase.upsert` is the replacement.

### Writing more than one row

One transaction, one owner. The outermost call opens it (`AppDatabase.write`,
`AppDatabase.transaction`, or `db.transaction` in a screen) and every repository
method beneath it takes `txn:` and uses that executor. `Database.transaction` is
not re-entrant; a nested `BEGIN` fails with
`cannot start a transaction within a transaction`.

---

## 2. Entity map

```
users ──1:1── user_settings
  │
  ├──1:N── water_reminders
  ├──1:N── water_logs
  ├──1:N── water_snoozes
  ├──1:N── medicines ──1:N── medicine_logs
  │        └────1:N── medicine_schedules (materialised days)
  ├──1:N── mood_entries
  ├──1:N── journal_entries
  ├──1:N── reflections
  ├──1:N── gratitude_entries
  ├──1:N── breathing_sessions
  ├──1:N── love_notes
  ├──1:N── scheduled_motivations ──N:1── motivational_messages
  ├──1:N── notification_history
  ├──1:N── ai_messages
  └──1:N── sync_queue

motivational_messages  (global content, not user-owned)
```

---

## 3. Tables

### 3.1 `users`

| Column | Type | Notes |
|---|---|---|
| `display_name` | TEXT NOT NULL | "Akasha" by default; she can change it. |
| `local_only` | INTEGER DEFAULT 1 | 1 = no cloud identity attached. |
| `firebase_uid` | TEXT NULL | Set only after a real sign-in. |
| `email` | TEXT NULL | Only if sync is enabled. |
| `onboarded_at` | INTEGER NULL | Non-null ⇒ skip onboarding. |
| `cloud_linked_at` | INTEGER NULL | Last successful link. |

Exactly one row in practice (`currentUserIdProvider`). The schema stays
user-scoped so a second profile is not a migration.

### 3.2 `user_settings` — one row per user

Every preference, typed rather than key/value (so a typo is a compile error and a
bad value cannot be silently stored as a string).

| Group | Columns | Defaults |
|---|---|---|
| Water targets | `water_target_ml`, `glass_size_ml`, `small_glass_ml`, `large_glass_ml` | 2000 / 250 / 150 / 350 |
| Water window | `water_start_min`, `water_end_min`, `water_interval_min` | 540 (09:00), 0 (12:00 AM), 60 |
| Pause flags | `water_reminders_paused`, `medicine_reminders_paused` | 0 |
| Snooze | `snooze_minutes` | 15 |
| Quiet hours | `quiet_mode_enabled`, `quiet_start_min`, `quiet_end_min`, `quiet_pause_water`, `quiet_pause_motivation`, `quiet_pause_medicine` | on, 22:30, 07:00, 1, 1, **0** |
| Voice | `voice_enabled`, `voice_profile`, `voice_rate`, `voice_pitch` | 1, `soft_feminine`, 0.46, 1.08 |
| Feedback | `sound_enabled`, `vibration_enabled`, `alarm_style` | 1, 1, 1 |
| Motivation | `motivation_enabled`, `motivation_per_day`, `motivation_categories` | 1, 3, `''` = all |
| Notes | `love_notes_enabled` | 1 |
| Appearance | `theme_mode` (`system`/`light`/`dark`), `language_code` | system, en |
| Consent | `ai_enabled`, `ai_consent_given`, `sync_enabled`, `sync_consent_given` | **all 0** |
| Security | `app_lock_enabled` | 0 |
| Sync | `last_sync_at` | NULL |

`quiet_pause_medicine` defaults to **0** on purpose: silencing medication reminders
by default would be the app making a health decision.

### 3.3 `water_reminders`

| Column | Notes |
|---|---|
| `minute_of_day` | 0..1439. `0` = 12:00 AM (midnight). |
| `label` | e.g. "Midday sip". |
| `amount_ml` | Suggested amount for that slot. |
| `enabled` | Per-slot mute. |
| `is_default_slot` | Lets "restore defaults" distinguish her own slots. |
| `sort_order` | Stable timeline ordering. |

**Unique index** `(user_id, minute_of_day)` — restoring defaults or re-adding a
slot cannot create duplicates; the insert is `ConflictAlgorithm.replace`.

Defaults are generated by `WaterScheduleEngine.generate(start: 540, end: 0,
interval: 60)` → **09:00, 10:00, …, 23:00, 00:00 = 16 slots**, midnight included.
`AppConstants.expectedDefaultWaterSlots == 16` and the unit test asserts the list
verbatim.

### 3.4 `water_logs`

| Column | Notes |
|---|---|
| `day_key` | Local day of the drink (what reports group by). |
| `logged_at` | Exact ms — lets a 23:59 drink still count for today. |
| `amount_ml` | Positive. |
| `source` | `manual` \| `notification` \| `snooze` \| `quick_add`. |
| `reminder_minute` | Which slot it answered, if any (enables "response rate"). |
| `glass_size` | `small` \| `medium` \| `large` \| `custom`. |
| `note` | Optional. |

Indexes: `(user_id, day_key)`, `(user_id, logged_at)`.

### 3.5 `water_snoozes`

One row per "Later" tap: `reminder_minute`, `scheduled_for`, `fired_at`,
`status` (`pending`/`fired`/`cancelled`). Kept so the diagnostics screen can show
what actually happened and so a cancelled snooze is not silently re-armed.

### 3.6 `medicines`

| Column | Notes |
|---|---|
| `name` | Her spelling. |
| `dosage` | **Free text copied from the prescription.** The app never computes, splits or recommends a dose. |
| `category` | `morning` \| `afternoon` \| `night` \| `custom` (colour grouping only). |
| `start_day`, `end_day` | `day_key`; `end_day NULL` = ongoing. |
| `weekdays` | `'1,2,3,4,5,6,7'` (1 = Monday). |
| `reminder_minutes` | Comma-separated minutes of day, e.g. `'480,1200'`. |
| `enabled`, `with_food`, `notes`, `color_hex` | Presentation + context. |

### 3.7 `medicine_schedules`

Materialised `(medicine_id, day_key, minute_of_day)` within the scheduling horizon.
Exists so a dose's existence is a database fact, not a runtime calculation that
could shift if her phone's timezone changes. Index `(user_id, day_key,
minute_of_day)`.

### 3.8 `medicine_logs`

| Column | Notes |
|---|---|
| `medicine_id`, `schedule_id` | `schedule_id` nullable for ad-hoc entries. |
| `day_key`, `scheduled_minute` | The dose this row is about. |
| `status` | `scheduled` \| `taken` \| `skipped` \| `snoozed` \| `missed`. |
| `responded_at`, `snoozed_until`, `notes` | Audit. |

**Unique index** `(medicine_id, day_key, scheduled_minute)` — the day is
idempotent, so a reschedule races into a `replace` instead of two doses.

`status` starts at `scheduled` and **only** a user action can move it to `taken`.
A reconciliation pass flips `scheduled → missed` once the day has ended
(`skipped` is her decision; `missed` is the app's bookkeeping).

### 3.9 `motivational_messages` (global)

`category`, `text`, `is_favorite`, `last_shown_at`, `show_count`,
`source` (`builtin`/`cloud`/`custom`). 104 rows seeded from
`lib/content/motivation_content.dart` across 8 categories. `last_shown_at` +
`show_count` implement anti-repetition rotation; `is_favorite` survives resets she
did not ask for.

### 3.10 `scheduled_motivations`

Per-user reminder times for encouragement: `minute_of_day`, optional pinned
`message_id`, `enabled`.

### 3.11 `mood_entries`

`day_key`, `mood` (enum key), `intensity` 1..5, `note`, `logged_at`. Multiple
entries per day are allowed; the dashboard shows the latest, the report averages
intensity.

### 3.12 `journal_entries`

`title` (nullable), `body` (required), `mood`, `tags` (comma separated),
`is_pinned`, `created_local`. Body is the only long-text column in the app and is
capped at `AppConstants.journalMaxLength`.

### 3.13 `reflections`

The overthinking helper, one row per session:
`situation`, `assumption`, `evidence_for`, `alternative`, `action_step`,
`completed`, `mood_after`.

### 3.14 `gratitude_entries`

`first` (required), `second`, `third` — three things, one row per day.

### 3.15 `breathing_sessions`

`started_at`, `duration_seconds`, `completed`, `pattern` (default `4-4-6`).
Sessions under 30 s are discarded before insert.

### 3.16 `love_notes`

`text`, `author` (default "Someone who cares"), `minute_of_day`, `enabled`,
`is_favorite`, `last_delivered_at`, `delivery_count`, `source`
(`local`/`remote`). Local by default; `remote` is reserved for a future shared
inbox, and nothing is fetched until she asks for it.

### 3.17 `notification_history`

Audit trail so the app can be honest about what it did:
`kind` (`water`/`medicine`/`motivation`/`love_note`/`report`), `ref_id`, `title`,
`body`, `scheduled_for`, `delivered_at`, `action_taken`
(`taken`/`skipped`/`snoozed`/`opened`/`none`), `action_at`.
Index on `delivered_at`; `prune(keepDays: 90)` deletes anything older than 90
days on app start (hard delete — it is an audit cache, not her content).

### 3.18 `ai_messages`

`role` (`user`/`assistant`), `content`, `created_local`, `flagged`
(1 = a safety response was substituted). Stored locally so the conversation is
hers, exportable and deletable — never a remote log.

### 3.19 `sync_queue`

| Column | Notes |
|---|---|
| `entity`, `entity_id` | What to push. |
| `operation` | `upsert` \| `delete`. |
| `payload` | JSON snapshot at enqueue time. |
| `attempts`, `last_error`, `next_attempt_at` | Backoff state. |
| `status` | `pending` \| `in_flight` \| `failed` \| `done`. |

Index `(status, next_attempt_at)` — the drain query. One entry per record
(collapsed on insert), so retry storms are impossible.

---

## 4. Indexes

```sql
CREATE INDEX idx_water_logs_day        ON water_logs (user_id, day_key);
CREATE INDEX idx_water_logs_time       ON water_logs (user_id, logged_at);
CREATE UNIQUE INDEX idx_water_reminders_slot ON water_reminders (user_id, minute_of_day);
CREATE INDEX idx_water_snoozes_status  ON water_snoozes (user_id, status, scheduled_for);
CREATE INDEX idx_med_sched_day         ON medicine_schedules (user_id, day_key, minute_of_day);
CREATE INDEX idx_med_logs_day          ON medicine_logs (user_id, day_key);
CREATE UNIQUE INDEX idx_med_logs_unique ON medicine_logs (medicine_id, day_key, scheduled_minute);
CREATE INDEX idx_mood_day              ON mood_entries (user_id, day_key);
CREATE INDEX idx_journal_day           ON journal_entries (user_id, day_key);
CREATE INDEX idx_gratitude_day         ON gratitude_entries (user_id, day_key);
CREATE INDEX idx_breathing_day         ON breathing_sessions (user_id, day_key);
CREATE INDEX idx_reflections_day       ON reflections (user_id, day_key);
CREATE INDEX idx_motivation_category   ON motivational_messages (category);
CREATE INDEX idx_love_notes_enabled    ON love_notes (user_id, enabled);
CREATE INDEX idx_notif_history_time    ON notification_history (delivered_at);
CREATE INDEX idx_sync_queue_status     ON sync_queue (status, next_attempt_at);
CREATE INDEX idx_ai_messages_time      ON ai_messages (user_id, created_local);
```

The two `UNIQUE` indexes are correctness constraints, not tuning: they are what
make "restore defaults" and "materialise today's doses" safe to run twice.

---

## 5. Representative queries

**Today's water**
```sql
SELECT COALESCE(SUM(amount_ml), 0) AS total, COUNT(*) AS glasses
FROM water_logs
WHERE user_id = ? AND day_key = ? AND deleted_at IS NULL;
```

**Last 7 days (chart), zero-filled in Dart**
```sql
SELECT day_key, SUM(amount_ml) AS total
FROM water_logs
WHERE user_id = ? AND day_key BETWEEN ? AND ? AND deleted_at IS NULL
GROUP BY day_key ORDER BY day_key;
```

**Today's doses with medicine context**
```sql
SELECT l.*, m.name, m.dosage, m.color_hex
FROM medicine_logs l
JOIN medicines m ON m.id = l.medicine_id
WHERE l.user_id = ? AND l.day_key = ? AND l.deleted_at IS NULL
ORDER BY l.scheduled_minute;
```

**Missed reconciliation (run after midnight, previous days only)**
```sql
UPDATE medicine_logs
SET status = 'missed', updated_at = ?, dirty = 1
WHERE user_id = ? AND status IN ('scheduled','snoozed') AND day_key < ?;
```

**Queue drain**
```sql
SELECT * FROM sync_queue
WHERE status IN ('pending','failed') AND (next_attempt_at IS NULL OR next_attempt_at <= ?)
ORDER BY created_at LIMIT 50;
```

---

## 6. Transactions that matter

* **First-run seeding** (`SeedService.ensureFirstRunData`) — profile + settings +
  16 reminder slots + the message library in **one** transaction, with the
  repositories handed that transaction. A failure rolls the whole first run back,
  so onboarding can never be marked complete on top of a half-seeded database.
* **Onboarding completion** (`OnboardingScreen._finish`) — profile/`onboarded_at`
  + settings + schedule + optional example medicine + motivation slots in one
  transaction. Notification permissions and alarm materialisation happen *after*
  the commit and are best-effort: denying notifications is not a setup failure.
* **Restore defaults** — soft-delete the live default slots, then upsert the
  engine's 16 slots, atomic. Tombstones have their `minute_of_day` parked above
  1440 first so the partial unique index stays satisfiable.
* **Notification action** — the dedupe claim, the water log / dose response and
  the history row commit together; the profile and settings reads inside it use
  the same transaction.
* **Logging a glass from a notification** — the action queue entry, the water log,
  the history row and the queue bump commit together.
* **Sync push batch** — per record, so one failure cannot roll back its neighbours.

---

## 7. Migrations

`DbSchema.migrations` maps "from version N" to the statements that reach N+1;
`AppDatabase.onUpgrade` applies every step from the file's version upwards. Rules:

1. Never rename or repurpose a column in place; add the new one and backfill.
2. Every migration must be idempotent-safe (`IF NOT EXISTS`) because OEM ROMs
   occasionally crash mid-upgrade.
3. Bump `DbSchema.version` in the same commit as the `CREATE TABLE` change.
4. Seed data lives in `SeedService`, not in migrations.
5. Migrations are **additive**. No `DROP TABLE`, no data deletion.

| Step | Changes |
|---|---|
| v1 → v2 | Adds `notification_actions` (exactly-once ledger for notification button presses). Additive. |
| v2 → v3 | Repair: replaces `idx_water_reminders_slot` (`UNIQUE(user_id, minute_of_day)`, which did not exclude tombstones and so permanently reserved a minute once a slot was soft-deleted) with the partial index `idx_water_reminders_slot_live … WHERE deleted_at IS NULL`; parks tombstones above minute 1440 so the new index can be built; back-fills `created_at` only where it is NULL. No table or row is removed. |

`test/unit/notification_ledger_test.dart` and
`test/unit/first_run_repair_test.dart` exercise every step on the real SQLite
engine with real user rows.

---

## 8. Why `sqflite` and not Drift

The brief named Drift. Drift generates `.g.dart` files with `build_runner`, which
pins your Dart SDK and Drift version to the exact combination that generated them.
Any mismatch produces a project that will not compile on the first open in Android
Studio — the precise failure this delivery is meant to avoid.

`sqflite` gives the same guarantees that matter here (typed models, migrations,
foreign keys, indexes, transactions) with zero codegen and a first build that
works. Everything is behind repository interfaces, so the storage engine is a
one-file swap: replace `AppDatabase` and the model `fromMap`/`toMap` calls, touch
no screen. See `docs/ARCHITECTURE.md` §9.

---

## 9. Backup, export, deletion

* **Export** — JSON dump of every user-owned table, written to the app's documents
  directory and shared via `share_plus`. Local-only; nothing is uploaded.
* **Delete a record** — soft delete on screen, hard delete from the DB after the
  tombstone is pushed (or immediately when sync has never been enabled).
* **Wipe everything** — `AppDatabase.deleteEverything()` deletes every table in
  reverse dependency order inside one batch (children before `users`), then the
  first-run seeder rebuilds a fresh profile on the next launch. Deleting just the
  `users` row would also work through `ON DELETE CASCADE`, but the batch clears
  tables that are not user-owned too (`motivational_messages`, `sync_queue`), so
  nothing stale survives a wipe.
* **Cloud deletion** — `SyncService.deleteCloudAccount()` removes the Firestore
  subtree and the auth user, then disables sync locally. Local data is untouched
  unless she also wipes.
