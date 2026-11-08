import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../content/motivation_content.dart';
import '../../data/models/user_settings.dart';

/// Decides *whether* a reminder should be spoken, *which* line to speak, and
/// *how* to degrade when the phone cannot speak.
///
/// Why this exists (repair R3)
/// ---------------------------
/// Before this file, `VoiceService.speak()` was only ever called from the Voice
/// settings preview and the diagnostics screen. Spoken water reminders were a
/// setting that did nothing: enabling it changed a boolean and no code path
/// consumed it. This is the missing consumer.
///
/// Honest engineering constraints
/// ------------------------------
/// * Text-to-speech is executed **natively** (see
///   `android/.../VoiceReminderScheduler.kt`), not from Dart. `flutter_tts` runs
///   in the Flutter engine, and once Android has terminated the app process no
///   Dart code runs without a foreground service — which is not a proportionate
///   or policy-friendly demand for a water reminder. So:
///
///   | app state                     | what happens                          |
///   |-------------------------------|---------------------------------------|
///   | foreground / backgrounded     | full spoken line via TTS              |
///   | terminated, screen locked     | notification tone only, spoken line in the body text |
///
/// * Speech **never** overrides silent mode or Do Not Disturb. Android would
///   have to be rooted or the user would have to grant notification-policy
///   access for that, and neither is acceptable in a wellness app.
/// * If no TTS engine exists (some budget ROMs ship none, or the user removed
///   it), [speak] returns false and the caller falls back to the notification
///   body. The feature reports itself as unavailable instead of silently doing
///   nothing.
abstract final class SpokenReminders {
  /// Rotates deterministically so the same reminder time always says the same
  /// thing on the same day (a "random" voice that changes on every rebuild is
  /// unsettling), but consecutive reminders differ.
  static String lineFor({
    required DateTime occurrence,
    required int slotMinute,
    List<String> pool = kWaterVoiceLines,
  }) {
    if (pool.isEmpty) return kWaterVoiceLines.first;
    final seed = occurrence.year * 10000 +
        occurrence.month * 100 +
        occurrence.day * 37 +
        slotMinute;
    return pool[seed.abs() % pool.length];
  }

  /// A slightly different line for medicine, so the two never sound identical.
  static String medicineLineFor({
    required DateTime occurrence,
    required int slotMinute,
    String medicineName = 'your medicine',
  }) {
    const pool = [
      'A gentle reminder about your medicine. Only take it if it is due.',
      'It is time to check your medicine, Akasha. No pressure, just care.',
      'A small nudge — your medicine is due about now.',
    ];
    final seed = occurrence.day * 13 + slotMinute + medicineName.length;
    return pool[seed.abs() % pool.length];
  }

  /// Whether TTS should even be attempted for this profile.
  static bool shouldSpeak(VoiceProfile profile) =>
      profile != VoiceProfile.disabled;

  /// Picks a random-but-stable line for the "test voice" button in settings.
  static String previewLine([int seed = 0]) =>
      kWaterVoiceLines[math.Random(seed).nextInt(kWaterVoiceLines.length)];
}
