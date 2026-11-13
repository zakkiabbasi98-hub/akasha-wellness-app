import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, Transaction;

import '../../core/database/app_database.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/id.dart';
import '../models/medicine_models.dart';

/// Medicines, their per-day schedule rows, and every dose response.
///
/// Invariant enforced here: a dose is never marked `taken` unless the user
/// tapped "I took it". Unanswered doses become `missed` only after their day
/// has fully passed ([reconcileMissedDoses]).
class MedicineRepository {
  MedicineRepository(this._db);
  final AppDatabase _db;

  // ── Medicines ───────────────────────────────────────────────────────────

  Future<List<Medicine>> all(String userId, {bool includeDisabled = true}) async {
    final rows = await _db.db.query(
      'medicines',
      where: includeDisabled
          ? 'user_id = ? AND deleted_at IS NULL'
          : 'user_id = ? AND deleted_at IS NULL AND enabled = 1',
      whereArgs: [userId],
      orderBy: 'start_day DESC, name ASC',
    );
    return rows.map(Medicine.fromRow).toList();
  }

  Future<Medicine?> byId(String id) async {
    final rows = await _db.db.query('medicines',
        where: 'id = ? AND deleted_at IS NULL', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Medicine.fromRow(rows.first);
  }

  /// Creates or edits a medicine and (re)materialises its schedule rows in one
  /// transaction, so a medicine can never exist without the doses that make it
  /// actionable.
  ///
  /// [txn] is the caller's transaction when this runs inside a larger unit of
  /// work (onboarding). Passing it is required — a nested `BEGIN` is what
  /// raises "cannot start a transaction within a transaction".
  Future<Medicine> save(Medicine medicine, {Transaction? txn}) =>
      _db.write(txn, (local) async {
        final existing = await local.query(
          'medicines',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [medicine.id],
          limit: 1,
        );
        if (existing.isEmpty) {
          await local.insert('medicines', medicine.toRow());
        } else {
          // Edit path: an update must not rewrite `created_at`.
          await local.update('medicines', AppDatabase.touch(medicine.toRow()),
              where: 'id = ?', whereArgs: [medicine.id]);
        }
        await regenerateSchedules(medicine, days: 14, txn: local);
        return medicine;
      });

  Future<void> setEnabled(String id, bool enabled) async {
    await _db.db.update(
      'medicines',
      AppDatabase.touch({'enabled': enabled ? 1 : 0}),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Soft delete keeps history intact (and the sync tombstone honest) while
  /// removing future schedule rows so no notification fires afterwards.
  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.update(
      'medicines',
      {'deleted_at': now, 'updated_at': now, 'dirty': 1, 'enabled': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _db.db.update(
      'medicine_schedules',
      {'deleted_at': now, 'updated_at': now, 'dirty': 1},
      where: 'medicine_id = ? AND day_key >= ?',
      whereArgs: [id, AkashaDates.key(AkashaDates.today())],
    );
  }

  /// (Re)creates schedule rows for the next [days] days that match the
  /// medicine's weekdays and date range.
  Future<void> regenerateSchedules(
    Medicine medicine, {
    int days = 14,
    Transaction? txn,
  }) async {
    if (!medicine.enabled) return;
    final today = AkashaDates.today();
    await _db.write(txn, (txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.update(
        'medicine_schedules',
        {'deleted_at': now, 'updated_at': now, 'dirty': 1},
        where: 'medicine_id = ? AND day_key >= ? AND deleted_at IS NULL',
        whereArgs: [medicine.id, AkashaDates.key(today)],
      );

      for (var i = 0; i < days; i++) {
        final day = today.add(Duration(days: i));
        if (!medicine.isDueOn(day)) continue;
        for (final minute in medicine.reminderMinutes) {
          final schedule = {
            'id': Ids.slotId('medsched', '${medicine.id}:${AkashaDates.key(day)}:$minute'),
            'user_id': medicine.userId,
            'medicine_id': medicine.id,
            'minute_of_day': minute,
            'day_key': AkashaDates.key(day),
            'enabled': 1,
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
            'deleted_at': null,
            'dirty': 1,
          };
          // Upsert, not REPLACE: the schedule rows for these days were
          // soft-deleted just above and hold these exact deterministic ids, so
          // they must be revived with their original `created_at`.
          await AppDatabase.upsert(txn, 'medicine_schedules', schedule);

          // Materialise the log row so history is complete even if the
          // notification is never opened.
          await _ensureLogRow(
            txn,
            userId: medicine.userId,
            medicineId: medicine.id,
            scheduleId: schedule['id'] as String,
            day: day,
            minute: minute,
          );
        }
      }
    });
  }

  /// The deterministic id of the log row for one dose of one medicine.
  ///
  /// Used by both [regenerateSchedules] (when creating the row) and
  /// [ReminderScheduler] (when embedding the id in a notification payload), so
  /// pressing "I took it" always addresses a row that exists or can be created.
  static String logIdFor({
    required String medicineId,
    required DateTime day,
    required int minute,
  }) =>
      Ids.slotId('medlog', '$medicineId:${AkashaDates.key(day)}:$minute');

  /// Id used by the *planner* — same formula, expressed once in pure code so
  /// the notification layer does not need a repository instance.
  static String planLogId(String medicineId, DateTime day, int minute) =>
      Ids.slotId('medlog', '$medicineId:${AkashaDates.key(day)}:$minute');

  Future<void> _ensureLogRow(
    Transaction txn, {
    required String userId,
    required String medicineId,
    required String scheduleId,
    required DateTime day,
    required int minute,
  }) async {
    final existing = await txn.query(
      'medicine_logs',
      where: 'medicine_id = ? AND day_key = ? AND scheduled_minute = ?',
      whereArgs: [medicineId, AkashaDates.key(day), minute],
      limit: 1,
    );
    if (existing.isNotEmpty) return;

    final log = MedicineLog(
      id: logIdFor(medicineId: medicineId, day: day, minute: minute),
      userId: userId,
      medicineId: medicineId,
      scheduleId: scheduleId,
      dayKey: AkashaDates.key(day),
      scheduledMinute: minute,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await AppDatabase.upsert(txn, 'medicine_logs', log.toRow());
  }

  // ── Doses ───────────────────────────────────────────────────────────────

  /// Today's doses joined with their medicines, sorted by time.
  Future<List<DoseView>> dosesForDay(String userId, DateTime day) async {
    final rows = await _db.db.rawQuery(
      '''
      SELECT l.*, m.name AS m_name, m.dosage AS m_dosage, m.notes AS m_notes,
             m.category AS m_category, m.start_day AS m_start_day,
             m.end_day AS m_end_day, m.weekdays AS m_weekdays,
             m.enabled AS m_enabled, m.with_food AS m_with_food,
             m.color_hex AS m_color_hex, m.reminder_minutes AS m_reminder_minutes,
             m.user_id AS m_user_id, m.created_at AS m_created_at,
             m.updated_at AS m_updated_at
      FROM medicine_logs l
      JOIN medicines m ON m.id = l.medicine_id
      WHERE l.user_id = ? AND l.day_key = ? AND l.deleted_at IS NULL
        AND m.deleted_at IS NULL
      ORDER BY l.scheduled_minute ASC
      ''',
      [userId, AkashaDates.key(day)],
    );
    return rows.map((r) {
      final medicine = Medicine.fromRow({
        'id': r['medicine_id'],
        'user_id': r['m_user_id'],
        'name': r['m_name'],
        'dosage': r['m_dosage'],
        'notes': r['m_notes'],
        'category': r['m_category'],
        'start_day': r['m_start_day'],
        'end_day': r['m_end_day'],
        'weekdays': r['m_weekdays'],
        'enabled': r['m_enabled'],
        'with_food': r['m_with_food'],
        'color_hex': r['m_color_hex'],
        'reminder_minutes': r['m_reminder_minutes'],
        'created_at': r['m_created_at'],
        'updated_at': r['m_updated_at'],
      });
      return DoseView(log: MedicineLog.fromRow(r), medicine: medicine);
    }).toList();
  }

  Future<List<MedicineLog>> logsForRange(
    String userId,
    DateTime from,
    DateTime to,
  ) async {
    final rows = await _db.db.query(
      'medicine_logs',
      where: 'user_id = ? AND day_key BETWEEN ? AND ? AND deleted_at IS NULL',
      whereArgs: [userId, AkashaDates.key(from), AkashaDates.key(to)],
      orderBy: 'day_key DESC, scheduled_minute ASC',
    );
    return rows.map(MedicineLog.fromRow).toList();
  }

  Future<void> recordResponse({
    required String logId,
    required DoseStatus status,
    DateTime? snoozedUntil,
    String? notes,
  }) async {
    final patch = AppDatabase.touch({
      'status': status.key,
      'responded_at': DateTime.now().millisecondsSinceEpoch,
      'snoozed_until': snoozedUntil?.millisecondsSinceEpoch,
      if (notes != null) 'notes': notes,
    });

    final updated = await _db.db.update(
      'medicine_logs',
      patch,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [logId],
    );
    if (updated > 0) return;

    // Nothing to update: the notification fired before the day's rows were
    // materialised (first launch, or the app was asleep past midnight). The id
    // is deterministic, so the dose can be reconstructed exactly — her tap must
    // never be silently dropped.
    await _recreateLogRow(logId, patch);
  }

  /// Applies a dose response **inside an existing transaction**.
  ///
  /// Same semantics as [recordResponse] (including "recreate the row from its
  /// deterministic id if it was never materialised"), but it enlists the caller's
  /// transaction so the response and the notification dedupe marker commit
  /// together. A dose is only ever set to `taken` on explicit user confirmation.
  Future<void> applyResponseInTxn(
    Transaction txn, {
    required String logId,
    required DoseStatus status,
    DateTime? snoozedUntil,
    DateTime? respondedAt,
    String? notes,
  }) async {
    final responded = respondedAt ?? DateTime.now();
    final patch = {
      'status': status.key,
      'responded_at': responded.millisecondsSinceEpoch,
      'snoozed_until': snoozedUntil?.millisecondsSinceEpoch,
      'updated_at': responded.millisecondsSinceEpoch,
      'dirty': 1,
      if (notes != null) 'notes': notes,
    };

    final updated = await txn.update(
      'medicine_logs',
      patch,
      where: 'id = ? AND deleted_at IS NULL',
      whereArgs: [logId],
    );
    if (updated > 0) return;

    // Not materialised yet — rebuild it from the deterministic id.
    const scope = 'medlog:';
    if (!logId.startsWith(scope)) return;
    final parts = logId.substring(scope.length).split(':');
    if (parts.length < 3) return;
    final minute = int.tryParse(parts.last);
    final dayKey = parts[parts.length - 2];
    final medicineId = parts.sublist(0, parts.length - 2).join(':');
    if (minute == null) return;

    final medicineRows = await txn.query(
      'medicines',
      where: 'id = ?',
      whereArgs: [medicineId],
      limit: 1,
    );
    if (medicineRows.isEmpty) return;
    final userId = medicineRows.first['user_id'] as String?;
    if (userId == null) return;

    // Upsert: this is a "create the row if the notification beat the schedule
    // materialiser to it, otherwise apply the answer to the existing row". An
    // `ignore` would silently drop the user's answer when the row already
    // existed, which is worse than a duplicate.
    await AppDatabase.upsert(
      txn,
      'medicine_logs',
      {
        'id': logId,
        'created_at': responded.millisecondsSinceEpoch,
        'dirty': 1,
        'user_id': userId,
        'medicine_id': medicineId,
        'schedule_id': null,
        'day_key': dayKey,
        'scheduled_minute': minute,
        'responded_at': null,
        'status': DoseStatus.scheduled.key,
        'snoozed_until': null,
        'notes': null,
        ...patch,
      },
    );
  }

  /// Rebuilds a single log row from a deterministic id of the form
  /// `medlog:<medicineId>:<yyyy-MM-dd>:<minute>`.
  Future<void> _recreateLogRow(String logId, Map<String, Object?> patch) async {
    const scope = 'medlog:';
    if (!logId.startsWith(scope)) return;
    final parts = logId.substring(scope.length).split(':');
    if (parts.length < 3) return;
    final minute = int.tryParse(parts.last);
    final dayKey = parts[parts.length - 2];
    final medicineId = parts.sublist(0, parts.length - 2).join(':');
    if (minute == null) return;

    final medicineRows = await _db.db.query(
      'medicines',
      where: 'id = ?',
      whereArgs: [medicineId],
      limit: 1,
    );
    if (medicineRows.isEmpty) return;
    final userId = medicineRows.first['user_id'] as String?;
    if (userId == null) return;

    final now = DateTime.now();
    // Same reasoning as the transactional path: recreate *or* patch in place.
    await AppDatabase.upsert(
      _db.db,
      'medicine_logs',
      {
        'id': logId,
        'created_at': now.millisecondsSinceEpoch,
        'dirty': 1,
        'user_id': userId,
        'medicine_id': medicineId,
        'schedule_id': null,
        'day_key': dayKey,
        'scheduled_minute': minute,
        'responded_at': null,
        'status': DoseStatus.scheduled.key,
        'snoozed_until': null,
        'notes': null,
        ...patch,
      },
    );
  }

  /// Called on app start / midnight. Anything still `scheduled` on a past day
  /// becomes `missed` — honestly, not judgementally.
  Future<int> reconcileMissedDoses(String userId) async {
    final todayKey = AkashaDates.key(AkashaDates.today());
    final result = await _db.db.update(
      'medicine_logs',
      {
        'status': DoseStatus.missed.key,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
        'dirty': 1,
      },
      where: 'user_id = ? AND day_key < ? AND status IN (?, ?)',
      whereArgs: [userId, todayKey, DoseStatus.scheduled.key, DoseStatus.snoozed.key],
    );
    return result;
  }

  Future<DoseDayStats> statsForDay(String userId, DateTime day) async {
    final doses = await dosesForDay(userId, day);
    var taken = 0, skipped = 0, missed = 0, pending = 0;
    for (final d in doses) {
      switch (d.log.status) {
        case DoseStatus.taken:
          taken++;
        case DoseStatus.skipped:
          skipped++;
        case DoseStatus.missed:
          missed++;
        case DoseStatus.scheduled:
        case DoseStatus.snoozed:
          pending++;
      }
    }
    return DoseDayStats(
      total: doses.length,
      taken: taken,
      skipped: skipped,
      missed: missed,
      pending: pending,
    );
  }

  Future<Map<String, DoseDayStats>> statsForRange(
    String userId,
    DateTime from,
    DateTime to,
  ) async {
    final logs = await logsForRange(userId, from, to);
    final grouped = <String, List<MedicineLog>>{};
    for (final log in logs) {
      grouped.putIfAbsent(log.dayKey, () => []).add(log);
    }
    return grouped.map((key, logs) {
      var taken = 0, skipped = 0, missed = 0, pending = 0;
      for (final l in logs) {
        switch (l.status) {
          case DoseStatus.taken:
            taken++;
          case DoseStatus.skipped:
            skipped++;
          case DoseStatus.missed:
            missed++;
          case DoseStatus.scheduled:
          case DoseStatus.snoozed:
            pending++;
        }
      }
      return MapEntry(
        key,
        DoseDayStats(
          total: logs.length,
          taken: taken,
          skipped: skipped,
          missed: missed,
          pending: pending,
        ),
      );
    });
  }
}

class DoseDayStats {
  const DoseDayStats({
    required this.total,
    required this.taken,
    required this.skipped,
    required this.missed,
    required this.pending,
  });

  final int total;
  final int taken;
  final int skipped;
  final int missed;
  final int pending;

  static const empty =
      DoseDayStats(total: 0, taken: 0, skipped: 0, missed: 0, pending: 0);

  double get adherence => total == 0 ? 0 : taken / total;
}
