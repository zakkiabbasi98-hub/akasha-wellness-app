import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Optional biometric app lock.
///
/// Nothing here records, stores, or transmits biometric data — the OS does all
/// of that. The app only asks "is this the device owner?" and remembers the
/// answer until it is backgrounded for longer than [_graceSeconds].
class LockService {
  LockService();

  final LocalAuthentication _auth = LocalAuthentication();
  DateTime? _lastUnlockedAt;

  /// Short grace period so switching apps for a few seconds to copy something
  /// does not force a re-scan every time.
  static const int _graceSeconds = 120;

  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final supported = await _auth.isDeviceSupported();
      return canCheck && supported;
    } catch (e) {
      debugPrint('AKASHA: biometric check failed: $e');
      return false;
    }
  }

  Future<List<BiometricType>> availableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> authenticate({String reason = 'Unlock AKASHA'}) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false, // allow device PIN/pattern as a fallback
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (ok) _lastUnlockedAt = DateTime.now();
      return ok;
    } catch (e) {
      debugPrint('AKASHA: authenticate failed: $e');
      return false;
    }
  }

  bool get isWithinGrace {
    final last = _lastUnlockedAt;
    if (last == null) return false;
    return DateTime.now().difference(last).inSeconds < _graceSeconds;
  }

  void markUnlocked() => _lastUnlockedAt = DateTime.now();

  /// Called when the app goes to the background so the next resume re-locks.
  void clearGrace() => _lastUnlockedAt = null;
}
