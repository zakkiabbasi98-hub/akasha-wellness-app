import '../../core/database/app_database.dart';
import '../../core/utils/date_utils.dart';
import 'sync_entity.dart';

enum MedicineCategory {
  morning('morning', 'Morning', 8 * 60),
  afternoon('afternoon', 'Afternoon', 14 * 60),
  night('night', 'Night', 21 * 60),
  custom('custom', 'As set', 12 * 60);

  const MedicineCategory(this.key, this.label, this.exampleMinute);
  final String key;
  final String label;

  /// Example time offered during setup. NOT a medical recommendation — the
  /// UI labels it as "an example, change it to match your prescription".
  final int exampleMinute;

  static MedicineCategory fromKey(String? key) => MedicineCategory.values
      .firstWhere((c) => c.key == key, orElse: () => MedicineCategory.custom);
}

/// A user-defined medicine and its recurring reminder times.
class Medicine with SyncEntity {
  Medicine({
    required this.id,
    required this.userId,
    required this.name,
    required this.startDay,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = true,
    this.dosage,
    this.notes,
    this.category = MedicineCategory.custom,
    this.endDay,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.enabled = true,
    this.withFood,
    this.colorHex = 'F2A9CE',
    this.reminderMinutes = const [],
  });

  @override
  final String id;
  final String userId;
  final String name;

  /// Free text copied from her own prescription. The app never generates or
  /// changes dosage advice.
  final String? dosage;
  final String? notes;
  final MedicineCategory category;
  final String startDay;
  final String? endDay;

  /// 1 = Monday … 7 = Sunday (matches DateTime.weekday).
  final List<int> weekdays;
  final bool enabled;
  final String? withFood;
  final String colorHex;
  final List<int> reminderMinutes;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  bool get isActive => enabled && deletedAt == null;

  bool isDueOn(DateTime day) {
    if (!enabled) return false;
    if (!weekdays.contains(day.weekday)) return false;
    final key = AkashaDates.key(day);
    if (key.compareTo(startDay) < 0) return false;
    final end = endDay;
    if (end != null && key.compareTo(end) > 0) return false;
    return true;
  }

  Medicine copyWith({
    String? name,
    String? dosage,
    String? notes,
    MedicineCategory? category,
    String? startDay,
    String? endDay,
    bool clearEndDay = false,
    List<int>? weekdays,
    bool? enabled,
    String? withFood,
    String? colorHex,
    List<int>? reminderMinutes,
  }) =>
      Medicine(
        id: id,
        userId: userId,
        name: name ?? this.name,
        dosage: dosage ?? this.dosage,
        notes: notes ?? this.notes,
        category: category ?? this.category,
        startDay: startDay ?? this.startDay,
        endDay: clearEndDay ? null : (endDay ?? this.endDay),
        weekdays: weekdays ?? this.weekdays,
        enabled: enabled ?? this.enabled,
        withFood: withFood ?? this.withFood,
        colorHex: colorHex ?? this.colorHex,
        reminderMinutes: reminderMinutes ?? this.reminderMinutes,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        deletedAt: deletedAt,
      );

  @override
  Map<String, Object?> toRow() => AppDatabase.insertRow({
        'id': id,
        'user_id': userId,
        'name': name,
        'dosage': dosage,
        'notes': notes,
        'category': category.key,
        'start_day': startDay,
        'end_day': endDay,
        'weekdays': weekdays.join(','),
        'enabled': enabled ? 1 : 0,
        'with_food': withFood,
        'color_hex': colorHex,
        'reminder_minutes': reminderMinutes.join(','),
        'deleted_at': SyncEntity.toMillis(deletedAt),
      }, createdAt: createdAt);

  factory Medicine.fromRow(Map<String, Object?> r) => Medicine(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        name: r['name'] as String,
        dosage: r['dosage'] as String?,
        notes: r['notes'] as String?,
        category: MedicineCategory.fromKey(r['category'] as String?),
        startDay: r['start_day'] as String,
        endDay: r['end_day'] as String?,
        weekdays: _parseInts(r['weekdays'] as String?, [1, 2, 3, 4, 5, 6, 7]),
        enabled: (r['enabled'] as int? ?? 1) == 1,
        withFood: r['with_food'] as String?,
        colorHex: r['color_hex'] as String? ?? 'F2A9CE',
        reminderMinutes: _parseInts(r['reminder_minutes'] as String?, const []),
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 1) == 1,
      );
}

enum DoseStatus {
  scheduled('scheduled', 'Scheduled'),
  taken('taken', 'Taken'),
  skipped('skipped', 'Skipped'),
  snoozed('snoozed', 'Snoozed'),
  missed('missed', 'Missed');

  const DoseStatus(this.key, this.label);
  final String key;
  final String label;

  static DoseStatus fromKey(String? key) =>
      DoseStatus.values.firstWhere((s) => s.key == key, orElse: () => DoseStatus.scheduled);
}

/// One scheduled dose occurrence and Akasha's response to it.
///
/// An unanswered dose stays [DoseStatus.scheduled] until the day ends, at
/// which point it becomes [DoseStatus.missed] — it is NEVER auto-marked taken.
class MedicineLog with SyncEntity {
  MedicineLog({
    required this.id,
    required this.userId,
    required this.medicineId,
    required this.dayKey,
    required this.scheduledMinute,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = true,
    this.scheduleId,
    this.respondedAt,
    this.status = DoseStatus.scheduled,
    this.snoozedUntil,
    this.notes,
  });

  @override
  final String id;
  final String userId;
  final String medicineId;
  final String? scheduleId;
  final String dayKey;
  final int scheduledMinute;
  final DateTime? respondedAt;
  final DoseStatus status;
  final DateTime? snoozedUntil;
  final String? notes;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  DateTime get scheduledAt =>
      AkashaDates.withMinutes(AkashaDates.parseKey(dayKey), scheduledMinute);

  bool get isAnswered =>
      status == DoseStatus.taken || status == DoseStatus.skipped || status == DoseStatus.missed;

  MedicineLog copyWith({
    DateTime? respondedAt,
    DoseStatus? status,
    DateTime? snoozedUntil,
    String? notes,
  }) =>
      MedicineLog(
        id: id,
        userId: userId,
        medicineId: medicineId,
        scheduleId: scheduleId,
        dayKey: dayKey,
        scheduledMinute: scheduledMinute,
        respondedAt: respondedAt ?? this.respondedAt,
        status: status ?? this.status,
        snoozedUntil: snoozedUntil ?? this.snoozedUntil,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        deletedAt: deletedAt,
      );

  @override
  Map<String, Object?> toRow() => AppDatabase.insertRow({
        'id': id,
        'user_id': userId,
        'medicine_id': medicineId,
        'schedule_id': scheduleId,
        'day_key': dayKey,
        'scheduled_minute': scheduledMinute,
        'responded_at': SyncEntity.toMillis(respondedAt),
        'status': status.key,
        'snoozed_until': SyncEntity.toMillis(snoozedUntil),
        'notes': notes,
        'deleted_at': SyncEntity.toMillis(deletedAt),
      }, createdAt: createdAt);

  factory MedicineLog.fromRow(Map<String, Object?> r) => MedicineLog(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        medicineId: r['medicine_id'] as String,
        scheduleId: r['schedule_id'] as String?,
        dayKey: r['day_key'] as String,
        scheduledMinute: r['scheduled_minute'] as int,
        respondedAt: SyncEntity.fromMillis(r['responded_at']),
        status: DoseStatus.fromKey(r['status'] as String?),
        snoozedUntil: SyncEntity.fromMillis(r['snoozed_until']),
        notes: r['notes'] as String?,
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 1) == 1,
      );
}

/// A dose joined with its medicine for list rendering.
class DoseView {
  const DoseView({required this.log, required this.medicine});
  final MedicineLog log;
  final Medicine medicine;
}

List<int> _parseInts(String? raw, List<int> fallback) {
  if (raw == null || raw.trim().isEmpty) return fallback;
  final parsed = raw
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toList()
    ..sort();
  return parsed.isEmpty ? fallback : parsed;
}
