import 'package:akasha/core/constants/app_constants.dart';
import 'package:akasha/core/services/water_schedule_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// These tests encode the water-reminder contract from the specification.
/// They are pure Dart — no Flutter bindings, no device, no database — so they
/// run in milliseconds and protect the most behaviour-critical logic in the app.
void main() {
  group('default schedule (spec §6)', () {
    test('produces exactly 16 reminders', () {
      final slots = WaterScheduleEngine.defaults();
      expect(slots, hasLength(AppConstants.expectedDefaultWaterSlots));
      expect(slots, hasLength(16));
    });

    test('starts at 09:00 AM and includes 12:00 AM (midnight)', () {
      final slots = WaterScheduleEngine.defaults();
      expect(slots.first.minuteOfDay, 9 * 60);
      expect(slots.first.label, '09:00 AM');
      // The midnight reminder is the one that is easy to drop — assert it hard.
      expect(slots.last.minuteOfDay, 0);
      expect(slots.last.label, '12:00 AM');
    });

    test('matches the exact list from the specification', () {
      final labels = WaterScheduleEngine.defaults().map((s) => s.label).toList();
      expect(labels, [
        '09:00 AM',
        '10:00 AM',
        '11:00 AM',
        '12:00 PM',
        '01:00 PM',
        '02:00 PM',
        '03:00 PM',
        '04:00 PM',
        '05:00 PM',
        '06:00 PM',
        '07:00 PM',
        '08:00 PM',
        '09:00 PM',
        '10:00 PM',
        '11:00 PM',
        '12:00 AM',
      ]);
    });

    test('contains no duplicate minutes', () {
      final minutes = WaterScheduleEngine.minutes(WaterScheduleEngine.defaults());
      expect(minutes.toSet(), hasLength(minutes.length));
      expect(minutes, hasLength(16));
    });
  });

  group('generate()', () {
    test('start == end means a full 24-hour window, without a duplicate slot', () {
      final slots = WaterScheduleEngine.generate(
        startMinute: 600,
        endMinute: 600,
        intervalMinutes: 60,
      );
      // "10:00 to 10:00" means all day. The closing boundary repeats the first
      // slot, and duplicates are dropped, so an hourly day is 24 reminders —
      // never 25, and never two alarms at the same minute.
      expect(slots, hasLength(24));
      expect(slots.first.minuteOfDay, 600);
      expect(slots.last.minuteOfDay, 600 - 60);
      expect(slots.map((s) => s.minuteOfDay).toSet(), hasLength(24));
    });

    test('non-wrapping window includes both boundaries', () {
      final slots = WaterScheduleEngine.generate(
        startMinute: 8 * 60,
        endMinute: 12 * 60,
        intervalMinutes: 60,
      );
      expect(slots.map((s) => s.minuteOfDay), [480, 540, 600, 660, 720]);
    });

    test('window that does not land on the grid excludes the end', () {
      final slots = WaterScheduleEngine.generate(
        startMinute: 9 * 60,
        endMinute: 12 * 60 + 30, // 12:30 is not reachable on an hourly grid
        intervalMinutes: 60,
      );
      expect(slots.map((s) => s.minuteOfDay), [540, 600, 660, 720]);
    });

    test('wrapping window crosses midnight cleanly', () {
      final slots = WaterScheduleEngine.generate(
        startMinute: 22 * 60, // 10 PM
        endMinute: 2 * 60, // 2 AM
        intervalMinutes: 60,
      );
      expect(
        slots.map((s) => s.minuteOfDay),
        [1320, 1380, 0, 60, 120],
      );
    });

    test('respects interval arithmetic for 30-minute reminders', () {
      final slots = WaterScheduleEngine.generate(
        startMinute: 9 * 60,
        endMinute: 11 * 60,
        intervalMinutes: 30,
      );
      expect(slots, hasLength(5));
      expect(slots[1].label, '09:30 AM');
      expect(slots[1].minuteOfDay, 570);
    });

    test('rejects intervals that are too small', () {
      expect(
        () => WaterScheduleEngine.generate(
          startMinute: 0,
          endMinute: 60,
          intervalMinutes: 1,
        ),
        throwsArgumentError,
      );
    });

    test('never exceeds the safety cap', () {
      final slots = WaterScheduleEngine.generate(
        startMinute: 0,
        endMinute: 1439,
        intervalMinutes: 5,
      );
      expect(slots.length, lessThanOrEqualTo(WaterScheduleEngine.maxSlots));
    });
  });

  group('duplicate prevention', () {
    test('areEquivalent is order independent', () {
      expect(
        WaterScheduleEngine.areEquivalent([540, 600, 660], [660, 540, 600]),
        isTrue,
      );
    });

    test('areEquivalent rejects different sets', () {
      expect(
        WaterScheduleEngine.areEquivalent([540, 600], [540, 600, 660]),
        isFalse,
      );
      expect(
        WaterScheduleEngine.areEquivalent([540, 600], [540, 660]),
        isFalse,
      );
    });

    test('minutes() de-duplicates and sorts', () {
      final slots = WaterScheduleEngine.generate(
        startMinute: 9 * 60,
        endMinute: 10 * 60,
        intervalMinutes: 30,
      );
      final minutes = WaterScheduleEngine.minutes([...slots, ...slots]);
      expect(minutes, [540, 570, 600]);
    });
  });

  group('end of day semantics', () {
    test('12:00 AM parses to minute 0, not 1440', () {
      expect(WaterScheduleEngine.parseTime('12:00 AM'), 0);
      expect(WaterScheduleEngine.parseTime('12:00 PM'), 12 * 60);
      expect(WaterScheduleEngine.parseTime('11:00 PM'), 23 * 60);
    });

    test('parses several input formats', () {
      expect(WaterScheduleEngine.parseTime('9:00'), 540);
      expect(WaterScheduleEngine.parseTime('09:00'), 540);
      expect(WaterScheduleEngine.parseTime('9:00 am'), 540);
      expect(WaterScheduleEngine.parseTime('9 PM'), 21 * 60);
      expect(WaterScheduleEngine.parseTime('0:00'), 0);
      expect(WaterScheduleEngine.parseTime('24:00'), isNull);
      expect(WaterScheduleEngine.parseTime('nonsense'), isNull);
    });

    test('formatting round-trips', () {
      for (final minute in [0, 60, 9 * 60, 12 * 60, 13 * 60, 23 * 60 + 59]) {
        final label = WaterScheduleEngine.formatLabel(minute);
        expect(WaterScheduleEngine.parseTime(label), minute);
      }
    });

    test('windowSpanMinutes handles the midnight wrap', () {
      // 09:00 → 12:00 AM is 15 hours of waking window.
      expect(
        WaterScheduleEngine.windowSpanMinutes(9 * 60, 0),
        15 * 60,
      );
      expect(
        WaterScheduleEngine.windowSpanMinutes(22 * 60, 2 * 60),
        4 * 60,
      );
    });
  });

  group('next slot / remaining', () {
    final slots = WaterScheduleEngine.defaults();

    test('finds the next reminder in the same day', () {
      final now = DateTime(2026, 11, 8, 10, 30);
      final next = WaterScheduleEngine.nextSlot(slots, now);
      expect(next, isNotNull);
      expect(next!.minuteOfDay, 11 * 60);
    });

    test('rolls over to the first slot of tomorrow after the last one', () {
      final now = DateTime(2026, 11, 8, 23, 30);
      final next = WaterScheduleEngine.nextSlot(slots, now);
      expect(next!.minuteOfDay, 0); // midnight reminder is still ahead
    });

    test('after midnight, the next slot is 09:00 when no midnight slot remains',
        () {
      final now = DateTime(2026, 11, 8, 0, 5);
      final next = WaterScheduleEngine.nextSlot(slots, now);
      expect(next!.minuteOfDay, 9 * 60);
    });

    test('remainingToday counts slots at or after now, midnight included', () {
      final now = DateTime(2026, 11, 8, 21, 0);
      // 9 PM, 10 PM, 11 PM and the 12:00 AM reminder remain → 4.
      // Midnight belongs to the end of the waking day, not the start, so it is
      // still ahead of you at 9 PM.
      expect(WaterScheduleEngine.remainingToday(slots, now), 4);
    });

    test('remainingToday at 00:05 counts the whole coming day', () {
      final now = DateTime(2026, 11, 8, 0, 5);
      // Every slot (09:00 … 11:00 PM) is still ahead; the 12:00 AM one has just
      // passed, so it is not counted twice.
      expect(WaterScheduleEngine.remainingToday(slots, now), 15);
    });

    test('returns null for an empty schedule', () {
      expect(WaterScheduleEngine.nextSlot([], DateTime.now()), isNull);
    });
  });

  group('user-configurable windows', () {
    test('a 12-hour window at 90 minutes yields the right count', () {
      final slots = WaterScheduleEngine.generate(
        startMinute: 8 * 60,
        endMinute: 20 * 60,
        intervalMinutes: 90,
      );
      // 08:00 … 20:00 inclusive, step 90 → 9 slots
      expect(slots, hasLength(9));
    });

    test('estimateSlotsPerDay catches invalid configuration gracefully', () {
      expect(
        WaterScheduleEngine.estimateSlotsPerDay(
          startMinute: 0,
          endMinute: 100,
          intervalMinutes: 0,
        ),
        0,
      );
    });

    test('describeWindow produces a friendly range', () {
      expect(
        WaterScheduleEngine.describeWindow(9 * 60, 0),
        '09:00 AM – 12:00 AM',
      );
    });

    test('custom interval produces no duplicate slots across the wrap', () {
      final slots = WaterScheduleEngine.generate(
        startMinute: 23 * 60,
        endMinute: 1 * 60,
        intervalMinutes: 30,
      );
      final minutes = slots.map((s) => s.minuteOfDay).toList();
      expect(minutes.toSet().length, minutes.length);
      expect(minutes, [1380, 1410, 0, 30, 60]);
    });
  });
}
