/// Stable 32-bit notification ids.
///
/// Android needs an int id per scheduled notification, and it must be STABLE
/// across app restarts — otherwise re-scheduling creates duplicates instead of
/// replacing the existing alarm. Everything is derived deterministically from
/// a string key, and each domain gets its own id range.
abstract final class AkashaNotificationIds {
  static const int waterBase = 100000;
  static const int medicineBase = 300000;
  static const int motivationBase = 500000;
  static const int loveNoteBase = 600000;
  static const int snoozeBase = 700000;
  static const int dailyReport = 800001;

  /// Range for action-button routing (intent payloads), not alarms.
  static const int waterActionNotification = 900001;
  static const int medicineActionNotification = 900002;

  static int water(int minuteOfDay) => waterBase + minuteOfDay;

  /// Medicine schedule notifications are per (medicine, day, minute) so a
  /// weekday-only medicine never fires on the wrong day.
  static int medicine(String medicineId, String dayKey, int minute) =>
      medicineBase + _positiveHash('$medicineId|$dayKey|$minute');

  static int motivation(int minuteOfDay) => motivationBase + minuteOfDay;

  static int loveNote(int minuteOfDay) => loveNoteBase + minuteOfDay;

  static int snooze(String snoozeId) => snoozeBase + _positiveHash(snoozeId);

  /// Deterministic positive hash capped so we stay inside Android's safe range.
  static int _positiveHash(String value) {
    var hash = 0x811C9DC5; // FNV-1a offset basis
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7FFFFFFF;
    }
    // Keep ids inside a 200k band per domain to avoid collisions between
    // domains and to stay far below 2^31.
    return hash % 200000;
  }
}
