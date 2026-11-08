import '../../core/database/app_database.dart';
import '../../core/utils/date_utils.dart';
import 'sync_entity.dart';

/// One configured water reminder slot.
class WaterReminder with SyncEntity {
  WaterReminder({
    required this.id,
    required this.userId,
    required this.minuteOfDay,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = true,
    this.label = 'Water reminder',
    this.amountMl = 250,
    this.enabled = true,
    this.isDefaultSlot = true,
    this.sortOrder = 0,
  });

  @override
  final String id;
  final String userId;
  final int minuteOfDay;
  final String label;
  final int amountMl;
  final bool enabled;
  final bool isDefaultSlot;
  final int sortOrder;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  String get timeLabel => AkashaDates.minutesToLabel(minuteOfDay);

  WaterReminder copyWith({
    int? minuteOfDay,
    String? label,
    int? amountMl,
    bool? enabled,
    bool? isDefaultSlot,
    int? sortOrder,
  }) =>
      WaterReminder(
        id: id,
        userId: userId,
        minuteOfDay: minuteOfDay ?? this.minuteOfDay,
        label: label ?? this.label,
        amountMl: amountMl ?? this.amountMl,
        enabled: enabled ?? this.enabled,
        isDefaultSlot: isDefaultSlot ?? this.isDefaultSlot,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        deletedAt: deletedAt,
      );

  @override
  Map<String, Object?> toRow() => AppDatabase.stamp({
        'id': id,
        'user_id': userId,
        'label': label,
        'minute_of_day': minuteOfDay,
        'amount_ml': amountMl,
        'enabled': enabled ? 1 : 0,
        'is_default_slot': isDefaultSlot ? 1 : 0,
        'sort_order': sortOrder,
        'deleted_at': SyncEntity.toMillis(deletedAt),
      });

  factory WaterReminder.fromRow(Map<String, Object?> r) => WaterReminder(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        minuteOfDay: r['minute_of_day'] as int,
        label: r['label'] as String? ?? 'Water reminder',
        amountMl: r['amount_ml'] as int? ?? 250,
        enabled: (r['enabled'] as int? ?? 1) == 1,
        isDefaultSlot: (r['is_default_slot'] as int? ?? 1) == 1,
        sortOrder: r['sort_order'] as int? ?? 0,
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 1) == 1,
      );
}

enum WaterLogSource { manual, notification, snooze, quickAdd, undoRestore }

extension WaterLogSourceX on WaterLogSource {
  String get key => switch (this) {
        WaterLogSource.manual => 'manual',
        WaterLogSource.notification => 'notification',
        WaterLogSource.snooze => 'snooze',
        WaterLogSource.quickAdd => 'quick_add',
        WaterLogSource.undoRestore => 'undo_restore',
      };

  static WaterLogSource fromKey(String? key) => WaterLogSource.values.firstWhere(
        (s) => s.key == key,
        orElse: () => WaterLogSource.manual,
      );
}

/// A recorded drink. Never a placeholder — always a real user event.
class WaterLog with SyncEntity {
  WaterLog({
    required this.id,
    required this.userId,
    required this.dayKey,
    required this.loggedAt,
    required this.amountMl,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = true,
    this.source = WaterLogSource.manual,
    this.reminderMinute,
    this.glassSize,
    this.note,
  });

  @override
  final String id;
  final String userId;
  final String dayKey;
  final DateTime loggedAt;
  final int amountMl;
  final WaterLogSource source;
  final int? reminderMinute;
  final String? glassSize;
  final String? note;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  @override
  Map<String, Object?> toRow() => AppDatabase.stamp({
        'id': id,
        'user_id': userId,
        'day_key': dayKey,
        'logged_at': SyncEntity.toMillis(loggedAt),
        'amount_ml': amountMl,
        'source': source.key,
        'reminder_minute': reminderMinute,
        'glass_size': glassSize,
        'note': note,
        'deleted_at': SyncEntity.toMillis(deletedAt),
      });

  factory WaterLog.fromRow(Map<String, Object?> r) => WaterLog(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        dayKey: r['day_key'] as String,
        loggedAt: AkashaDates.fromMillis(r['logged_at'] as int),
        amountMl: r['amount_ml'] as int,
        source: WaterLogSourceX.fromKey(r['source'] as String?),
        reminderMinute: r['reminder_minute'] as int?,
        glassSize: r['glass_size'] as String?,
        note: r['note'] as String?,
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 1) == 1,
      );
}

enum SnoozeStatus { pending, fired, cancelled }

class WaterSnooze with SyncEntity {
  WaterSnooze({
    required this.id,
    required this.userId,
    required this.reminderMinute,
    required this.scheduledFor,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = true,
    this.firedAt,
    this.status = SnoozeStatus.pending,
  });

  @override
  final String id;
  final String userId;
  final int reminderMinute;
  final DateTime scheduledFor;
  final DateTime? firedAt;
  final SnoozeStatus status;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  WaterSnooze copyWith({DateTime? firedAt, SnoozeStatus? status}) => WaterSnooze(
        id: id,
        userId: userId,
        reminderMinute: reminderMinute,
        scheduledFor: scheduledFor,
        firedAt: firedAt ?? this.firedAt,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
        deletedAt: deletedAt,
      );

  @override
  Map<String, Object?> toRow() => AppDatabase.stamp({
        'id': id,
        'user_id': userId,
        'reminder_minute': reminderMinute,
        'scheduled_for': SyncEntity.toMillis(scheduledFor),
        'fired_at': SyncEntity.toMillis(firedAt),
        'status': status.name,
        'deleted_at': SyncEntity.toMillis(deletedAt),
      });

  factory WaterSnooze.fromRow(Map<String, Object?> r) => WaterSnooze(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        reminderMinute: r['reminder_minute'] as int,
        scheduledFor: AkashaDates.fromMillis(r['scheduled_for'] as int),
        firedAt: SyncEntity.fromMillis(r['fired_at']),
        status: SnoozeStatus.values.firstWhere(
          (s) => s.name == r['status'],
          orElse: () => SnoozeStatus.pending,
        ),
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 1) == 1,
      );
}

/// Aggregated hydration for one day — computed from real [WaterLog] rows.
class DailyWaterSummary {
  const DailyWaterSummary({
    required this.dayKey,
    required this.totalMl,
    required this.glassCount,
    required this.targetMl,
    required this.entries,
    this.remindersHandled = 0,
    this.remindersSkipped = 0,
  });

  final String dayKey;
  final int totalMl;
  final int glassCount;
  final int targetMl;
  final List<WaterLog> entries;
  final int remindersHandled;
  final int remindersSkipped;

  double get targetProgress => targetMl <= 0 ? 0 : totalMl / targetMl;
  int get remainingMl => (targetMl - totalMl).clamp(0, 1 << 31);
  bool get targetReached => totalMl >= targetMl;

  static const DailyWaterSummary empty = DailyWaterSummary(
    dayKey: '',
    totalMl: 0,
    glassCount: 0,
    targetMl: 2000,
    entries: [],
  );
}

/// A point in the weekly / monthly chart — always derived from the database.
class WaterTrendPoint {
  const WaterTrendPoint({required this.date, required this.totalMl, this.targetMl = 2000});

  final DateTime date;
  final int totalMl;
  final int targetMl;

  double get ratio => targetMl <= 0 ? 0 : (totalMl / targetMl).clamp(0, 1.5);
}
