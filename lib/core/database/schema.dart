/// SQLite schema for AKASHA.
///
/// Design rules (see docs/DATABASE.md for the full rationale):
///  * Every user-owned row carries `id` (UUID v4), `created_at`, `updated_at`,
///    `deleted_at` and `dirty` so offline-first sync is possible without
///    changing the schema later.
///  * Deletes are SOFT (`deleted_at`) for anything that syncs; hard deletes are
///    only used for short-lived caches (notification history pruning).
///  * Timestamps are epoch milliseconds (UTC-safe on disk, local in the app).
///  * Day-bucketed queries use `day_key` (`yyyy-MM-dd`) for cheap indexes.
abstract final class DbSchema {
  static const int version = 1;

  /// Common sync/audit columns. `id` is TEXT because records are created
  /// offline on many devices.
  static const String commonColumns = '''
    id TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    deleted_at INTEGER,
    dirty INTEGER NOT NULL DEFAULT 1
  ''';

  static const List<String> tables = [
    'users',
    'user_settings',
    'water_reminders',
    'water_logs',
    'water_snoozes',
    'medicines',
    'medicine_schedules',
    'medicine_logs',
    'motivational_messages',
    'scheduled_motivations',
    'mood_entries',
    'journal_entries',
    'reflections',
    'gratitude_entries',
    'breathing_sessions',
    'love_notes',
    'notification_history',
    'ai_messages',
    'sync_queue',
  ];

  /// Statements run inside `onCreate`.
  static List<String> createStatements() => [
        // ── Local profile ────────────────────────────────────────────────
        '''
        CREATE TABLE users (
          $commonColumns,
          display_name TEXT NOT NULL,
          local_only INTEGER NOT NULL DEFAULT 1,
          firebase_uid TEXT,
          email TEXT,
          onboarded_at INTEGER,
          cloud_linked_at INTEGER
        )
        ''',

        // ── Settings: one row per user, typed columns (fast + typed) ─────
        '''
        CREATE TABLE user_settings (
          $commonColumns,
          user_id TEXT NOT NULL,
          water_target_ml INTEGER NOT NULL DEFAULT 2000,
          glass_size_ml INTEGER NOT NULL DEFAULT 250,
          small_glass_ml INTEGER NOT NULL DEFAULT 150,
          large_glass_ml INTEGER NOT NULL DEFAULT 350,
          water_start_min INTEGER NOT NULL DEFAULT 540,     -- 09:00
          water_end_min INTEGER NOT NULL DEFAULT 0,         -- 12:00 AM (midnight)
          water_interval_min INTEGER NOT NULL DEFAULT 60,
          water_reminders_paused INTEGER NOT NULL DEFAULT 0,
          medicine_reminders_paused INTEGER NOT NULL DEFAULT 0,
          snooze_minutes INTEGER NOT NULL DEFAULT 15,
          quiet_mode_enabled INTEGER NOT NULL DEFAULT 1,
          quiet_start_min INTEGER NOT NULL DEFAULT 1350,    -- 22:30
          quiet_end_min INTEGER NOT NULL DEFAULT 420,       -- 07:00
          quiet_pause_water INTEGER NOT NULL DEFAULT 1,
          quiet_pause_motivation INTEGER NOT NULL DEFAULT 1,
          quiet_pause_medicine INTEGER NOT NULL DEFAULT 0,  -- never silent by default
          voice_enabled INTEGER NOT NULL DEFAULT 1,
          voice_profile TEXT NOT NULL DEFAULT 'soft_feminine',
          voice_rate REAL NOT NULL DEFAULT 0.46,
          voice_pitch REAL NOT NULL DEFAULT 1.08,
          sound_enabled INTEGER NOT NULL DEFAULT 1,
          vibration_enabled INTEGER NOT NULL DEFAULT 1,
          alarm_style INTEGER NOT NULL DEFAULT 1,           -- allow full-screen intent
          motivation_enabled INTEGER NOT NULL DEFAULT 1,
          motivation_per_day INTEGER NOT NULL DEFAULT 3,
          motivation_categories TEXT NOT NULL DEFAULT '',
          love_notes_enabled INTEGER NOT NULL DEFAULT 1,
          theme_mode TEXT NOT NULL DEFAULT 'system',
          language_code TEXT NOT NULL DEFAULT 'en',
          ai_enabled INTEGER NOT NULL DEFAULT 0,
          ai_consent_given INTEGER NOT NULL DEFAULT 0,
          sync_enabled INTEGER NOT NULL DEFAULT 0,
          sync_consent_given INTEGER NOT NULL DEFAULT 0,
          app_lock_enabled INTEGER NOT NULL DEFAULT 0,
          last_sync_at INTEGER,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
        ''',

        // ── Water ───────────────────────────────────────────────────────
        '''
        CREATE TABLE water_reminders (
          $commonColumns,
          user_id TEXT NOT NULL,
          label TEXT NOT NULL DEFAULT 'Water reminder',
          minute_of_day INTEGER NOT NULL,
          amount_ml INTEGER NOT NULL DEFAULT 250,
          enabled INTEGER NOT NULL DEFAULT 1,
          is_default_slot INTEGER NOT NULL DEFAULT 1,
          sort_order INTEGER NOT NULL DEFAULT 0,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
        ''',
        '''
        CREATE TABLE water_logs (
          $commonColumns,
          user_id TEXT NOT NULL,
          day_key TEXT NOT NULL,
          logged_at INTEGER NOT NULL,
          amount_ml INTEGER NOT NULL,
          source TEXT NOT NULL DEFAULT 'manual',  -- manual|notification|snooze|quick_add
          reminder_minute INTEGER,
          glass_size TEXT,                        -- small|medium|large|custom
          note TEXT,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
        ''',
        '''
        CREATE TABLE water_snoozes (
          $commonColumns,
          user_id TEXT NOT NULL,
          reminder_minute INTEGER NOT NULL,
          scheduled_for INTEGER NOT NULL,
          fired_at INTEGER,
          status TEXT NOT NULL DEFAULT 'pending', -- pending|fired|cancelled
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
        ''',

        // ── Medicine ────────────────────────────────────────────────────
        '''
        CREATE TABLE medicines (
          $commonColumns,
          user_id TEXT NOT NULL,
          name TEXT NOT NULL,
          dosage TEXT,
          notes TEXT,
          category TEXT NOT NULL DEFAULT 'morning', -- morning|afternoon|night|custom
          start_day TEXT NOT NULL,
          end_day TEXT,
          weekdays TEXT NOT NULL DEFAULT '1,2,3,4,5,6,7',
          enabled INTEGER NOT NULL DEFAULT 1,
          with_food TEXT,                           -- free text from prescription
          color_hex TEXT NOT NULL DEFAULT 'F2A9CE',
          reminder_minutes TEXT NOT NULL DEFAULT '480', -- comma separated
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
        ''',
        '''
        CREATE TABLE medicine_schedules (
          $commonColumns,
          user_id TEXT NOT NULL,
          medicine_id TEXT NOT NULL,
          minute_of_day INTEGER NOT NULL,
          day_key TEXT NOT NULL,
          enabled INTEGER NOT NULL DEFAULT 1,
          FOREIGN KEY (medicine_id) REFERENCES medicines (id) ON DELETE CASCADE,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
        ''',
        '''
        CREATE TABLE medicine_logs (
          $commonColumns,
          user_id TEXT NOT NULL,
          medicine_id TEXT NOT NULL,
          schedule_id TEXT,
          day_key TEXT NOT NULL,
          scheduled_minute INTEGER NOT NULL,
          responded_at INTEGER,
          status TEXT NOT NULL DEFAULT 'scheduled', -- scheduled|taken|skipped|snoozed|missed
          snoozed_until INTEGER,
          notes TEXT,
          FOREIGN KEY (medicine_id) REFERENCES medicines (id) ON DELETE CASCADE,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
        ''',

        // ── Motivation ──────────────────────────────────────────────────
        '''
        CREATE TABLE motivational_messages (
          $commonColumns,
          category TEXT NOT NULL,
          text TEXT NOT NULL,
          is_favorite INTEGER NOT NULL DEFAULT 0,
          last_shown_at INTEGER,
          show_count INTEGER NOT NULL DEFAULT 0,
          source TEXT NOT NULL DEFAULT 'builtin'  -- builtin|cloud|custom
        )
        ''',
        '''
        CREATE TABLE scheduled_motivations (
          $commonColumns,
          user_id TEXT NOT NULL,
          message_id TEXT,
          minute_of_day INTEGER NOT NULL,
          enabled INTEGER NOT NULL DEFAULT 1,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
        ''',

        // ── Mind & Soul ─────────────────────────────────────────────────
        '''
        CREATE TABLE mood_entries (
          $commonColumns,
          user_id TEXT NOT NULL,
          day_key TEXT NOT NULL,
          mood TEXT NOT NULL,
          intensity INTEGER NOT NULL DEFAULT 3,
          note TEXT,
          logged_at INTEGER NOT NULL,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
        ''',
        '''
        CREATE TABLE journal_entries (
          $commonColumns,
          user_id TEXT NOT NULL,
          day_key TEXT NOT NULL,
          title TEXT,
          body TEXT NOT NULL,
          mood TEXT,
          tags TEXT NOT NULL DEFAULT '',
          is_pinned INTEGER NOT NULL DEFAULT 0,
          created_local INTEGER NOT NULL,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
        ''',
        '''
        CREATE TABLE reflections (
          $commonColumns,
          user_id TEXT NOT NULL,
          day_key TEXT NOT NULL,
          situation TEXT,
          assumption TEXT,
          evidence_for TEXT,
          alternative TEXT,
          action_step TEXT,
          completed INTEGER NOT NULL DEFAULT 0,
          mood_after TEXT,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
        ''',
        '''
        CREATE TABLE gratitude_entries (
          $commonColumns,
          user_id TEXT NOT NULL,
          day_key TEXT NOT NULL,
          first TEXT NOT NULL,
          second TEXT,
          third TEXT,
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
        ''',
        '''
        CREATE TABLE breathing_sessions (
          $commonColumns,
          user_id TEXT NOT NULL,
          day_key TEXT NOT NULL,
          started_at INTEGER NOT NULL,
          duration_seconds INTEGER NOT NULL,
          completed INTEGER NOT NULL DEFAULT 1,
          pattern TEXT NOT NULL DEFAULT '4-4-6',
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
        ''',

        // ── Love notes ──────────────────────────────────────────────────
        '''
        CREATE TABLE love_notes (
          $commonColumns,
          user_id TEXT NOT NULL,
          text TEXT NOT NULL,
          author TEXT NOT NULL DEFAULT 'Someone who cares',
          minute_of_day INTEGER,
          enabled INTEGER NOT NULL DEFAULT 0,
          is_favorite INTEGER NOT NULL DEFAULT 0,
          last_delivered_at INTEGER,
          delivery_count INTEGER NOT NULL DEFAULT 0,
          source TEXT NOT NULL DEFAULT 'local', -- local|remote
          FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
        )
        ''',

        // ── Notification audit trail + AI chat + sync queue ─────────────
        '''
        CREATE TABLE notification_history (
          $commonColumns,
          user_id TEXT NOT NULL,
          kind TEXT NOT NULL,          -- water|medicine|motivation|love_note|report
          ref_id TEXT,
          title TEXT NOT NULL,
          body TEXT NOT NULL,
          scheduled_for INTEGER,
          delivered_at INTEGER,
          action_taken TEXT,           -- taken|skipped|snoozed|opened|none
          action_at INTEGER
        )
        ''',
        '''
        CREATE TABLE ai_messages (
          $commonColumns,
          user_id TEXT NOT NULL,
          role TEXT NOT NULL,          -- user|assistant
          content TEXT NOT NULL,
          created_local INTEGER NOT NULL,
          flagged INTEGER NOT NULL DEFAULT 0
        )
        ''',
        '''
        CREATE TABLE sync_queue (
          $commonColumns,
          user_id TEXT NOT NULL,
          entity TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          operation TEXT NOT NULL,     -- upsert|delete
          payload TEXT,
          attempts INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          next_attempt_at INTEGER,
          status TEXT NOT NULL DEFAULT 'pending' -- pending|in_flight|failed|done
        )
        ''',
      ];

  /// Indexes: created after tables so the SQL stays readable.
  static List<String> indexStatements() => [
        // Water
        'CREATE INDEX idx_water_logs_day ON water_logs (user_id, day_key)',
        'CREATE INDEX idx_water_logs_time ON water_logs (user_id, logged_at)',
        'CREATE UNIQUE INDEX idx_water_reminders_slot ON water_reminders (user_id, minute_of_day)',
        'CREATE INDEX idx_water_snoozes_status ON water_snoozes (user_id, status, scheduled_for)',
        // Medicine
        'CREATE INDEX idx_med_sched_day ON medicine_schedules (user_id, day_key, minute_of_day)',
        'CREATE INDEX idx_med_logs_day ON medicine_logs (user_id, day_key)',
        'CREATE UNIQUE INDEX idx_med_logs_unique ON medicine_logs (medicine_id, day_key, scheduled_minute)',
        // Mind & soul
        'CREATE INDEX idx_mood_day ON mood_entries (user_id, day_key)',
        'CREATE INDEX idx_journal_day ON journal_entries (user_id, day_key)',
        'CREATE INDEX idx_gratitude_day ON gratitude_entries (user_id, day_key)',
        'CREATE INDEX idx_breathing_day ON breathing_sessions (user_id, day_key)',
        'CREATE INDEX idx_reflections_day ON reflections (user_id, day_key)',
        // Motivation / notes
        'CREATE INDEX idx_motivation_category ON motivational_messages (category)',
        'CREATE INDEX idx_love_notes_enabled ON love_notes (user_id, enabled)',
        // Ops
        'CREATE INDEX idx_notif_history_time ON notification_history (delivered_at)',
        'CREATE INDEX idx_sync_queue_status ON sync_queue (status, next_attempt_at)',
        'CREATE INDEX idx_ai_messages_time ON ai_messages (user_id, created_local)',
      ];

  /// Migration hooks for future versions. Each entry upgrades FROM its key
  /// version TO key+1. Keeping this table from v1 means later releases never
  /// destroy Akasha's history.
  static const Map<int, List<String>> migrations = {
    // 1: [ 'ALTER TABLE water_logs ADD COLUMN ...' ],
  };
}
