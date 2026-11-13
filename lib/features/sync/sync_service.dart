import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../core/database/app_database.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/mind_models.dart';
import '../../data/repositories/love_note_repository.dart';
import '../../data/repositories/medicine_repository.dart';
import '../../data/repositories/mind_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/sync_repository.dart';
import '../../data/repositories/water_repository.dart';
import 'cloud_backend.dart';
import 'conflict_rules.dart';

enum SyncPhase { idle, syncing, offline, error, needsAuth, disabled }

class SyncState {
  const SyncState({
    this.phase = SyncPhase.idle,
    this.pending = 0,
    this.lastSyncAt,
    this.message,
    this.pulledRecords = 0,
    this.pushedRecords = 0,
  });

  final SyncPhase phase;
  final int pending;
  final DateTime? lastSyncAt;
  final String? message;
  final int pulledRecords;
  final int pushedRecords;

  SyncState copyWith({
    SyncPhase? phase,
    int? pending,
    DateTime? lastSyncAt,
    String? message,
    int? pulledRecords,
    int? pushedRecords,
  }) =>
      SyncState(
        phase: phase ?? this.phase,
        pending: pending ?? this.pending,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        message: message ?? this.message,
        pulledRecords: pulledRecords ?? this.pulledRecords,
        pushedRecords: pushedRecords ?? this.pushedRecords,
      );
}

/// Offline-first synchronisation engine.
///
/// Guarantees
/// ----------
/// 1. **Local-first writes.** SQLite is always the source of truth for the UI.
///    Nothing the user does ever waits for the network.
/// 2. **Nothing is lost.** Every mutation is enqueued (see SyncRepository).
///    Failed uploads retry with exponential backoff; the queue survives restarts.
/// 3. **No stale overwrites.** Conflict resolution is per-record
///    last-writer-wins by `updated_at`, but only between comparable versions:
///    if the cloud row is NEWER, the local row is replaced; if the local row is
///    newer, it is re-enqueued. Older data can never clobber newer data in
///    either direction.
/// 4. **Duplicate protection.** Record ids are UUID v4 generated locally, and
///    upserts are idempotent in Firestore (deterministic document ids).
/// 5. **Deletes are tombstones.** `deleted_at` propagates instead of being lost,
///    so a delete on one device is respected on another.
class SyncService {
  SyncService({
    required this.database,
    required this.water,
    required this.medicine,
    required this.mind,
    required this.loveNotes,
    required this.profiles,
    CloudBackend? backend,
  })  : _db = database,
        backend = backend ?? const LocalOnlyBackend();

  final AppDatabase database;
  final AppDatabase _db;
  final WaterRepository water;
  final MedicineRepository medicine;
  final MindRepository mind;
  final LoveNoteRepository loveNotes;
  final ProfileRepository profiles;

  CloudBackend backend;
  late final SyncRepository _queue = SyncRepository(_db);

  /// Entities that participate in sync. Notification history and the AI chat are
  /// deliberately excluded: notification noise is device-specific, and AI
  /// conversations stay on the device.
  static const List<String> syncedEntities = [
    'water_logs',
    'water_reminders',
    'medicines',
    'medicine_logs',
    'mood_entries',
    'journal_entries',
    'gratitude_entries',
    'breathing_sessions',
    'reflections',
    'love_notes',
  ];

  Future<SyncState> currentState() async {
    final pending = await _queue.pendingCount();
    final profile = await profiles.currentProfile();
    final settings = profile == null ? null : await profiles.currentSettings();
    return SyncState(
      phase: !(settings?.syncEnabled ?? false)
          ? SyncPhase.disabled
          : (backend.isAvailable ? SyncPhase.idle : SyncPhase.offline),
      pending: pending,
      lastSyncAt: settings?.lastSyncAt,
    );
  }

  /// Runs one full cycle: push local changes, then pull remote changes.
  /// Safe to call at any time; it never throws to the UI.
  Future<SyncState> syncNow({bool force = false}) async {
    final profile = await profiles.currentProfile();
    if (profile == null) return const SyncState(phase: SyncPhase.disabled);

    final settings = await profiles.currentSettings();
    if (settings == null || !settings.syncEnabled || !settings.syncConsentGiven) {
      return const SyncState(phase: SyncPhase.disabled);
    }
    if (!backend.isAvailable) {
      return const SyncState(
        phase: SyncPhase.offline,
        message: 'Cloud sync is not configured in this build. Everything stays on your phone.',
      );
    }
    if (backend.currentUserId == null) {
      return const SyncState(
        phase: SyncPhase.needsAuth,
        message: 'Sign in to sync your progress across devices.',
      );
    }

    try {
      var pushed = 0;
      final queued = await _queue.pending();
      for (final entry in queued) {
        try {
          if (entry.operation == 'delete') {
            await backend.remove(entity: entry.entity, entityId: entry.entityId);
          } else {
            final rows = await _db.db.query(
              entry.entity,
              where: 'id = ?',
              whereArgs: [entry.entityId],
              limit: 1,
            );
            if (rows.isEmpty) {
              await _queue.markDone(entry.id);
              continue;
            }
            final row = Map<String, Object?>.from(rows.first);
            await backend.upsert(
              entity: entry.entity,
              entityId: entry.entityId,
              data: row,
              updatedAt: AkashaDates.fromMillis(row['updated_at'] as int),
            );
            await _queue.markEntityClean(entry.entity, entry.entityId);
          }
          await _queue.markDone(entry.id);
          pushed++;
        } catch (e) {
          await _queue.markFailed(entry.id, e.toString());
        }
      }

      final pulled = await _pullAndMerge(profile.id);
      final now = DateTime.now();
      await profiles.saveSettings(settings.copyWith(lastSyncAt: now));

      return SyncState(
        phase: SyncPhase.idle,
        pending: await _queue.pendingCount(),
        lastSyncAt: now,
        pushedRecords: pushed,
        pulledRecords: pulled,
        message: 'Everything is in sync.',
      );
    } catch (e) {
      debugPrint('AKASHA sync failed: $e');
      return SyncState(
        phase: SyncPhase.error,
        pending: await _queue.pendingCount(),
        message: 'Sync paused. Your changes are safe on this phone.',
      );
    }
  }

  /// Merges remote rows into local storage using updatedAt last-writer-wins.
  ///
  /// A Firestore document is *not* a SQLite row: it can carry extra fields
  /// (`server_updated_at` is a Firestore Timestamp, which the local engine
  /// cannot bind), and it can be missing columns the local table requires
  /// (`created_at`, `start_day`, …). Blindingly spreading `{...remoteRow}` into
  /// an INSERT is how a pull used to raise `NOT NULL constraint failed` and
  /// abort the whole sync cycle, so every remote row is normalised against the
  /// real table shape first — see [_LocalRowShape].
  Future<int> _pullAndMerge(String userId) async {
    final settings = await profiles.currentSettings();
    final remote = await backend.pull(since: settings?.lastSyncAt);
    var merged = 0;

    for (final entry in remote.entries) {
      final table = entry.key;
      if (!syncedEntities.contains(table)) continue;
      final shape = await _shapeOf(table);

      for (final remoteRow in entry.value) {
        final id = remoteRow['id'] as String?;
        if (id == null) continue;
        final remoteUpdatedAt = (remoteRow['updated_at'] as num?)?.toInt() ?? 0;

        final localRows = await _db.db
            .query(table, where: 'id = ?', whereArgs: [id], limit: 1);
        final localRow = localRows.isEmpty ? null : localRows.first;
        final localUpdatedAt =
            (localRow?['updated_at'] as num?)?.toInt() ?? 0;
        final localDirty = (localRow?['dirty'] as num?)?.toInt() == 1;

        // Newest wins (see conflict_rules.dart, unit-tested). A dirty local row
        // that is at least as new as the cloud row is kept and will be pushed
        // on the next cycle.
        final replaceLocal = localRow == null ||
            SyncConflictRules.shouldReplaceLocal(
              localUpdatedAt: localUpdatedAt,
              localDirty: localDirty,
              remoteUpdatedAt: remoteUpdatedAt,
            );
        if (!replaceLocal) {
          if (SyncConflictRules.shouldRequeueLocal(
            localUpdatedAt: localUpdatedAt,
            localDirty: localDirty,
            remoteUpdatedAt: remoteUpdatedAt,
          )) {
            await _queue.enqueue(
              userId: userId,
              entity: table,
              entityId: id,
              operation: localRow?['deleted_at'] != null ? 'delete' : 'upsert',
            );
          }
          continue;
        }

        final row = shape.merge(
          remoteRow,
          localRow: localRow,
          userId: userId,
          now: DateTime.now(),
        );
        if (row != null && remoteUpdatedAt == 0) {
          // A cloud document without `updated_at` would otherwise defeat
          // last-writer-wins: it could never replace anything, so it is stamped
          // with "now" and treated as the newest version.
          row['updated_at'] = DateTime.now().millisecondsSinceEpoch;
        }
        if (row == null) {
          // The cloud row is missing fields this table requires and there is no
          // local row to fill them from. Skipping is honest — inventing values
          // would write a record the user never created — but it must be
          // visible in the logs, never silent.
          debugPrint('AKASHA sync: skipped $table/$id — remote row is missing '
              'required columns ${shape.missingRequired(remoteRow).join(', ')}');
          continue;
        }

        // Upsert, not REPLACE: a merge must not reset a row's `created_at`
        // when the cloud document did not carry one. `markDirty: false` keeps
        // the remote `updated_at` and `dirty = 0` — a pulled row is in sync and
        // must not be pushed straight back.
        await AppDatabase.upsert(_db.db, table, row, markDirty: false);
        merged++;
      }
    }
    return merged;
  }

  final Map<String, _LocalRowShape> _shapeCache = {};

  Future<_LocalRowShape> _shapeOf(String table) async {
    final cached = _shapeCache[table];
    if (cached != null) return cached;
    final columns = await _db.db.rawQuery('PRAGMA table_info($table)');
    final shape = _LocalRowShape.fromPragma(columns);
    _shapeCache[table] = shape;
    return shape;
  }

  Future<void> enableSync({required bool enable}) async {
    await profiles.mutateSettings(
      (s) => s.copyWith(syncEnabled: enable, syncConsentGiven: enable || s.syncConsentGiven),
    );
    if (enable) {
      final profile = await profiles.currentProfile();
      if (profile != null) {
        await _queue.backfillFromDirtyTables(userId: profile.id);
      }
    }
  }

  Future<CloudAuthResult> signIn(String email, String password) =>
      backend.signInWithEmail(email, password);

  Future<CloudAuthResult> signUp(String email, String password) =>
      backend.signUpWithEmail(email, password);

  Future<void> signOut() => backend.signOut();

  /// Wipes cloud data and local mirror. Requires an explicit confirmation in
  /// the UI before it is ever called.
  Future<void> deleteCloudAccount() async {
    await backend.deleteAccount();
    await _queue.clear();
    await profiles.mutateSettings((s) => s.copyWith(syncEnabled: false));
  }

  /// Enqueues a local mutation. Called by repositories through the controller
  /// layer after each write that should be backed up.
  Future<void> trackChange({
    required String entity,
    required String entityId,
    required String userId,
    bool delete = false,
  }) =>
      _queue.enqueue(
        userId: userId,
        entity: entity,
        entityId: entityId,
        operation: delete ? 'delete' : 'upsert',
      );

  Future<int> pendingCount() => _queue.pendingCount();

  /// Convenience for the reports screen: are AI features usable right now?
  bool get cloudConfigured => backend.isAvailable;

  /// Local mirror of the moral of the story: never silently drop a user's data
  /// because the cloud refused it.
  Future<List<Map<String, Object?>>> failedEntries() async {
    final rows = await _db.db.query(
      'sync_queue',
      where: 'status = ?',
      whereArgs: ['failed'],
      orderBy: 'updated_at DESC',
      limit: 50,
    );
    return rows.cast<Map<String, Object?>>();
  }

  /// Deep-links into the mood history so a synced mood shows up immediately.
  Future<List<MoodEntry>> recentMoods(String userId) => mind.moodRange(
        userId,
        DateTime.now().subtract(const Duration(days: 7)),
        DateTime.now(),
      );
}

/// The real column shape of one local table, used to turn a Firestore document
/// into a row SQLite will accept.
class _LocalRowShape {
  _LocalRowShape(this.columns, this.required);

  /// Every column that exists locally, in declaration order.
  final List<String> columns;

  /// Columns that are `NOT NULL` with no DEFAULT and are not the primary key.
  final Set<String> required;

  factory _LocalRowShape.fromPragma(List<Map<String, Object?>> pragma) {
    final columns = <String>[];
    final required = <String>{};
    for (final c in pragma) {
      final name = c['name'] as String;
      columns.add(name);
      final notNull = (c['notnull'] as num?)?.toInt() == 1;
      final hasDefault = c['dflt_value'] != null;
      final isPk = (c['pk'] as num?)?.toInt() == 1;
      if (notNull && !hasDefault && !isPk) required.add(name);
    }
    return _LocalRowShape(columns, required);
  }

  Iterable<String> missingRequired(Map<String, Object?> remoteRow) =>
      required.where((c) => remoteRow[c] == null);

  /// Builds a local row from [remoteRow], keeping only real columns, coercing
  /// values to types sqflite can bind, and filling `user_id`, `created_at` and
  /// `dirty` the way a locally-originated row would be.
  ///
  /// Returns null when the result would still violate a NOT NULL constraint.
  Map<String, Object?>? merge(
    Map<String, Object?> remoteRow, {
    required Map<String, Object?>? localRow,
    required String userId,
    required DateTime now,
  }) {
    final row = <String, Object?>{};
    for (final column in columns) {
      if (localRow != null) row[column] = localRow[column];
    }
    for (final column in columns) {
      if (!remoteRow.containsKey(column)) continue;
      final coerced = _coerce(remoteRow[column]);
      if (coerced == _unsupported) continue;
      row[column] = coerced;
    }
    row['id'] = remoteRow['id'];
    if (columns.contains('user_id')) row['user_id'] = userId;
    row['created_at'] ??= now.millisecondsSinceEpoch;
    row['updated_at'] = (remoteRow['updated_at'] as num?)?.toInt() ??
        now.millisecondsSinceEpoch;
    // A pulled row is by definition in sync; the local mirror must not claim
    // pending changes or it would be re-pushed forever.
    row['dirty'] = 0;

    for (final column in required) {
      if (row[column] == null) return null;
    }
    return row;
  }

  /// Firestore values that cannot be bound to SQLite (Timestamps, GeoPoints,
  /// nested maps) are dropped rather than written as `Instance of …`.
  static const Object _unsupported = Object();

  static Object? _coerce(Object? value) => switch (value) {
        null || bool() || num() || String() => value,
        DateTime() => (value).millisecondsSinceEpoch,
        _ => _unsupported,
      };
}
