import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the small Kotlin MethodChannel in MainActivity.
///
/// All calls are read-only queries about what the OS currently permits, plus
/// deep links into official settings screens. Nothing here tries to bypass Do
/// Not Disturb, silent mode, or force-stop — those are Android's rules.
class SystemChannel {
  const SystemChannel();

  static const MethodChannel _channel = MethodChannel('com.akasha.wellness/system');

  Future<bool> canScheduleExactAlarms() async {
    try {
      return await _channel.invokeMethod<bool>('canScheduleExactAlarms') ?? false;
    } on PlatformException catch (e) {
      debugPrint('canScheduleExactAlarms failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> openExactAlarmSettings() => _safe('openExactAlarmSettings');

  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> openBatteryOptimizationSettings() =>
      _safe('openBatteryOptimizationSettings');

  Future<bool> isNotificationPolicyAccessGranted() async {
    try {
      return await _channel.invokeMethod<bool>('isNotificationPolicyAccessGranted') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> isDndActive() async {
    try {
      return await _channel.invokeMethod<bool>('isDndActive') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> openNotificationSettings() => _safe('openNotificationSettings');

  Future<void> openAppSettings() => _safe('openAppSettings');

  /// Returns the time of the last native clock/timezone change that has not
  /// been handled yet (epoch millis), or `null` if there is nothing pending.
  ///
  /// The native receiver in `TimeChangeReceiver.kt` cannot talk to Dart (it
  /// never spins up a FlutterEngine), so it drops a marker in SharedPreferences.
  /// This call both reads and clears that marker, which is what makes the
  /// reschedule exactly-once.
  Future<int?> consumeRescheduleRequest() async {
    try {
      return await _channel.invokeMethod<int>('consumeRescheduleRequest');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  // ── Native spoken reminders (repair R3) ──────────────────────────────────
  //
  // Speech is executed by Kotlin, not Dart, because flutter_tts cannot run once
  // Android has terminated the Flutter engine. Dart owns the *plan*; Kotlin owns
  // the *audio*. See docs/NOTIFICATIONS.md → "Spoken reminders".

  /// Hands the whole spoken plan to Android. Replaces any previous plan.
  ///
  /// [plan] is a list of `{slotId, minuteOfDay, text, voiceKey, pitch, rate}`.
  Future<bool> applyVoicePlan({
    required List<Map<String, Object?>> plan,
    required bool enabled,
  }) async {
    try {
      final encoded = jsonEncode(plan);
      await _channel.invokeMethod<void>('applyVoicePlan', {
        'plan': encoded,
        'enabled': enabled,
      });
      return true;
    } on PlatformException catch (e) {
      debugPrint('applyVoicePlan failed: ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> cancelVoicePlan() => _safe('cancelVoicePlan');

  /// False when the phone has no TTS engine at all — the voice settings screen
  /// uses this to explain why speech will not happen instead of pretending.
  Future<bool> isSpeechAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isSpeechAvailable') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Speaks a preview through the native engine (so the preview sounds exactly
  /// like a real reminder).
  Future<void> speakTest(String text) async {
    try {
      await _channel.invokeMethod<void>('speakTest', {'text': text});
    } on PlatformException catch (e) {
      debugPrint('speakTest failed: ${e.message}');
    } on MissingPluginException {
    }
  }

  /// True when the phone is muted or in Do Not Disturb — speech will be
  /// suppressed by Android and the app should say so rather than look broken.
  Future<bool> isSilentOrDnd() async {
    try {
      return await _channel.invokeMethod<bool>('isSilentOrDnd') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<int> deviceSdkInt() async {
    try {
      return await _channel.invokeMethod<int>('deviceSdkInt') ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  Future<void> _safe(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException catch (e) {
      debugPrint('$method failed: ${e.message}');
    } on MissingPluginException {
      // Running on a non-Android host (widget tests / desktop) — no-op.
    }
  }
}
