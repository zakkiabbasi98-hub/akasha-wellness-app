import '../../core/database/app_database.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/id.dart';
import '../models/mind_models.dart';

/// Audit trail of every reminder the app raised and what happened to it.
///
/// This is what makes the daily report honest about "reminders completed" vs
/// "reminders skipped", and gives Akasha a place to see what she missed
/// without being nagged.
class NotificationHistoryRepository {
  NotificationHistoryRepository(this._db);

  final AppDatabase _db;

  Future<NotificationRecord> record({
    required String userId,
    required String kind,
    required String title,
    required String body,
    String? refId,
    DateTime? scheduledFor,
    DateTime? deliveredAt,
  }) async {
    final now = DateTime.now();
    final record = NotificationRecord(
      id: Ids.newId(),
      userId: userId,
      kind: kind,
      refId: refId,
      title: title,
      body: body,
      scheduledFor: scheduledFor,
      deliveredAt: deliveredAt ?? now,
      createdAt: now,
      updatedAt: now,
    );
    await _db.db.insert('notification_history', record.toRow());
    return record;
  }

  Future<void> recordAction({
    required String id,
    required String action,
  }) async {
    await _db.db.update(
      'notification_history',
      {
        'action_taken': action,
        'action_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Most recent record of a kind for a reference (e.g. today's water
  /// reminder), used so a notification action can find its own row.
  Future<NotificationRecord?> latestFor({
    required String userId,
    required String kind,
    String? refId,
    DateTime? onDay,
  }) async {
    final where = <String>['user_id = ?', 'kind = ?', 'deleted_at IS NULL'];
    final args = <Object?>[userId, kind];
    if (refId != null) {
      where.add('ref_id = ?');
      args.add(refId);
    }
    if (onDay != null) {
      where.add('delivered_at BETWEEN ? AND ?');
      args.add(AkashaDates.millis(AkashaDates.startOfDay(onDay)));
      args.add(AkashaDates.millis(AkashaDates.endOfDay(onDay)));
    }
    final rows = await _db.db.query(
      'notification_history',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'delivered_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : NotificationRecord.fromRow(rows.first);
  }

  Future<List<NotificationRecord>> recent(String userId, {int limit = 100}) async {
    final rows = await _db.db.query(
      'notification_history',
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
      orderBy: 'delivered_at DESC',
      limit: limit,
    );
    return rows.map(NotificationRecord.fromRow).toList();
  }

  Future<Map<String, int>> actionCountsForDay(String userId, DateTime day) async {
    final rows = await _db.db.rawQuery(
      'SELECT kind, action_taken, COUNT(*) AS c FROM notification_history '
      'WHERE user_id = ? AND delivered_at BETWEEN ? AND ? AND deleted_at IS NULL '
      'GROUP BY kind, action_taken',
      [
        userId,
        AkashaDates.millis(AkashaDates.startOfDay(day)),
        AkashaDates.millis(AkashaDates.endOfDay(day)),
      ],
    );
    return {
      for (final r in rows)
        '${r['kind']}:${r['action_taken'] ?? 'none'}': (r['c'] as num?)?.toInt() ?? 0,
    };
  }

  /// Keeps the table lean; runs on app start.
  Future<void> prune({int keepDays = 90}) async {
    final cutoff = DateTime.now().subtract(Duration(days: keepDays));
    await _db.db.delete(
      'notification_history',
      where: 'delivered_at IS NOT NULL AND delivered_at < ?',
      whereArgs: [AkashaDates.millis(cutoff)],
    );
  }
}
