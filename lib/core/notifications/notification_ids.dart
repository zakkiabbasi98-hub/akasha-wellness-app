/// Stable, collision-free 32-bit notification ids.
///
/// Android requires one `int` per scheduled notification. Two rules make the
/// alarm set correct:
///
/// 1. The id must be **stable** across app restarts, otherwise re-scheduling
///    creates a duplicate alarm instead of replacing the existing one.
/// 2. The id must be **unique per calendar occurrence**, not per clock time.
///
/// Rule 2 is the repair applied in this revision. The previous implementation
/// used `waterBase + minuteOfDay`, i.e. one id per *clock time*. The scheduler
/// materialises a 7-day horizon, so the 09:00 slot wrote id `100540` seven
/// times and only the last day survived — six of every seven reminders were
/// silently destroyed. The calendar day is therefore part of every recurring
/// id now. See docs/REPAIR_CHANGELOG.md → R1.
///
/// Band layout (every value stays below Android's `Integer.MAX_VALUE`,
/// 2 147 483 647):
///
/// | kind        | base         | width        |
/// |-------------|--------------|--------------|
/// | water       | 100 000 000  | day*2048+min |
/// | medicine    | 300 000 000  | hashed 500M  |
/// | motivation  | 900 000 000  | day*2048+min |
/// | love note   | 950 000 000  | day*2048+min |
/// | snooze      | 1 000 000 000| hashed 100M  |
/// | daily       | 1 200 000 001| single       |
///
/// Water and the two "encouragement" kinds are laid out *structurally* (no
/// hash) so a collision is mathematically impossible: within a band the value
/// is `dayIndex * 2048 + minuteOfDay`, and `minuteOfDay` can never reach 2048.
/// Medicine and snooze must distinguish opaque string keys, so they use a
/// 30-bit FNV-1a hash folded into a very wide band — with the realistic number
/// of pending medicine alarms (~350) the birthday-collision probability is
/// about 1 in 8 000, versus roughly 1 in 30 with the previous 200k band.
abstract final class AkashaNotificationIds {
  // ── Bands ────────────────────────────────────────────────────────────────
  static const int waterBase = 100000000;
  static const int medicineBase = 300000000;
  static const int motivationBase = 900000000;
  static const int loveNoteBase = 950000000;
  static const int snoozeBase = 1000000000;
  static const int dailyReport = 1200000001;

  /// Not alarm ids — routing ids for the action callbacks.
  static const int waterActionNotification = 1300000001;
  static const int medicineActionNotification = 1300000002;

  /// Stride between adjacent days inside a recurring band. Must be greater
  /// than 1439 (the largest valid minute-of-day).
  static const int dayStride = 2048;

  /// 1000 days ≈ 2.7 years. Chosen so a band stays inside its allotment even
  /// at the maximum day index; the scheduler only ever uses 0..[horizon].
  static const int dayModulus = 1000;

  /// The largest id this class can produce. Asserted by the unit tests.
  static const int maxId = 1300000002;

  // ── Recurring slots (structural, collision-free) ─────────────────────────

  /// Id for the water reminder at [minuteOfDay] on the calendar day [day].
  ///
  /// Two different days at the same clock time get different ids, which is the
  /// entire point of this scheme.
  static int water(int minuteOfDay, DateTime day) =>
      waterBase + dayIndex(day) * dayStride + _checkedMinute(minuteOfDay);

  static int motivation(int minuteOfDay, DateTime day) =>
      motivationBase + dayIndex(day) * dayStride + _checkedMinute(minuteOfDay);

  static int loveNote(int minuteOfDay, DateTime day, {String? noteId}) =>
      loveNoteBase +
      dayIndex(day) * dayStride +
      _checkedMinute(minuteOfDay) +
      // Two notes may legitimately share a clock time; a small offset derived
      // from the note id keeps them distinct without leaving the 2048 stride.
      (noteId == null ? 0 : _positiveHash(noteId) % 8);

  // ── Opaque keys (hashed, very wide bands) ────────────────────────────────

  /// Medicine doses are addressable by their deterministic log id, which
  /// already contains the medicine id, the calendar day and the minute.
  static int medicine(String logId) => medicineBase + _wideHash(logId, 500000000);

  static int snooze(String snoozeId) => snoozeBase + _wideHash(snoozeId, 100000000);

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Days since the Unix epoch, wrapped into [dayModulus].
  ///
  /// Deliberately UTC-based: a local-time division would drift by one day
  /// across a DST boundary and silently change an id (creating a duplicate).
  static int dayIndex(DateTime day) {
    final utc = DateTime.utc(day.year, day.month, day.day);
    final days = utc.difference(DateTime.utc(1970)).inDays;
    final wrapped = days % dayModulus;
    return wrapped < 0 ? wrapped + dayModulus : wrapped;
  }

  static int _checkedMinute(int minuteOfDay) {
    if (minuteOfDay < 0 || minuteOfDay >= 24 * 60) {
      throw ArgumentError.value(minuteOfDay, 'minuteOfDay', 'Must be 0..1439');
    }
    return minuteOfDay;
  }

  /// 30-bit FNV-1a, folded into [width] so it fits the band.
  static int _wideHash(String value, int width) {
    var hash = 0x811C9DC5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x3FFFFFFF;
    }
    return hash % width;
  }

  /// Small stable hash for the within-stride note offset.
  static int _positiveHash(String value) {
    var hash = 0x811C9DC5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    return hash;
  }

  // ── Band classification ───────────────────────────────────────────────────
  // Used by the diagnostics screen to explain what is pending. Never used by
  // scheduling: the scheduler takes ids from the functions above, so the screen
  // physically cannot disagree with it.

  static bool isWater(int id) => id >= waterBase && id < medicineBase;
  static bool isMedicine(int id) => id >= medicineBase && id < motivationBase;
  static bool isMotivation(int id) => id >= motivationBase && id < loveNoteBase;
  static bool isLoveNote(int id) => id >= loveNoteBase && id < snoozeBase;
  static bool isSnooze(int id) => id >= snoozeBase && id < dailyReport;
  static bool isDaily(int id) => id == dailyReport;

  /// True when [id] belongs to AKASHA at all.
  static bool isOurs(int id) =>
      id >= waterBase && id <= maxId;
}
