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

  Future<List<WaterReminder>> reminders(String userId,
      {Transaction? txn}) async {
    final rows = await (txn ?? _db.db).query(
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
  /// Replaces the default slots atomically. Custom slots (is_default_slot = 0)
  /// are preserved so a user who added "3:30 PM — after gym" does not lose it
  /// when she tweaks the interval.
  ///
  /// [txn] is the caller's transaction when this runs inside a larger unit of
  /// work (first-run seeding, onboarding). Passing it matters: opening a second
  /// transaction here is exactly what produced
  /// "cannot start a transaction within a transaction".
  Future<List<WaterReminder>> generateDefaultSchedule({
    required String userId,
    required int startMinute,
    required int endMinute,
    required int intervalMinutes,
    required int amountMl,
    Transaction? txn,
  }) async {
    final slots = WaterScheduleEngine.generate(
      startMinute: startMinute,
      endMinute: endMinute,
      intervalMinutes: intervalMinutes,
    );

    return _db.write(txn, (local) async {
      final existingCustom = await local.query(
        'water_reminders',
        where: 'user_id = ? AND is_default_slot = 0 AND deleted_at IS NULL',
        whereArgs: [userId],
      );
      final customMinutes = existingCustom
          .map((r) => r['minute_of_day'] as int)
          .toSet();

      // Soft-delete previous default slots (kept for history/sync integrity),
      // parking their minute so `idx_water_reminders_slot`
      // (UNIQUE user_id + minute_of_day) is free for the rebuilt rows.
      final now = DateTime.now().millisecondsSinceEpoch;
      final previous = await local.query(
        'water_reminders',
        columns: ['id'],
        where: 'user_id = ? AND is_default_slot = 1 AND deleted_at IS NULL',
        whereArgs: [userId],
      );
      for (final row in previous) {
        await _parkTombstoneMinute(local, row['id'] as String);
      }
      await local.update(
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
        // Deterministic ids make a re-run idempotent. An upsert (not REPLACE,
        // not ignore) is required: the previous default slots were just
        // soft-deleted above and they hold *these same ids*, so the rebuilt row
        // must clear `deleted_at` and keep its original `created_at` rather
        // than being skipped or deleted-and-recreated.
        await AppDatabase.upsert(local, 'water_reminders', reminder.toRow());
        created.add(reminder);
      }
      return created;
    });
  }

  /// Creates or edits one reminder slot.
  ///
  /// The clash resolution and the write are one transaction so two slots can
  /// never occupy the same minute, and the insert itself is an
  /// `ON CONFLICT(id) DO UPDATE`-style merge rather than a REPLACE: on edit the
  /// existing row's `created_at` is kept (only `updated_at` moves), which is
  /// what "preserve created_at when updating" requires.
  Future<void> upsertReminder(WaterReminder reminder,
          {Transaction? txn}) =>
      _db.write(txn, (local) async {
        // Guard against duplicates: if another active slot already sits on this
        // minute, keep the newest and soft-delete the older one.
        final clash = await local.query(
          'water_reminders',
          where:
              'user_id = ? AND minute_of_day = ? AND id != ? AND deleted_at IS NULL',
          whereArgs: [reminder.userId, reminder.minuteOfDay, reminder.id],
        );
        for (final row in clash) {
          await _parkTombstoneMinute(local, row['id'] as String);
          await local.update(
            'water_reminders',
            {
              'deleted_at': DateTime.now().millisecondsSinceEpoch,
              'updated_at': DateTime.now().millisecondsSinceEpoch,
              'dirty': 1,
            },
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }

        // Insert or merge, never REPLACE: an edit keeps the row's original
        // `created_at`, and re-saving a soft-deleted slot brings it back with
        // its history intact.
        await AppDatabase.upsert(local, 'water_reminders', reminder.toRow());
      });

  Future<void> setReminderEnabled(String id, bool enabled) async {
    await _db.db.update(
      'water_reminders',
      AppDatabase.touch({'enabled': enabled ? 1 : 0}),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> softDeleteReminder(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // `idx_water_reminders_slot` is UNIQUE(user_id, minute_of_day) and does not
    // exclude soft-deleted rows. A tombstone left sitting on 09:00 would make
    // it impossible to ever create a new 09:00 slot, so the tombstone parks its
    // minute outside the valid 0..1439 range. `deleted_at` is what readers
    // filter on; the parked value only keeps the index honest.
    await _db.transaction((txn) async {
      await _parkTombstoneMinute(txn, id);
      await txn.update(
        'water_reminders',
        {'deleted_at': now, 'updated_at': now, 'dirty': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// A soft-deleted one-off reminder must not keep its slot reserved.
  ///
  /// Deterministic default slot ids are reused when the schedule is rebuilt;
  /// a tombstone on the same (user_id, minute_of_day) would block that insert.
  static const int _tombstoneMinuteBase = 100000;

  Future<void> _parkTombstoneMinute(Transaction txn, String id) async {
    await txn.rawUpdate(
      'UPDATE water_reminders '
      'SET minute_of_day = ? + rowid '
      'WHERE id = ? AND deleted_at IS NULL',
      [_tombstoneMinuteBase, id],
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
      AppDatabase.touch({'amount_ml': amountMl}),
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
      AppDatabase.touch({
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
      AppDatabase.touch({'status': SnoozeStatus.cancelled.name}),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearExpiredSnoozes(String userId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.update(
      'water_snoozes',
      AppDatabase.touch({'status': SnoozeStatus.cancelled.name}),
      where: 'user_id = ? AND status = ? AND scheduled_for < ?',
      whereArgs: [userId, SnoozeStatus.pending.name, now],
    );
  }
}
