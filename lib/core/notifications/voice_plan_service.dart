import 'package:flutter/foundation.dart';

import '../../data/models/user_settings.dart';
import '../../data/models/water_models.dart';
import '../services/system_channel.dart';
import '../utils/date_utils.dart';
import 'spoken_reminders.dart';

/// Pushes the spoken-reminder plan down to Android.
///
/// This is the bridge that makes the "spoken reminders" setting real. Two
/// engines exist on purpose:
///
/// * **Kotlin** ([VoiceReminderScheduler]) speaks at alarm time, including when
///   the app is closed or the phone is locked. This is the one that actually
///   matters for a reminder.
/// * **Dart** ([VoiceService]) speaks inside the app, for the preview button.
///
/// The plan below is therefore *slot definitions*, not occurrences: Kotlin arms
/// the next occurrence of each slot and re-arms itself daily. Sending 16 slots
/// once is enough for months, which keeps the alarm set small and the behaviour
/// predictable.
///
/// If the phone has no TTS engine the plan is cancelled and [VoicePlanResult]
/// says why — an honest "your phone cannot speak" beats a setting that silently
/// does nothing.
class VoicePlanService {
  VoicePlanService(this._channel);

  final SystemChannel _channel;

  /// Builds and sends the plan. Safe to call on every settings change.
  Future<VoicePlanResult> apply({
    required UserSettings settings,
    required List<WaterReminder> reminders,
    required bool waterPaused,
    required bool speechEngineAvailable,
  }) async {
    final voiceProfile = settings.effectiveVoice;
    final shouldSpeak = !waterPaused &&
        SpokenReminders.shouldSpeak(voiceProfile) &&
        speechEngineAvailable;

    if (!shouldSpeak) {
      await _channel.cancelVoicePlan();
      return VoicePlanResult(
        armed: false,
        slotCount: 0,
        reason: waterPaused
            ? 'Water reminders are paused.'
            : voiceProfile == VoiceProfile.disabled
                ? 'Voice is turned off.'
                : 'This phone has no text-to-speech engine installed.',
      );
    }

    final enabled = reminders.where((r) => r.enabled).toList()
      ..sort((a, b) => a.minuteOfDay.compareTo(b.minuteOfDay));

    if (enabled.isEmpty) {
      await _channel.cancelVoicePlan();
      return const VoicePlanResult(
        armed: false,
        slotCount: 0,
        reason: 'No water slots are enabled.',
      );
    }

    final today = AkashaDates.today();
    final plan = <Map<String, Object?>>[];
    for (final reminder in enabled) {
      final slotId = 'water:${reminder.id}';
      plan.add({
        'slotId': slotId,
        'minuteOfDay': reminder.minuteOfDay,
        'text': SpokenReminders.lineFor(
          occurrence: today,
          slotMinute: reminder.minuteOfDay,
        ),
        'voiceKey': voiceProfile.key,
        'pitch': settings.voicePitch,
        'rate': settings.voiceRate,
      });
    }

    final ok = await _channel.applyVoicePlan(plan: plan, enabled: true);
    if (!ok) {
      return const VoicePlanResult(
        armed: false,
        slotCount: 0,
        reason: 'Android did not accept the spoken reminder plan.',
      );
    }
    return VoicePlanResult(
      armed: true,
      slotCount: plan.length,
      reason: '${plan.length} spoken reminders armed.',
    );
  }

  /// Speaks the same line a real reminder would, through the native engine, so
  /// the preview is not a different voice from the reminder.
  Future<void> preview(UserSettings settings, {int minuteOfDay = 540}) async {
    final line = SpokenReminders.lineFor(
      occurrence: AkashaDates.today(),
      slotMinute: minuteOfDay,
    );
    debugPrint('AKASHA voice preview: $line (${settings.effectiveVoice.key})');
    await _channel.speakTest(line);
  }

  Future<bool> isAvailable() => _channel.isSpeechAvailable();

  /// True when Android will suppress audio right now (muted or DND). The
  /// settings screen shows this instead of letting the user think it is broken.
  Future<bool> isSuppressed() => _channel.isSilentOrDnd();
}

/// Outcome of applying the spoken plan, shown verbatim in Voice settings.
class VoicePlanResult {
  const VoicePlanResult({
    required this.armed,
    required this.slotCount,
    required this.reason,
  });

  final bool armed;
  final int slotCount;
  final String reason;

  @override
  String toString() => reason;
}
