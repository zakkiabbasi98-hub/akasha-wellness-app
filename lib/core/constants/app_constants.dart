/// App-wide constants. Numbers that the spec pins down live here so tests can
/// assert on the same values the UI uses.
abstract final class AppConstants {
  static const String appName = 'AKASHA';
  static const String tagline = 'Hydrate • Smile • Shine';
  static const String ownerDefaultName = 'Akasha';

  // ── Water defaults (spec §6) ────────────────────────────────────────────
  /// 09:00 in minutes from midnight.
  static const int defaultWaterStartMinute = 9 * 60;

  /// 12:00 AM — midnight. Represented as 0 and treated INCLUSIVELY as the end
  /// of the waking window, which is why the generator walks wrap-around.
  static const int defaultWaterEndMinute = 0;

  static const int defaultWaterIntervalMinutes = 60;
  static const int defaultWaterTargetMl = 2000;
  static const int defaultGlassMl = 250;
  static const int smallGlassMl = 150;
  static const int largeGlassMl = 350;
  static const int defaultSnoozeMinutes = 15;

  /// Number of slots the default schedule must produce (09:00 → 12:00 AM).
  static const int expectedDefaultWaterSlots = 16;

  // ── Quiet hours defaults ────────────────────────────────────────────────
  static const int defaultQuietStartMinute = 22 * 60 + 30; // 22:30
  static const int defaultQuietEndMinute = 7 * 60; // 07:00

  // ── Medicine example times (NOT medical advice) ─────────────────────────
  static const int exampleMorningMinute = 8 * 60;
  static const int exampleAfternoonMinute = 14 * 60;
  static const int exampleNightMinute = 21 * 60;

  // ── Notification plumbing ───────────────────────────────────────────────
  static const String channelWater = 'akasha_water_reminders';
  static const String channelMedicine = 'akasha_medicine_reminders';
  static const String channelMotivation = 'akasha_motivation';
  static const String channelLoveNotes = 'akasha_love_notes';
  static const String channelDaily = 'akasha_daily_report';

  // Notification id bands live in exactly one place:
  // lib/core/notifications/notification_ids.dart. They used to be duplicated
  // here with different values, which is a classic way to schedule the same
  // reminder under two ids. Do not reintroduce them.

  /// How far ahead the scheduler materialises notifications.
  ///
  /// 5 days (not 7) because the alarm budget is finite and medicine dominates
  /// it: 4 medicines x 3 times x 5 days = 60 medicine alarms, plus 16 water
  /// slots x 5 days = 80. A 7-day horizon blew past [maxPendingAlarms] for a
  /// user with several medicines, and Android silently drops the overflow.
  static const int scheduleHorizonDays = 5;

  /// Hard ceiling on simultaneously registered alarms. Android's own limit is
  /// around 500; behaviour degrades well before that on OEM builds, so the app
  /// stays materially below it and reports a warning above 400.
  static const int maxPendingAlarms = 400;

  // ── Misc ────────────────────────────────────────────────────────────────
  static const int motivationPoolTarget = 100; // >=100 original messages
  static const int journalMaxLength = 20000;
  static const int reflectionMaxLength = 4000;

  static const List<String> medicineCategories = [
    'morning',
    'afternoon',
    'night',
    'custom',
  ];

  static const List<String> weekdaysShort = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
}
