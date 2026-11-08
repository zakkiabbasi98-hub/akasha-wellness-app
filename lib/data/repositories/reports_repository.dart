import '../../core/utils/date_utils.dart';
import '../models/medicine_models.dart';
import '../models/mind_models.dart';
import '../models/water_models.dart';
import 'medicine_repository.dart';
import 'mind_repository.dart';
import 'water_repository.dart';

/// One day of real, joined wellness data.
class DailyReport {
  const DailyReport({
    required this.day,
    required this.water,
    required this.doses,
    required this.moods,
    required this.journalCount,
    required this.gratitude,
    required this.breathingMinutes,
    required this.breathingSessions,
    this.waterRemindersHandled = 0,
    this.waterRemindersSkipped = 0,
  });

  final DateTime day;
  final DailyWaterSummary water;
  final DoseDayStats doses;
  final List<MoodEntry> moods;
  final int journalCount;
  final GratitudeEntry? gratitude;
  final int breathingMinutes;
  final int breathingSessions;
  final int waterRemindersHandled;
  final int waterRemindersSkipped;

  bool get waterComplete => water.totalMl >= water.targetMl && water.targetMl > 0;
  bool get hasAnyData =>
      water.totalMl > 0 ||
      doses.total > 0 ||
      moods.isNotEmpty ||
      journalCount > 0 ||
      gratitude != null ||
      breathingSessions > 0;

  /// A gentle 0–100 "how much care did you give yourself today" indicator.
  /// Deliberately NOT called a health score and never shown as a judgement.
  int get wellnessPoints {
    var points = 0;
    points += (water.targetProgress.clamp(0, 1) * 40).round();
    if (doses.total > 0) points += (doses.adherence.clamp(0, 1) * 30).round();
    else points += 30; // no medication prescribed today → full credit
    if (moods.isNotEmpty) points += 10;
    if (journalCount > 0) points += 10;
    if (gratitude != null) points += 5;
    if (breathingSessions > 0) points += 5;
    return points.clamp(0, 100);
  }
}

/// Aggregate over a range (weekly / monthly reports).
class RangeReport {
  const RangeReport({
    required this.from,
    required this.to,
    required this.days,
    required this.waterTrend,
    required this.doseStats,
    required this.moodCounts,
    required this.journalCount,
    required this.gratitudeCount,
    required this.breathingMinutes,
    required this.targetMl,
  });

  final DateTime from;
  final DateTime to;
  final List<DailyReport> days;
  final List<WaterTrendPoint> waterTrend;
  final Map<String, DoseDayStats> doseStats;
  final Map<MoodType, int> moodCounts;
  final int journalCount;
  final int gratitudeCount;
  final int breathingMinutes;
  final int targetMl;

  int get totalWaterMl => waterTrend.fold(0, (s, p) => s + p.totalMl);
  int get averageWaterMl => days.isEmpty ? 0 : totalWaterMl ~/ days.length;
  int get daysTargetMet => waterTrend.where((p) => p.totalMl >= p.targetMl).length;

  DoseDayStats get doses => doseStats.values.fold(
        DoseDayStats.empty,
        (acc, s) => DoseDayStats(
          total: acc.total + s.total,
          taken: acc.taken + s.taken,
          skipped: acc.skipped + s.skipped,
          missed: acc.missed + s.missed,
          pending: acc.pending + s.pending,
        ),
      );

  int get averageWellness {
    if (days.isEmpty) return 0;
    return days.fold<int>(0, (s, d) => s + d.wellnessPoints) ~/ days.length;
  }
}

/// Builds reports by joining the other repositories. No fake numbers: every
/// value here comes from a row Akasha created.
class ReportsRepository {
  ReportsRepository({
    required this.water,
    required this.medicine,
    required this.mind,
  });

  final WaterRepository water;
  final MedicineRepository medicine;
  final MindRepository mind;

  Future<DailyReport> daily({
    required String userId,
    required DateTime day,
    required int targetMl,
    required int glassSizeMl,
  }) async {
    final results = await Future.wait([
      water.summaryForDay(userId, day, targetMl: targetMl, glassSizeMl: glassSizeMl),
      medicine.statsForDay(userId, day),
      mind.moodsForDay(userId, day),
      mind.journalCountInRange(userId, day, day),
      mind.gratitudeForDay(userId, day),
      mind.breathingForDay(userId, day),
    ]);

    final summary = results[0] as DailyWaterSummary;
    final doseStats = results[1] as DoseDayStats;
    final moods = results[2] as List<MoodEntry>;
    final journalCount = results[3] as int;
    final gratitude = results[4] as GratitudeEntry?;
    final breathing = results[5] as List<BreathingSession>;

    return DailyReport(
      day: day,
      water: summary,
      doses: doseStats,
      moods: moods,
      journalCount: journalCount,
      gratitude: gratitude,
      breathingMinutes: breathing.fold(0, (s, b) => s + b.durationSeconds) ~/ 60,
      breathingSessions: breathing.length,
    );
  }

  Future<RangeReport> range({
    required String userId,
    required DateTime from,
    required DateTime to,
    required int targetMl,
    required int glassSizeMl,
  }) async {
    final days = <DailyReport>[];
    final dayCount = AkashaDates.daysBetween(from, to) + 1;
    for (var i = 0; i < dayCount; i++) {
      days.add(await daily(
        userId: userId,
        day: AkashaDates.dayOnly(from).add(Duration(days: i)),
        targetMl: targetMl,
        glassSizeMl: glassSizeMl,
      ));
    }

    final trend = await water.trend(userId, from, to, targetMl: targetMl);
    final doseStats = await medicine.statsForRange(userId, from, to);
    final moodCounts = await mind.moodDistribution(userId, from, to);
    final journalCount = await mind.journalCountInRange(userId, from, to);
    final gratitudeHistory = await mind.gratitudeHistory(userId, limit: 400);
    final gratitudeInRange = gratitudeHistory
        .where((g) => g.dayKey.compareTo(AkashaDates.key(from)) >= 0 &&
            g.dayKey.compareTo(AkashaDates.key(to)) <= 0)
        .length;
    final breathingMinutes = await mind.breathingMinutesInRange(userId, from, to);

    return RangeReport(
      from: from,
      to: to,
      days: days,
      waterTrend: trend,
      doseStats: doseStats,
      moodCounts: moodCounts,
      journalCount: journalCount,
      gratitudeCount: gratitudeInRange,
      breathingMinutes: breathingMinutes,
      targetMl: targetMl,
    );
  }

  Future<RangeReport> weekly({
    required String userId,
    required int targetMl,
    required int glassSizeMl,
    DateTime? anchor,
  }) async {
    final start = AkashaDates.startOfWeek(anchor ?? DateTime.now());
    return range(
      userId: userId,
      from: start,
      to: start.add(const Duration(days: 6)),
      targetMl: targetMl,
      glassSizeMl: glassSizeMl,
    );
  }

  Future<RangeReport> monthly({
    required String userId,
    required int targetMl,
    required int glassSizeMl,
    DateTime? anchor,
  }) async {
    final anchorDate = anchor ?? DateTime.now();
    return range(
      userId: userId,
      from: AkashaDates.startOfMonth(anchorDate),
      to: AkashaDates.endOfMonth(anchorDate),
      targetMl: targetMl,
      glassSizeMl: glassSizeMl,
    );
  }

  /// Day keys with any record — used to dot the calendar.
  Future<Map<DateTime, int>> activityMap({
    required String userId,
    required DateTime from,
    required DateTime to,
    required int targetMl,
  }) async {
    final waterTotals = await water.totalsByDay(userId, from, to);
    final journalDays = await mind.journalCountInRange(userId, from, to);
    final map = <DateTime, int>{};
    waterTotals.forEach((key, value) {
      map[AkashaDates.parseKey(key)] = value >= targetMl ? 3 : (value > 0 ? 2 : 1);
    });
    if (journalDays > 0) {
      // journal presence is aggregated; individual days come from the list
      final entries = await mind.journalEntries(userId, from: from, to: to, limit: 500);
      for (final e in entries) {
        final day = AkashaDates.parseKey(e.dayKey);
        final current = map[day] ?? 0;
        map[day] = current.clamp(1, 3);
      }
    }
    return map;
  }
}
