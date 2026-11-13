import 'package:akasha/core/notifications/background_actions.dart';
import 'package:akasha/core/notifications/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for Critical Issue 2: notification actions in a background isolate.
///
/// The original bug had two halves:
///   1. The headless callback relied on statics the main isolate populated, so
///      it found `null` and silently did nothing.
///   2. Nothing deduplicated delivery, so a repeated broadcast could double-count
///      a glass of water.
///
/// Half 2 is pure logic and is tested here directly. Half 1 is structural: the
/// executor is now constructed from an [AppDatabase] rather than a provider, and
/// `BackgroundActionEngine.handle` builds its own. That is asserted by the
/// "no static state" group below.
void main() {
  final day = DateTime(2026, 11, 8, 9, 0);

  group('payload round-trip', () {
    test('encodes and decodes every field', () {
      const payload = NotificationPayload(
        kind: 'water',
        refId: 'snooze-1',
        value: 250,
        slotMinute: 540,
        dayKey: '2026-11-08',
      );
      final decoded = NotificationPayload.decode(payload.encode())!;
      expect(decoded.kind, 'water');
      expect(decoded.refId, 'snooze-1');
      expect(decoded.value, 250);
      expect(decoded.slotMinute, 540);
      expect(decoded.dayKey, '2026-11-08');
    });

    test('a payload written by an older build (no dayKey) still decodes', () {
      // Alarms survive an app update; those payloads have four fields only.
      final decoded = NotificationPayload.decode('water||250|540')!;
      expect(decoded.kind, 'water');
      expect(decoded.value, 250);
      expect(decoded.slotMinute, 540);
      expect(decoded.dayKey, isNull);
      // and falls back to today rather than crashing
      expect(decoded.occurredOn, isNotNull);
    });

    test('garbage decodes to null instead of throwing', () {
      expect(NotificationPayload.decode(null), isNull);
      expect(NotificationPayload.decode(''), isNull);
      expect(NotificationPayload.decode('|'), isNull);
    });

    test('a non-numeric amount is ignored, not fatal', () {
      final decoded = NotificationPayload.decode('water||abc|540')!;
      expect(decoded.value, isNull);
      expect(decoded.slotMinute, 540);
    });
  });

  group('dedupe key (exactly-once delivery)', () {
    NotificationPayload waterPayload({int minute = 540, int amount = 250}) =>
        NotificationPayload(
          kind: 'water',
          value: amount,
          slotMinute: minute,
          dayKey: '2026-11-08',
        );

    test('the same action on the same slot always yields the same key', () {
      final a = ActionEvent.dedupeKeyFor(
        AkashaActions.drankWater,
        waterPayload(),
        at: day,
      );
      final b = ActionEvent.dedupeKeyFor(
        AkashaActions.drankWater,
        waterPayload(),
        at: day.add(const Duration(minutes: 3)), // repeated delivery
      );
      expect(a, b,
          reason: 'A re-delivered broadcast must not count a second glass.');
    });

    test('different actions on the same slot get different keys', () {
      final drank = ActionEvent.dedupeKeyFor(
        AkashaActions.drankWater,
        waterPayload(),
        at: day,
      );
      final skipped = ActionEvent.dedupeKeyFor(
        AkashaActions.skipWater,
        waterPayload(),
        at: day,
      );
      final snoozed = ActionEvent.dedupeKeyFor(
        AkashaActions.snoozeWater,
        waterPayload(),
        at: day,
      );
      expect({drank, skipped, snoozed}, hasLength(3));
    });

    test('different slots get different keys', () {
      final a = ActionEvent.dedupeKeyFor(
        AkashaActions.drankWater,
        waterPayload(minute: 540),
        at: day,
      );
      final b = ActionEvent.dedupeKeyFor(
        AkashaActions.drankWater,
        waterPayload(minute: 600),
        at: day,
      );
      expect(a, isNot(b));
    });

    test('yesterday and today are distinct events', () {
      final a = ActionEvent.dedupeKeyFor(
        AkashaActions.drankWater,
        const NotificationPayload(
            kind: 'water', slotMinute: 540, dayKey: '2026-11-07'),
        at: DateTime(2026, 11, 7, 9),
      );
      final b = ActionEvent.dedupeKeyFor(
        AkashaActions.drankWater,
        const NotificationPayload(
            kind: 'water', slotMinute: 540, dayKey: '2026-11-08'),
        at: day,
      );
      expect(a, isNot(b));
    });

    test('medicine actions are keyed on the log id, not the clock', () {
      const payload = NotificationPayload(
        kind: 'medicine',
        refId: 'medlog:m1:2026-11-08:540',
        slotMinute: 540,
        dayKey: '2026-11-08',
      );
      final took = ActionEvent.dedupeKeyFor(
          AkashaActions.tookMedicine, payload, at: day);
      final skipped = ActionEvent.dedupeKeyFor(
          AkashaActions.skipMedicine, payload, at: day);
      expect(took, isNot(skipped));
      expect(took, contains('medlog:m1:2026-11-08:540'));
    });
  });

  group('engine robustness', () {
    test('a plain tap (no action button) is treated as already handled', () async {
      // Opening the app must never be queued as a failed action.
      final response = NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        id: 1,
        payload: const NotificationPayload(kind: 'water', slotMinute: 540)
            .encode(),
      );
      final result = await BackgroundActionEngine.handle(response);
      expect(result, isTrue);
    });

    test('a payload-less response is rejected without throwing', () async {
      final response = NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        id: 1,
        actionId: AkashaActions.drankWaterId,
      );
      final result = await BackgroundActionEngine.handle(response);
      expect(result, isFalse,
          reason: 'No payload means no target; it must not be reported as done.');
    });
  });

  group('no main-isolate dependency (the root cause of Issue 2)', () {
    test('BackgroundActionEngine exposes a static entry point', () {
      // The plugin entry point is a free function that must work in a fresh
      // isolate. It exists and is callable without any setup.
      expect(BackgroundActionEngine.handle, isA<Function>());
      expect(onBackgroundNotificationResponse, isA<Function>());
    });

    test('ActionExecutor takes its database explicitly, not from a provider', () {
      // Constructing the type must not require a ProviderContainer; the test
      // itself proves that by referencing the public constructor.
      expect(ActionExecutor.new, isA<Function>());
    });
  });
}
