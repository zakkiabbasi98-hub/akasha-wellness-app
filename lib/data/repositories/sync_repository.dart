import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/database/app_database.dart';
import '../../core/utils/id.dart';

/// The pending-upload queue.
///
/// Every local mutation appends one row here (inside the same logical unit of
/// work as the mutation itself). The sync engine drains it when connectivity and
/// auth allow. Rows are only removed after the cloud acknowledges them, so a
/// dead battery or a crash mid-upload cannot lose a change.
class SyncQueueEntry {
  const SyncQueueEntry({
    required this.id,
    required this.userId,
    required this.entity,
    required this.entityId,
    required this.operation,
    required this.status,
    required this.attempts,
    this.payload,
    this.lastError,
    this.nextAttemptAt,
  });

  final String id;
  final String userId;
  final String entity;
  final String entityId;
  final String operation;
  final String status;
  final int attempts;
  final Map<String, Object?>? payload;
  final String? lastError;
  final DateTime? nextAttemptAt;

  factory SyncQueueEntry.fromRow(Map<String, Object?> r) => SyncQueueEntry(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        entity: r['entity'] as String,
        entityId: r['entity_id'] as String,
        operation: r['operation'] as String,
        status: r['status'] as String,
        attempts: r['attempts'] as int? ?? 0,
        payload: r['payload'] == null
            ? null
            : jsonDecode(r['payload'] as String) as Map<String, Object?>,
        lastError: r['last_error'] as String?,
        nextAttemptAt: r['next_attempt_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['next_attempt_at'] as int),
      );
}

class SyncRepository {
  SyncRepository(this._db);
  final AppDatabase _db;

  Future<void> enqueue({
    required String userId,
    required String entity,
    required String entityId,
    required String operation,
    Map<String, Object?>? payload,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // Collapse repeated edits of the same record into one pending operation:
    // the queue always carries the newest state, never a backlog of stale ones.
    final existing = await _db.db.query(
      'sync_queue',
      where: 'entity_id = ? AND entity = ? AND status = ?',
      whereArgs: [entityId, entity, 'pending'],
      limit: 1,
    );

    final row = {
      'id': existing.isNotEmpty ? existing.first['id'] as String : Ids.newId(),
      'user_id': userId,
      'entity': entity,
      'entity_id': entityId,
      'operation': operation,
      'payload': payload == null ? null : jsonEncode(payload),
      'attempts': existing.isNotEmpty ? existing.first['attempts'] : 0,
      'last_error': null,
      'next_attempt_at': now,
      'status': 'pending',
      'created_at': existing.isNotEmpty ? existing.first['created_at'] : now,
      'updated_at': now,
      'deleted_at': null,
      'dirty': 1,
    };
    // The row above already carries the existing `created_at` when it is an
    // update, so a plain insert-or-replace is safe here — but ABORT semantics
    // would strand the queue, so REPLACE stays deliberate and is documented.
    await _db.db.insert('sync_queue', row,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<SyncQueueEntry>> pending({int limit = 100}) async {
    final rows = await _db.db.query(
      'sync_queue',
      where: 'status = ? OR (status = ? AND next_attempt_at <= ?)',
      whereArgs: ['pending', 'failed', DateTime.now().millisecondsSinceEpoch],
      orderBy: 'created_at ASC',
      limit: limit,
    );
    return rows.map(SyncQueueEntry.fromRow).toList();
  }

  Future<int> pendingCount() async {
    final rows = await _db.db.rawQuery(
        'SELECT COUNT(*) AS c FROM sync_queue WHERE status IN (?, ?)', ['pending', 'failed']);
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  Future<void> markDone(String id) async {
    await _db.db.delete('sync_queue', where: 'id = ?', whereArgs: [id]);
  }

  /// Exponential backoff: 1m, 5m, 15m, 1h, 6h — then keep trying every 6h.
  Future<void> markFailed(String id, String error) async {
    final rows = await _db.db.query('sync_queue', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final attempts = (rows.first['attempts'] as int? ?? 0) + 1;
    final delays = [
      const Duration(minutes: 1),
      const Duration(minutes: 5),
      const Duration(minutes: 15),
      const Duration(hours: 1),
      const Duration(hours: 6),
    ];
    final delay = delays[(attempts - 1).clamp(0, delays.length - 1)];
    await _db.db.update(
      'sync_queue',
      {
        'attempts': attempts,
        'last_error': error,
        'status': attempts >= 6 ? 'failed' : 'pending',
        'next_attempt_at': DateTime.now().add(delay).millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clear() async {
    await _db.db.delete('sync_queue');
  }

  /// Marks a locally stored record as synced (dirty = 0).
  Future<void> markEntityClean(String table, String id) async {
    await _db.db.update(
      table,
      {'dirty': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Finds local rows that were never enqueued (e.g. created before sync was
  /// enabled). Called when the user turns sync on, so nothing is left behind.
  Future<int> backfillFromDirtyTables({required String userId}) async {
    var count = 0;
    const tables = [
      'water_logs',
      'water_reminders',
      'medicines',
      'medicine_logs',
      'mood_entries',
      'journal_entries',
      'gratitude_entries',
      'breathing_sessions',
      'love_notes',
      'reflections',
    ];
    for (final table in tables) {
      final rows = await _db.db.query(
        table,
        where: 'dirty = 1 AND deleted_at IS NULL AND user_id = ?',
        whereArgs: [userId],
        limit: 500,
      );
      for (final row in rows) {
        await enqueue(
          userId: userId,
          entity: table,
          entityId: row['id'] as String,
          operation: 'upsert',
        );
        count++;
      }
    }
    return count;
  }
}
