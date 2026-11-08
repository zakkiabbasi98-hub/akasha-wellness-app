import 'dart:async';

import 'package:flutter/foundation.dart';

/// Contract the sync engine talks to.
///
/// Two implementations exist:
///  * [LocalOnlyBackend] — used when Firebase is not configured. Every call is
///    a no-op, so the whole app (and all its tests) run offline forever.
///  * [FirestoreBackend] — the optional real backend (see firebase_backend.dart).
///
/// Keeping this interface tiny means the sync engine is testable without any
/// Firebase dependency, and the offline guarantee is structural rather than a
/// promise.
abstract interface class CloudBackend {
  bool get isAvailable;

  String? get currentUserId;

  Future<CloudAuthResult> signInWithEmail(String email, String password);

  Future<CloudAuthResult> signUpWithEmail(String email, String password);

  Future<void> signOut();

  /// Uploads one record. Implementations must be idempotent: sending the same
  /// record twice with the same updatedAt leaves the cloud unchanged.
  Future<void> upsert({
    required String entity,
    required String entityId,
    required Map<String, Object?> data,
    required DateTime updatedAt,
  });

  Future<void> remove({
    required String entity,
    required String entityId,
  });

  /// Pulls everything newer than [since]. Returns per-entity rows.
  Future<Map<String, List<Map<String, Object?>>>> pull({DateTime? since});

  Future<void> deleteAccount();
}

class CloudAuthResult {
  const CloudAuthResult({required this.success, this.userId, this.email, this.error});

  final bool success;
  final String? userId;
  final String? email;
  final String? error;

  static const unavailable = CloudAuthResult(
    success: false,
    error: 'Cloud sync is not configured in this build.',
  );
}

/// Default backend: the app is complete and fully functional with this one.
class LocalOnlyBackend implements CloudBackend {
  const LocalOnlyBackend();

  @override
  bool get isAvailable => false;

  @override
  String? get currentUserId => null;

  @override
  Future<CloudAuthResult> signInWithEmail(String email, String password) async =>
      CloudAuthResult.unavailable;

  @override
  Future<CloudAuthResult> signUpWithEmail(String email, String password) async =>
      CloudAuthResult.unavailable;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> upsert({
    required String entity,
    required String entityId,
    required Map<String, Object?> data,
    required DateTime updatedAt,
  }) async {
    debugPrint('AKASHA sync (local-only backend): dropping upsert for $entity/$entityId');
  }

  @override
  Future<void> remove({required String entity, required String entityId}) async {}

  @override
  Future<Map<String, List<Map<String, Object?>>>> pull({DateTime? since}) async => const {};

  @override
  Future<void> deleteAccount() async {}
}
