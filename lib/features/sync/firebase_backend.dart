import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'cloud_backend.dart';

/// Optional real backend on Firebase Auth + Cloud Firestore.
///
/// IMPORTANT — this file is only ever constructed when Firebase has been
/// configured (see docs/FIREBASE_SETUP.md). The app imports it lazily from
/// main.dart inside a try/catch, so a build *without* google-services.json and
/// without firebase_options.dart still compiles and runs perfectly offline.
///
/// Data model
/// ----------
///   users/{uid}                       → profile document
///   users/{uid}/{entity}/{recordId}   → one document per synced record
///
/// Security rules (firebase/firestore.rules) restrict every path to the
/// authenticated owner, so one account can never read another's records.
class FirestoreBackend implements CloudBackend {
  FirestoreBackend._(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  static bool _initialised = false;

  /// Returns null when Firebase is not configured — callers then fall back to
  /// [LocalOnlyBackend].
  static Future<FirestoreBackend?> tryCreate() async {
    try {
      if (!_initialised) {
        await Firebase.initializeApp();
        _initialised = true;
      }
      final auth = FirebaseAuth.instance;
      final firestore = FirebaseFirestore.instance;
      // Cache-first settings keep reads working offline too.
      firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      return FirestoreBackend._(auth, firestore);
    } catch (e) {
      debugPrint('AKASHA: Firebase not configured ($e). Continuing offline-only.');
      return null;
    }
  }

  @override
  bool get isAvailable => true;

  @override
  String? get currentUserId => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> get _root =>
      _firestore.collection('users');

  @override
  Future<CloudAuthResult> signInWithEmail(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      return CloudAuthResult(
        success: true,
        userId: cred.user?.uid,
        email: cred.user?.email,
      );
    } on FirebaseAuthException catch (e) {
      return CloudAuthResult(success: false, error: _friendlyAuthError(e.code));
    } catch (e) {
      return CloudAuthResult(success: false, error: 'Could not sign in. Please try again.');
    }
  }

  @override
  Future<CloudAuthResult> signUpWithEmail(String email, String password) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final uid = cred.user?.uid;
      if (uid != null) {
        await _root.doc(uid).set({
          'email': cred.user?.email,
          'created_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      return CloudAuthResult(success: true, userId: uid, email: cred.user?.email);
    } on FirebaseAuthException catch (e) {
      return CloudAuthResult(success: false, error: _friendlyAuthError(e.code));
    } catch (e) {
      return CloudAuthResult(success: false, error: 'Could not create the account.');
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> upsert({
    required String entity,
    required String entityId,
    required Map<String, Object?> data,
    required DateTime updatedAt,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');

    // Firestore rejects nested nulls/unsupported types in some fields, so the
    // row is normalised to JSON-safe primitives.
    final sanitised = <String, dynamic>{};
    data.forEach((key, value) {
      sanitised[key] = switch (value) {
        null => null,
        bool() || num() || String() => value,
        DateTime() => (value).millisecondsSinceEpoch,
        _ => value.toString(),
      };
    });
    sanitised['updated_at'] = updatedAt.millisecondsSinceEpoch;
    sanitised['server_updated_at'] = FieldValue.serverTimestamp();

    // Deterministic doc id = idempotent upsert (no duplicates on retry).
    await _root
        .doc(uid)
        .collection(entity)
        .doc(entityId)
        .set(sanitised, SetOptions(merge: true));
  }

  @override
  Future<void> remove({required String entity, required String entityId}) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');
    await _root.doc(uid).collection(entity).doc(entityId).delete();
  }

  @override
  Future<Map<String, List<Map<String, Object?>>>> pull({DateTime? since}) async {
    final uid = currentUserId;
    if (uid == null) throw StateError('Not signed in');

    final result = <String, List<Map<String, Object?>>>{};
    for (final entity in _entities) {
      Query<Map<String, dynamic>> query = _root.doc(uid).collection(entity);
      if (since != null) {
        query = query.where(
          'updated_at',
          isGreaterThan: since.millisecondsSinceEpoch,
        );
      }
      final snapshot = await query.get(const GetOptions(source: Source.serverAndCache));
      result[entity] = snapshot.docs
          .map((doc) => <String, Object?>{...doc.data(), 'id': doc.id})
          .toList();
    }
    return result;
  }

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final uid = user.uid;
    // Delete every synced collection, then the profile doc, then the account.
    for (final entity in _entities) {
      final docs = await _root.doc(uid).collection(entity).limit(400).get();
      final batch = _firestore.batch();
      for (final doc in docs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
    await _root.doc(uid).delete();
    await user.delete();
  }

  static const List<String> _entities = [
    'water_logs',
    'water_reminders',
    'medicines',
    'medicine_logs',
    'mood_entries',
    'journal_entries',
    'gratitude_entries',
    'breathing_sessions',
    'reflections',
    'love_notes',
  ];

  String _friendlyAuthError(String code) => switch (code) {
        'user-not-found' => 'No account found with that email.',
        'wrong-password' => 'That password does not match.',
        'invalid-email' => 'That email address does not look right.',
        'email-already-in-use' => 'There is already an account with that email.',
        'weak-password' => 'Please choose a stronger password (6+ characters).',
        'network-request-failed' => 'No internet right now. Your data stays safe offline.',
        'too-many-requests' => 'Too many attempts. Please try again in a little while.',
        _ => 'Something went wrong. Please try again.',
      };
}
