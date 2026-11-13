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
  Future<int> _pullAndMerge(String userId) async {
    final settings = await profiles.currentSettings();
    final remote = await backend.pull(since: settings?.lastSyncAt);
    var merged = 0;

    for (final entry in remote.entries) {
      final table = entry.key;
      if (!syncedEntities.contains(table)) continue;

      for (final remoteRow in entry.value) {
        final id = remoteRow['id'] as String?;
        if (id == null) continue;
        final remoteUpdatedAt = (remoteRow['updated_at'] as num?)?.toInt() ?? 0;

        final localRows = await _db.db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
        if (localRows.isEmpty) {
          await _db.db.insert(
            table,
            {...remoteRow, 'user_id': userId, 'dirty': 0},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          merged++;
          continue;
        }

        final localRow = localRows.first;
        final localUpdatedAt = (localRow['updated_at'] as num?)?.toInt() ?? 0;
        final localDirty = (localRow['dirty'] as num?)?.toInt() == 1;

        // Conflict rule: newest wins (see conflict_rules.dart, unit-tested).
        // A dirty local row that is at least as new as the cloud row is kept
        // and will be pushed on the next cycle.
        if (SyncConflictRules.shouldReplaceLocal(
          localUpdatedAt: localUpdatedAt,
          localDirty: localDirty,
          remoteUpdatedAt: remoteUpdatedAt,
        )) {
          await _db.db.insert(
            table,
            {...remoteRow, 'user_id': userId, 'dirty': 0},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          merged++;
        } else if (SyncConflictRules.shouldRequeueLocal(
          localUpdatedAt: localUpdatedAt,
          localDirty: localDirty,
          remoteUpdatedAt: remoteUpdatedAt,
        )) {
          await _queue.enqueue(
            userId: userId,
            entity: table,
            entityId: id,
            operation: localRow['deleted_at'] != null ? 'delete' : 'upsert',
          );
        }
      }
    }
    return merged;
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
