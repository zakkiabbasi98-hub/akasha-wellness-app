import 'package:akasha/features/ai_companion/ai_service.dart';
import 'package:akasha/features/sync/cloud_backend.dart';
import 'package:akasha/features/sync/conflict_rules.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pure-logic tests for the pieces of the sync and AI layers that do not need
/// a database or a network.
void main() {
  group('conflict resolution rule (last writer wins, newest data protected)', () {
    // The rule under test is the SAME implementation SyncService._pullAndMerge
    // calls — not a copy — so this suite fails if the real merge logic drifts.
    bool shouldReplaceLocal({
      required int localUpdatedAt,
      required bool localDirty,
      required int remoteUpdatedAt,
    }) =>
        SyncConflictRules.shouldReplaceLocal(
          localUpdatedAt: localUpdatedAt,
          localDirty: localDirty,
          remoteUpdatedAt: remoteUpdatedAt,
        );

    test('clean local row accepts the newer cloud row', () {
      expect(
        shouldReplaceLocal(
          localUpdatedAt: 1000,
          localDirty: false,
          remoteUpdatedAt: 900,
        ),
        isTrue,
      );
    });

    test('a newer local change is never overwritten by an older cloud row', () {
      expect(
        shouldReplaceLocal(
          localUpdatedAt: 2000,
          localDirty: true,
          remoteUpdatedAt: 1500,
        ),
        isFalse,
      );
    });

    test('a newer cloud row wins over an older dirty local row', () {
      expect(
        shouldReplaceLocal(
          localUpdatedAt: 1000,
          localDirty: true,
          remoteUpdatedAt: 2000,
        ),
        isTrue,
      );
    });

    test('equal timestamps keep the local dirty row for re-upload', () {
      expect(
        shouldReplaceLocal(
          localUpdatedAt: 1500,
          localDirty: true,
          remoteUpdatedAt: 1500,
        ),
        isFalse,
      );
      expect(
        SyncConflictRules.shouldRequeueLocal(
          localUpdatedAt: 1500,
          localDirty: true,
          remoteUpdatedAt: 1500,
        ),
        isTrue,
      );
    });

    test('a pushed row is not requeued', () {
      expect(
        SyncConflictRules.shouldRequeueLocal(
          localUpdatedAt: 10,
          localDirty: false,
          remoteUpdatedAt: 99,
        ),
        isFalse,
      );
    });

    test('a tombstone is recognised by its deleted_at column', () {
      expect(SyncConflictRules.isDeleted({'deleted_at': 123}), isTrue);
      expect(SyncConflictRules.isDeleted({'deleted_at': null}), isFalse);
      expect(SyncConflictRules.isDeleted({}), isFalse);
    });
  });

  group('LocalOnlyBackend keeps the app offline-safe', () {
    const backend = LocalOnlyBackend();

    test('is never "available", so sync short-circuits', () {
      expect(backend.isAvailable, isFalse);
      expect(backend.currentUserId, isNull);
    });

    test('auth attempts return a friendly, non-throwing failure', () async {
      final result = await backend.signInWithEmail('a@b.com', 'password');
      expect(result.success, isFalse);
      expect(result.error, isNotNull);
    });

    test('pull returns no records', () async {
      expect(await backend.pull(), isEmpty);
    });
  });

  group('AI safety detection', () {
    test('ordinary sadness is not flagged as crisis', () {
      expect(AiCompanionService.detectSafety('I feel sad today'), SafetyFlag.none);
      expect(
        AiCompanionService.detectSafety('I am overthinking a conversation'),
        SafetyFlag.none,
      );
    });

    test('explicit self-harm language is flagged immediately', () {
      expect(
        AiCompanionService.detectSafety('I want to die'),
        SafetyFlag.crisis,
      );
      expect(
        AiCompanionService.detectSafety('I have been thinking about suicide'),
        SafetyFlag.crisis,
      );
      expect(
        AiCompanionService.detectSafety('I want to hurt myself'),
        SafetyFlag.crisis,
      );
    });

    test('the local fallback never claims to be a therapist', () {
      final service = AiCompanionService();
      expect(service.isConfigured, isFalse, reason: 'no endpoint in tests');
      final reply = service.localReflection('I am so anxious about tomorrow');
      expect(reply.toLowerCase(), isNot(contains('diagnos')));
      expect(reply.toLowerCase(), isNot(contains('i am a therapist')));
      expect(reply, isNotEmpty);
    });

    test('a crisis message always returns real-world support guidance', () async {
      final service = AiCompanionService();
      final reply = await service.send(
        message: 'I want to die',
        history: const [],
      );
      expect(reply.isCrisis, isTrue);
      expect(reply.text, contains('real person'));
    });

    test('reflective fallback responds differently to different feelings', () {
      final service = AiCompanionService();
      final anxious = service.localReflection('I am anxious');
      final tired = service.localReflection('I am exhausted');
      expect(anxious, isNot(equals(tired)));
    });
  });
}
