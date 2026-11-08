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
