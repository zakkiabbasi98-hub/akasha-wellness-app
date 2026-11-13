import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, Transaction;

import '../../core/database/app_database.dart';
import '../../core/services/water_schedule_engine.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/id.dart';
import '../models/water_models.dart';

/// All water reads/writes. The single place that knows the water SQL.
class WaterRepository {
  WaterRepository(this._db);
  final AppDatabase _db;

  // ── Reminder slots ──────────────────────────────────────────────────────

  Future<List<WaterReminder>> reminders(String userId) async {
    final rows = await _db.db.query(
      'water_reminders',
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
      orderBy: 'minute_of_day ASC',
    );
    return rows.map(WaterReminder.fromRow).toList();
  }

  Future<List<WaterReminder>> enabledReminders(String userId) async {
    final all = await reminders(userId);
    return all.where((r) => r.enabled).toList();
  }

  /// Regenerates the schedule from a window + interval.
  ///
  /// Replaces default slots atomically. Custom slots (is_default_slot = 0) are
  /// preserved so a user who added "3:30 PM — after gym" does not lose it when
  /// she tweaks the interval. A unique index on (user_id, minute_of_day)
  /// guarantees no duplicate slot can ever exist.
  Future<List<WaterReminder>> generateDefaultSchedule({
    required String userId,
    required int startMinute,
    required int endMinute,
    required int intervalMinutes,
    required int amountMl,
  }) async {
    final slots = WaterScheduleEngine.generate(
      startMinute: startMinute,
      endMinute: endMinute,
      intervalMinutes: intervalMinutes,
    );

    return _db.transaction((txn) async {
      final existingCustom = await txn.query(
        'water_reminders',
        where: 'user_id = ? AND is_default_slot = 0 AND deleted_at IS NULL',
        whereArgs: [userId],
      );
      final customMinutes = existingCustom
          .map((r) => r['minute_of_day'] as int)
          .toSet();

      // Soft-delete previous default slots (kept for history/sync integrity).
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.update(
        'water_reminders',
        {'deleted_at': now, 'updated_at': now, 'dirty': 1},
        where: 'user_id = ? AND is_default_slot = 1 AND deleted_at IS NULL',
        whereArgs: [userId],
      );

      final created = <WaterReminder>[];
      for (var i = 0; i < slots.length; i++) {
        final slot = slots[i];
        if (customMinutes.contains(slot.minuteOfDay)) continue; // no duplicates
        final reminder = WaterReminder(
          id: Ids.slotId('water', '$userId:${slot.minuteOfDay}'),
          userId: userId,
          minuteOfDay: slot.minuteOfDay,
          label: slot.label,
          amountMl: amountMl,
          isDefaultSlot: true,
          sortOrder: i,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await txn.insert('water_reminders', reminder.toRow(),
            conflictAlgorithm: ConflictAlgorithm.replace);
        created.add(reminder);
      }
      return created;
    });
  }

  Future<void> upsertReminder(WaterReminder reminder) async {
    // Guard against duplicates: if another active slot already sits on this
    // minute, keep the newest and soft-delete the older one.
    final clash = await _db.db.query(
      'water_reminders',
      where: 'user_id = ? AND minute_of_day = ? AND id != ? AND deleted_at IS NULL',
      whereArgs: [reminder.userId, reminder.minuteOfDay, reminder.id],
    );
    for (final row in clash) {
      final now = DateTime.now().millisecondsSinceEpoch;
      await _db.db.update(
        'water_reminders',
        {'deleted_at': now, 'updated_at': now, 'dirty': 1},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    await _db.db.insert('water_reminders', reminder.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setReminderEnabled(String id, bool enabled) async {
    await _db.db.update(
      'water_reminders',
      AppDatabase.stamp({'enabled': enabled ? 1 : 0}),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDeleteReminder(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.update(
      'water_reminders',
      {'deleted_at': now, 'updated_at': now, 'dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ── Logs ────────────────────────────────────────────────────────────────

  Future<WaterLog> addLog({
    required String userId,
    required int amountMl,
    required WaterLogSource source,
    DateTime? at,
    int? reminderMinute,
    String? glassSize,
    String? note,
  }) async {
    final when = at ?? DateTime.now();
    final log = WaterLog(
      id: Ids.newId(),
      userId: userId,
      dayKey: AkashaDates.key(when),
      loggedAt: when,
      amountMl: amountMl,
      source: source,
      reminderMinute: reminderMinute,
      glassSize: glassSize,
      note: note,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.db.insert('water_logs', log.toRow());
    return log;
  }

  /// Inserts a water log **inside an existing transaction**.
  ///
  /// Used by the notification action executor so the millilitres, the dedupe
  /// marker and the history row commit atomically. [id] is deterministic for
  /// notification-sourced logs, which makes a duplicated delivery a no-op
  /// instead of a double count.
  Future<void> insertLogInTxn(
    Transaction txn, {
    required String id,
    required String userId,
    required int amountMl,
    required WaterLogSource source,
    required DateTime at,
    int? reminderMinute,
    String? glassSize,
    String? note,
  }) async {
    final log = WaterLog(
      id: id,
      userId: userId,
      dayKey: AkashaDates.key(at),
      loggedAt: at,
      amountMl: amountMl,
      source: source,
      reminderMinute: reminderMinute,
      glassSize: glassSize,
      note: note,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await txn.insert(
      'water_logs',
      log.toRow(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> updateLogAmount(String id, int amountMl) async {
    await _db.db.update(
      'water_logs',
      AppDatabase.stamp({'amount_ml': amountMl}),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteLog(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.update(
      'water_logs',
      {'deleted_at': now, 'updated_at': now, 'dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<WaterLog>> logsForDay(String userId, DateTime day) async {
    final rows = await _db.db.query(
      'water_logs',
      where: 'user_id = ? AND day_key = ? AND deleted_at IS NULL',
      whereArgs: [userId, AkashaDates.key(day)],
      orderBy: 'logged_at ASC',
    );
    return rows.map(WaterLog.fromRow).toList();
  }

  Future<int> totalForDay(String userId, DateTime day) async {
    final rows = await _db.db.rawQuery(
      'SELECT COALESCE(SUM(amount_ml), 0) AS total FROM water_logs '
      'WHERE user_id = ? AND day_key = ? AND deleted_at IS NULL',
      [userId, AkashaDates.key(day)],
    );
    return (rows.first['total'] as num?)?.toInt() ?? 0;
  }

  Future<DailyWaterSummary> summaryForDay(
    String userId,
    DateTime day, {
    required int targetMl,
    int glassSizeMl = 250,
  }) async {
    final logs = await logsForDay(userId, day);
    final total = logs.fold<int>(0, (sum, l) => sum + l.amountMl);
    return DailyWaterSummary(
      dayKey: AkashaDates.key(day),
      totalMl: total,
      glassCount: glassSizeMl <= 0 ? 0 : (total / glassSizeMl).round(),
      targetMl: targetMl,
      entries: logs,
    );
  }

  /// Totals for a date range — one query, used by charts and reports.
  Future<Map<String, int>> totalsByDay(
    String userId,
    DateTime from,
    DateTime to,
  ) async {
    final rows = await _db.db.rawQuery(
      'SELECT day_key, SUM(amount_ml) AS total FROM water_logs '
      'WHERE user_id = ? AND day_key BETWEEN ? AND ? AND deleted_at IS NULL '
      'GROUP BY day_key',
      [userId, AkashaDates.key(from), AkashaDates.key(to)],
    );
    return {
      for (final r in rows) r['day_key'] as String: (r['total'] as num?)?.toInt() ?? 0,
    };
  }

  Future<List<WaterTrendPoint>> trend(
    String userId,
    DateTime from,
    DateTime to, {
    required int targetMl,
  }) async {
    final totals = await totalsByDay(userId, from, to);
    final days = AkashaDates.daysBetween(from, to) + 1;
    return List.generate(days, (i) {
      final date = AkashaDates.dayOnly(from).add(Duration(days: i));
      return WaterTrendPoint(
        date: date,
        totalMl: totals[AkashaDates.key(date)] ?? 0,
        targetMl: targetMl,
      );
    });
  }

  Future<int> streakDays(String userId, {required int targetMl}) async {
    // Walk backwards until a day misses the target. Excludes today (still in
    // progress) so an unfinished day never breaks her streak.
    var streak = 0;
    var cursor = AkashaDates.today().subtract(const Duration(days: 1));
    for (var i = 0; i < 400; i++) {
      final total = await totalForDay(userId, cursor);
      if (total >= targetMl) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    return streak;
  }

  // ── Snoozes ─────────────────────────────────────────────────────────────

  Future<WaterSnooze> createSnooze({
    required String userId,
    required int reminderMinute,
    required DateTime scheduledFor,
  }) async {
    final snooze = WaterSnooze(
      id: Ids.newId(),
      userId: userId,
      reminderMinute: reminderMinute,
      scheduledFor: scheduledFor,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.db.insert('water_snoozes', snooze.toRow());
    return snooze;
  }

  Future<List<WaterSnooze>> pendingSnoozes(String userId) async {
    final rows = await _db.db.query(
      'water_snoozes',
      where: 'user_id = ? AND status = ? AND deleted_at IS NULL',
      whereArgs: [userId, SnoozeStatus.pending.name],
      orderBy: 'scheduled_for ASC',
    );
    return rows.map(WaterSnooze.fromRow).toList();
  }

  Future<void> markSnoozeFired(String id) async {
    await _db.db.update(
      'water_snoozes',
      AppDatabase.stamp({
        'status': SnoozeStatus.fired.name,
        'fired_at': DateTime.now().millisecondsSinceEpoch,
      }),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> cancelSnooze(String id) async {
    await _db.db.update(
      'water_snoozes',
      AppDatabase.stamp({'status': SnoozeStatus.cancelled.name}),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearExpiredSnoozes(String userId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.update(
      'water_snoozes',
      AppDatabase.stamp({'status': SnoozeStatus.cancelled.name}),
      where: 'user_id = ? AND status = ? AND scheduled_for < ?',
      whereArgs: [userId, SnoozeStatus.pending.name, now],
    );
  }
}
