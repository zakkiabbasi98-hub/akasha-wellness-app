import 'package:intl/intl.dart';

/// Date helpers shared by schedule engines, queries and UI.
///
/// Everything is local-time based: AKASHA is a device-first app, so "today"
/// always means the user's today, even if her phone's clock is wrong.
abstract final class AkashaDates {
  static DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime today() => dayOnly(DateTime.now());

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  static DateTime startOfWeek(DateTime d) {
    final day = dayOnly(d);
    return day.subtract(Duration(days: day.weekday - 1)); // Monday first
  }

  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  static DateTime endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0, 23, 59, 59, 999);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool isToday(DateTime d) => isSameDay(d, DateTime.now());

  static bool isTomorrow(DateTime d) =>
      isSameDay(d, DateTime.now().add(const Duration(days: 1)));

  static int daysBetween(DateTime a, DateTime b) =>
      dayOnly(b).difference(dayOnly(a)).inDays;

  /// ISO date key used for all SQLite day-columns: `2026-11-08`.
  static String key(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  static DateTime parseKey(String key) => DateFormat('yyyy-MM-dd').parse(key);

  /// Timestamps are stored as epoch milliseconds (timezone-safe on disk).
  static int millis(DateTime d) => d.millisecondsSinceEpoch;

  static DateTime fromMillis(int ms) => DateTime.fromMillisecondsSinceEpoch(ms);

  static String hhmm(DateTime d) => DateFormat('h:mm a').format(d);

  static String hhmm24(DateTime d) => DateFormat('HH:mm').format(d);

  static String prettyDate(DateTime d) {
    if (isToday(d)) return 'Today';
    if (isToday(d.subtract(const Duration(days: 1)))) return 'Yesterday';
    if (isToday(d.add(const Duration(days: 1)))) return 'Tomorrow';
    return DateFormat('EEEE, d MMMM').format(d);
  }

  static String shortDate(DateTime d) => DateFormat('d MMM yyyy').format(d);

  static String monthYear(DateTime d) => DateFormat('MMMM yyyy').format(d);

  static String weekdayShort(DateTime d) => DateFormat('EEE').format(d);

  static String relativeTime(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return shortDate(d);
  }

  /// Parses "09:00", "9:00 AM", "21:30" into minutes-from-midnight.
  /// Returns null when the input cannot be understood.
  static int? parseTimeToMinutes(String raw) {
    final input = raw.trim().toUpperCase();
    if (input.isEmpty) return null;

    final ampm = RegExp(r'(\d{1,2})[:.](\d{2})\s*(AM|PM)').firstMatch(input) ??
        RegExp(r'^(\d{1,2})\s*(AM|PM)').firstMatch(input);
    if (ampm != null) {
      var h = int.parse(ampm.group(1)!);
      final m = ampm.group(2) != null && ampm.group(2)!.length == 2 &&
              ampm.groupCount >= 3 && int.tryParse(ampm.group(2)!) != null
          ? int.tryParse(ampm.group(2)!) ?? 0
          : 0;
      final isPm = ampm.group(ampm.groupCount)! == 'PM';
      if (h == 12) h = isPm ? 12 : 0;
      else if (isPm) h += 12;
      return (h % 24) * 60 + m;
    }

    final h24 = RegExp(r'^(\d{1,2})[:.](\d{2})$').firstMatch(input);
    if (h24 != null) {
      final h = int.parse(h24.group(1)!);
      final m = int.parse(h24.group(2)!);
      if (h > 23 || m > 59) return null;
      return h * 60 + m;
    }
    final onlyHour = int.tryParse(input);
    if (onlyHour != null && onlyHour >= 0 && onlyHour <= 23) return onlyHour * 60;
    return null;
  }

  static String minutesToLabel(int minutes) {
    final normalized = minutes % (24 * 60);
    final h = normalized ~/ 60;
    final m = normalized % 60;
    final dt = DateTime(2000, 1, 1, h, m);
    return DateFormat('h:mm a').format(dt);
  }

  /// 12:00 AM → 0 minutes, which is what schedule generators need.
  static int nowMinutes() => DateTime.now().hour * 60 + DateTime.now().minute;

  /// Hours since midnight for an [hour] value where midnight == 0.
  static DateTime withMinutes(DateTime day, int minutes) {
    final d = dayOnly(day);
    return d.add(Duration(minutes: minutes));
  }

  static String greeting(DateTime now) {
    final h = now.hour;
    if (h < 5) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 21) return 'Good evening';
    return 'Good night';
  }

  static List<DateTime> lastNDays(int n, {DateTime? anchor}) {
    final base = dayOnly(anchor ?? DateTime.now());
    return List.generate(n, (i) => base.subtract(Duration(days: n - 1 - i)));
  }

  static bool isWithinQuietHours({
    required DateTime now,
    required int quietStartMinutes,
    required int quietEndMinutes,
  }) {
    final mins = now.hour * 60 + now.minute;
    if (quietStartMinutes == quietEndMinutes) return false;
    if (quietStartMinutes < quietEndMinutes) {
      // Same-day window, e.g. 13:00 → 15:00
      return mins >= quietStartMinutes && mins < quietEndMinutes;
    }
    // Overnight window, e.g. 22:00 → 07:00
    return mins >= quietStartMinutes || mins < quietEndMinutes;
  }
}
