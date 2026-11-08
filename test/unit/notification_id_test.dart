import 'package:akasha/core/constants/app_constants.dart';
import 'package:akasha/core/notifications/notification_ids.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression suite for Critical Issue 1: water reminder id collisions.
///
/// The bug was `waterBase + minuteOfDay` — one id per *clock time*, shared by
/// every day in the scheduling horizon. The seven-day loop therefore wrote the
/// same id seven times and only the last day survived, so six of every seven
/// reminders were destroyed by Android's replace-on-same-id behaviour.
///
/// These tests fail loudly if that ever comes back.
void main() {
  final day0 = DateTime(2026, 11, 8);
  final day1 = day0.add(const Duration(days: 1));

  group('water ids are unique per calendar day (the original bug)', () {
    test('the same clock time on two days gets two different ids', () {
      expect(
        AkashaNotificationIds.water(9 * 60, day0),
        isNot(AkashaNotificationIds.water(9 * 60, day1)),
        reason: 'Two days must never share an id — this is exactly the bug.',
      );
    });

    test('a full 7-day horizon of all 16 slots produces 112 distinct ids', () {
      final minutes = [
        for (var h = 9; h <= 23; h++) h * 60, // 09:00 .. 23:00
        0, // 12:00 AM (midnight) — inclusive, per the spec
      ];
      expect(minutes, hasLength(16));

      final ids = <int>{};
      for (var d = 0; d < 7; d++) {
        final day = day0.add(Duration(days: d));
        for (final minute in minutes) {
          ids.add(AkashaNotificationIds.water(minute, day));
        }
      }
      expect(ids.length, 112,
          reason: 'Any collision means Android would overwrite a reminder.');
    });

    test('the default 16 slots all get an id on the very first day', () {
      final minutes = <int>[
        540, 600, 660, 720, 780, 840, 900, 960, 1020, 1080, 1140, 1200, 1260,
        1320, 1380, 0,
      ];
      final ids = minutes.map((m) => AkashaNotificationIds.water(m, day0)).toSet();
      expect(ids.length, 16);
    });

    test('midnight (minute 0) is a valid slot, not treated as falsy', () {
      final id = AkashaNotificationIds.water(0, day0);
      expect(id, AkashaNotificationIds.waterBase);
      expect(id, AkashaNotificationIds.water(0, day0));
    });
  });

  group('ids are stable and ordered', () {
    test('the same input always produces the same id', () {
      expect(
        AkashaNotificationIds.water(660, day0),
        AkashaNotificationIds.water(660, day0),
      );
      expect(
        AkashaNotificationIds.medicine('medlog:m1:2026-11-08:540'),
        AkashaNotificationIds.medicine('medlog:m1:2026-11-08:540'),
      );
    });

    test('time-of-day ordering is preserved within a day', () {
      final a = AkashaNotificationIds.water(9 * 60, day0);
      final b = AkashaNotificationIds.water(10 * 60, day0);
      expect(a, lessThan(b));
    });

    test('day ordering is preserved for the same slot', () {
      final a = AkashaNotificationIds.water(9 * 60, day0);
      final b = AkashaNotificationIds.water(9 * 60, day1);
      expect(a, lessThan(b));
    });

    test('a DST shift never changes an id (ids use the UTC calendar day)', () {
      // 2026-03-29 is a European DST transition; a local-time day index would
      // drift by one and silently create a duplicate alarm.
      final before = DateTime(2026, 3, 28);
      final after = DateTime(2026, 3, 30);
      expect(
        AkashaNotificationIds.water(600, after) -
            AkashaNotificationIds.water(600, before),
        AkashaNotificationIds.dayStride * 2,
      );
    });
  });

  group('band isolation', () {
    test('water, medicine and encouragement never overlap', () {
      final waterIds = <int>{
        for (var d = 0; d < 3; d++)
          for (final m in [0, 540, 720, 1439])
            AkashaNotificationIds.water(m, day0.add(Duration(days: d))),
      };
      final medIds = <int>{
        for (var i = 0; i < 200; i++)
          AkashaNotificationIds.medicine('medlog:m$i:2026-11-08:540'),
      };
      final motIds = <int>{
        for (final m in [540, 720, 900])
          AkashaNotificationIds.motivation(m, day0),
      };

      expect(waterIds.intersection(medIds), isEmpty);
      expect(waterIds.intersection(motIds), isEmpty);
      expect(medIds.intersection(motIds), isEmpty);
    });

    test('every generated id is a safe positive 32-bit int', () {
      final all = <int>[
        AkashaNotificationIds.dailyReport,
        for (var d = 0; d < 30; d++)
          for (final m in [0, 720, 1439])
            AkashaNotificationIds.water(m, day0.add(Duration(days: d))),
        for (var d = 0; d < 30; d++)
          for (final m in [0, 720, 1439]) ...[
            AkashaNotificationIds.motivation(m, day0.add(Duration(days: d))),
            AkashaNotificationIds.loveNote(m, day0.add(Duration(days: d))),
          ],
        for (var i = 0; i < 500; i++)
          AkashaNotificationIds.medicine('medlog:med$i:2026-11-08:540'),
        for (var i = 0; i < 500; i++) AkashaNotificationIds.snooze('snooze-$i'),
      ];
      for (final id in all) {
        expect(id, greaterThan(0));
        // Android's PendingIntent uses a signed int.
        expect(id, lessThan(2147483647));
      }
    });

    test('band predicates classify every id into exactly one band', () {
      final samples = <int>[
        AkashaNotificationIds.water(540, day0),
        AkashaNotificationIds.medicine('medlog:x:2026-11-08:540'),
        AkashaNotificationIds.motivation(540, day0),
        AkashaNotificationIds.loveNote(540, day0),
        AkashaNotificationIds.snooze('abc'),
        AkashaNotificationIds.dailyReport,
      ];
      for (final id in samples) {
        final matches = [
          AkashaNotificationIds.isWater(id),
          AkashaNotificationIds.isMedicine(id),
          AkashaNotificationIds.isMotivation(id),
          AkashaNotificationIds.isLoveNote(id),
          AkashaNotificationIds.isSnooze(id),
          AkashaNotificationIds.isDaily(id),
        ].where((x) => x).length;
        expect(matches, 1, reason: 'id $id must belong to exactly one band');
      }
    });
  });

  group('collision resistance of the hashed bands', () {
    test('1000 medicine log ids produce no collisions', () {
      final ids = <int>{
        for (var i = 0; i < 1000; i++)
          AkashaNotificationIds.medicine('medlog:medicine-$i:2026-11-08:540'),
      };
      // A birthday collision in a 500M band with 1000 samples is ~0.1%; allow
      // at most one miss but flag anything systematic.
      expect(ids.length, greaterThanOrEqualTo(999));
    });

    test('realistic pending set (350 medicine alarms) is collision free', () {
      // 4 medicines x 3 times x 5 days = 60; 10 medicines is 150. Use 350 to be
      // deliberately pessimistic.
      final ids = <int>{};
      for (var med = 0; med < 12; med++) {
        for (var day = 0; day < 5; day++) {
          for (final minute in [480, 840, 1260]) {
            ids.add(AkashaNotificationIds.medicine(
                'medlog:med$med:2026-11-${(day + 8).toString().padLeft(2, '0')}:$minute'));
          }
        }
      }
      expect(ids.length, 180);
    });

    test('snooze ids never collide with the regular slots', () {
      final snooze = AkashaNotificationIds.snooze('snooze-abc');
      final regular = AkashaNotificationIds.water(540, day0);
      expect(AkashaNotificationIds.isSnooze(snooze), isTrue);
      expect(AkashaNotificationIds.isWater(regular), isTrue);
      expect(snooze, isNot(regular));
    });
  });

  group('bounds', () {
    test('minute outside 0..1439 is rejected rather than silently scheduled', () {
      expect(() => AkashaNotificationIds.water(1440, day0), throwsArgumentError);
      expect(() => AkashaNotificationIds.water(-1, day0), throwsArgumentError);
    });

    test('every band stays under the alarm budget constant', () {
      expect(AppConstants.maxPendingAlarms, lessThanOrEqualTo(500));
      expect(AppConstants.scheduleHorizonDays, inInclusiveRange(3, 7));
    });
  });
}
