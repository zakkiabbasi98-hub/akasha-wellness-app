import 'dart:math' as math;

import '../constants/app_constants.dart';

/// A single generated reminder slot.
class ScheduleSlot {
  const ScheduleSlot({required this.minuteOfDay, required this.label});

  /// Minutes from local midnight, 0..1439. `0` means 12:00 AM.
  final int minuteOfDay;
  final String label;

  @override
  String toString() => '$label ($minuteOfDay)';

  @override
  bool operator ==(Object other) =>
      other is ScheduleSlot && other.minuteOfDay == minuteOfDay;

  @override
  int get hashCode => minuteOfDay;
}

/// Pure, dependency-free water schedule generator.
///
/// This is the most behaviour-critical piece of the app, so it is deliberately
/// isolated from Flutter, notifications and the database — which makes it
/// exhaustively unit-testable (see test/unit/water_schedule_engine_test.dart).
///
/// Semantics
/// ---------
/// * `startMinute` is inclusive.
/// * `endMinute` is inclusive **when it lands on the interval grid**.
/// * A window whose end is at or before its start crosses midnight
///   (e.g. 09:00 → 12:00 AM is a normal waking window, not an error).
/// * `0` (midnight) represents 12:00 AM and must be produced for the default
///   schedule — this is exactly the bug the spec warns about.
abstract final class WaterScheduleEngine {
  /// Hard safety cap: more than this many daily reminders would be abusive
  /// notification spam (and Android caps pending alarms anyway).
  static const int maxSlots = 96;
  static const int minIntervalMinutes = 5;

  /// Generates the slots for one day.
  ///
  /// Throws [ArgumentError] for nonsensical intervals or empty windows, so
  /// callers cannot silently schedule nothing.
  static List<ScheduleSlot> generate({
    required int startMinute,
    required int endMinute,
    required int intervalMinutes,
  }) {
    if (intervalMinutes < minIntervalMinutes) {
      throw ArgumentError.value(
        intervalMinutes,
        'intervalMinutes',
        'Reminders must be at least $minIntervalMinutes minutes apart',
      );
    }

    final start = _wrap(startMinute);
    final end = _wrap(endMinute);

    // Extend the window past midnight when it wraps. `start == end` is treated
    // as a full 24-hour window (not a zero-length one), because "09:00 to 09:00"
    // is how a person describes "all day", never "no reminders at all".
    //
    // The closing boundary would repeat the first slot, and `seen` drops it, so a
    // full-day hourly window yields 24 slots (not 25) — one reminder per hour,
    // never two at the same minute.
    final windowEnd = (end <= start) ? end + _minutesPerDay : end;

    final span = windowEnd - start;
    if (span <= 0) {
      throw ArgumentError('Empty reminder window');
    }

    final slots = <ScheduleSlot>[];
    final seen = <int>{};

    for (var cursor = start; cursor <= windowEnd; cursor += intervalMinutes) {
      final minute = _wrap(cursor);
      if (!seen.add(minute)) continue; // defensive duplicate prevention
      slots.add(ScheduleSlot(minuteOfDay: minute, label: formatLabel(minute)));
      if (slots.length >= maxSlots) break;
    }

    return slots;
  }

  /// The exact default the spec pins down: 09:00 → 12:00 AM every hour.
  /// Expected: 16 reminders including 12:00 AM.
  static List<ScheduleSlot> defaults() => generate(
        startMinute: AppConstants.defaultWaterStartMinute,
        endMinute: AppConstants.defaultWaterEndMinute,
        intervalMinutes: AppConstants.defaultWaterIntervalMinutes,
      );

  /// Sorted, de-duplicated list of minute-of-day values.
  static List<int> minutes(
    List<ScheduleSlot> slots,
  ) {
    final unique = slots.map((s) => s.minuteOfDay).toSet().toList()..sort();
    return unique;
  }

  /// True when two schedules would produce identical slot sets — used to
  /// prevent accidental duplicate schedules before persisting.
  static bool areEquivalent(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final sa = a.toSet(), sb = b.toSet();
    return sa.length == sb.length && sa.containsAll(sb);
  }

  /// Validates a candidate slot minute.
  static bool isValidMinute(int minute) => minute >= 0 && minute < _minutesPerDay;

  /// "09:00 AM" → 540. Never throws; returns null for junk.
  static int? parseTime(String raw) => parseTimeToMinutesSafe(raw);

  /// "12:00 AM" comes back as 0 — *not* 1440. Callers that need "end of the
  /// waking day" semantics rely on [generate]'s wrap-around handling.
  static String formatLabel(int minuteOfDay) {
    final m = _wrap(minuteOfDay);
    final h24 = m ~/ 60;
    final mm = m % 60;
    final period = h24 < 12 ? 'AM' : 'PM';
    var h12 = h24 % 12;
    if (h12 == 0) h12 = 12;
    return '${h12.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')} $period';
  }

  /// Next slot strictly after [now], rolling to tomorrow's first slot.
  /// Used by "up next" copy on the water screen.
  static ScheduleSlot? nextSlot(List<ScheduleSlot> slots, DateTime now) {
    if (slots.isEmpty) return null;
    final current = now.hour * 60 + now.minute;
    final sorted = [...slots]..sort((a, b) => a.minuteOfDay.compareTo(b.minuteOfDay));
    for (final s in sorted) {
      if (s.minuteOfDay > current) return s;
    }
    return sorted.first; // tomorrow's first
  }

  /// How many slots are still ahead of [now] in the current waking day.
  ///
  /// The 12:00 AM (minute `0`) slot belongs to the *end* of the day window, not
  /// the start, so at 21:00 the midnight reminder still counts as ahead of you.
  /// It is therefore ordered at 1440 rather than 0 for this calculation.
  static int remainingToday(List<ScheduleSlot> slots, DateTime now) {
    final current = now.hour * 60 + now.minute;
    return slots.where((s) {
      final effective = s.minuteOfDay == 0 ? _minutesPerDay : s.minuteOfDay;
      return effective >= current;
    }).length;
  }

  /// Evenly spaced reminders count, e.g. for the settings summary.
  static int estimateSlotsPerDay({
    required int startMinute,
    required int endMinute,
    required int intervalMinutes,
  }) {
    try {
      return generate(
        startMinute: startMinute,
        endMinute: endMinute,
        intervalMinutes: intervalMinutes,
      ).length;
    } catch (_) {
      return 0;
    }
  }

  static const int _minutesPerDay = 24 * 60;

  static int _wrap(int minute) => ((minute % _minutesPerDay) + _minutesPerDay) % _minutesPerDay;

  /// Independent parser (kept local so this file has zero imports from the UI
  /// layer). Accepts "9:00", "09:00", "9:00 AM", "9 PM", "0:00".
  static int? parseTimeToMinutesSafe(String raw) {
    final text = raw.trim().toUpperCase().replaceAll('.', ':');
    if (text.isEmpty) return null;

    final amPmMatch = RegExp(r'^(\d{1,2})(?::(\d{2}))?\s*(AM|PM)$').firstMatch(text);
    if (amPmMatch != null) {
      var hour = int.parse(amPmMatch.group(1)!);
      final minute = int.tryParse(amPmMatch.group(2) ?? '0') ?? 0;
      if (hour > 12 || minute > 59) return null;
      final isPm = amPmMatch.group(3) == 'PM';
      if (hour == 12) hour = isPm ? 12 : 0;
      else if (isPm) hour += 12;
      return hour * 60 + minute;
    }

    final hhmm = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
    if (hhmm != null) {
      final hour = int.parse(hhmm.group(1)!);
      final minute = int.parse(hhmm.group(2)!);
      if (hour > 23 || minute > 59) return null;
      return hour * 60 + minute;
    }

    final hourOnly = int.tryParse(text);
    if (hourOnly != null && hourOnly >= 0 && hourOnly <= 23) {
      return hourOnly * 60;
    }
    return null;
  }

  /// Total minutes covered by the window (handles midnight wrap).
  static int windowSpanMinutes(int startMinute, int endMinute) {
    final start = _wrap(startMinute);
    final end = _wrap(endMinute);
    final endExt = end <= start ? end + _minutesPerDay : end;
    return endExt - start;
  }

  /// Convenience for the settings summary: how many reminders per day.
  static String describeWindow(int startMinute, int endMinute) =>
      '${formatLabel(startMinute)} – ${formatLabel(endMinute)}';

  /// Rounds an arbitrary "now" down to the nearest whole minute — keeps the
  /// snooze maths predictable.
  static DateTime truncateToMinute(DateTime d) =>
      DateTime(d.year, d.month, d.day, d.hour, d.minute);

  /// Used by the UI to show a friendly "16 gentle reminders a day".
  static int clampedSlotCount(int start, int end, int interval) =>
      math.min(estimateSlotsPerDay(startMinute: start, endMinute: end, intervalMinutes: interval), maxSlots);
}
