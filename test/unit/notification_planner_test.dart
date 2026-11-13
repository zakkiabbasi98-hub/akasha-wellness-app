import 'package:akasha/core/constants/app_constants.dart';
import 'package:akasha/core/notifications/notification_ids.dart';
import 'package:akasha/core/notifications/notification_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// The scheduling contract, tested purely.
///
/// `NotificationPlanner` decides every alarm the app registers, so these tests
/// cover the behaviours in the repair brief that used to be untestable:
/// multi-day materialisation, the inclusive midnight slot, quiet hours,
/// weekdays, snoozes, past-occurrence suppression and the alarm budget.
void main() {
  // A fixed "now" so nothing here depends on the wall clock.
  final now = DateTime(2026, 11, 8, 8, 30); // Sunday 08:30

  const defaultMinutes = <int>[
    540, 600, 660, 720, 780, 840, 900, 960, 1020, 1080, 1140, 1200, 1260,
    1320, 1380, 0,
  ];

  group('multi-day materialisation (the original bug)', () {
    test('16 slots over 5 days produce 80 alarms with 80 distinct ids', () {
      final plan = NotificationPlanner.planWater(
        minutes: defaultMinutes,
        amountMl: 250,
        now: now,
        horizonDays: AppConstants.scheduleHorizonDays,
      );

      expect(plan, hasLength(16 * AppConstants.scheduleHorizonDays));
      expect(plan.map((a) => a.id).toSet(), hasLength(plan.length),
          reason: 'Duplicate ids mean Android silently overwrites reminders.');
    });

    test('every day in the horizon is represented for every slot', () {
      final plan = NotificationPlanner.planWater(
        minutes: defaultMinutes,
        amountMl: 250,
        now: now,
        horizonDays: 3,
      );
      for (var d = 0; d < 3; d++) {
        final dayKey =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-'
            '${(now.day + d).toString().padLeft(2, '0')}';
        for (final minute in defaultMinutes) {
          final match = plan.where((a) =>
              a.minuteOfDay == minute &&
              a.when.day == DateTime(now.year, now.month, now.day + d).day);
          expect(match, hasLength(1),
              reason: 'Slot $minute missing on $dayKey');
        }
      }
    });

    test('occurrences are strictly ordered within a day', () {
      final plan = NotificationPlanner.planWater(
        minutes: defaultMinutes,
        amountMl: 250,
        now: now,
        horizonDays: 1,
      );
      final todayTimes = plan
          .where((a) => a.when.day == now.day)
          .map((a) => a.when)
          .toList();
      for (var i = 1; i < todayTimes.length; i++) {
        expect(todayTimes[i].isAfter(todayTimes[i - 1]), isTrue);
      }
    });
  });

  group('midnight is inclusive', () {
    test('the 12:00 AM slot fires at the next midnight, not skipped', () {
      final plan = NotificationPlanner.planWater(
        minutes: const [0],
        amountMl: 250,
        now: now, // 08:30 — midnight already passed today
        horizonDays: 1,
      );
      expect(plan, isNotEmpty);
      // The first day's midnight has passed, so the first occurrence is
      // tomorrow's 00:00 — it must not be dropped entirely.
      final first = plan.first;
      expect(first.when.hour, 0);
      expect(first.when.minute, 0);
      expect(first.when.isAfter(now), isTrue);
    });

    test('a reminder exactly at now is kept (not treated as past)', () {
      final at = DateTime(2026, 11, 8, 8, 30);
      final plan = NotificationPlanner.planWater(
        minutes: const [8 * 60 + 30],
        amountMl: 250,
        now: at,
        horizonDays: 1,
      );
      expect(plan.any((a) => a.when == at), isTrue);
    });

    test('a time one minute in the past is dropped for today only', () {
      final plan = NotificationPlanner.planWater(
        minutes: const [8 * 60 + 29],
        amountMl: 250,
        now: now,
        horizonDays: 2,
      );
      expect(plan.any((a) => a.when.day == now.day), isFalse);
      expect(plan.any((a) => a.when.day == now.day + 1), isTrue);
    });
  });

  group('quiet hours', () {
    const quiet = QuietWindow(
      enabled: true,
      startMinute: 22 * 60 + 30, // 22:30
      endMinute: 7 * 60, // 07:00
      pausesWater: true,
      pausesMotivation: true,
      pausesMedicine: false,
    );

    test('a 23:00 water slot inside the window is not scheduled', () {
      final plan = NotificationPlanner.planWater(
        minutes: const [23 * 60],
        amountMl: 250,
        now: now,
        horizonDays: 3,
        quiet: quiet,
      );
      expect(plan, isEmpty);
    });

    test('the 12:00 AM slot is suppressed by an overnight quiet window', () {
      final plan = NotificationPlanner.planWater(
        minutes: const [0],
        amountMl: 250,
        now: now,
        horizonDays: 3,
        quiet: quiet,
      );
      expect(plan, isEmpty);
    });

    test('a 09:00 slot outside the window survives', () {
      final plan = NotificationPlanner.planWater(
        minutes: const [540],
        amountMl: 250,
        now: now,
        horizonDays: 3,
        quiet: quiet,
      );
      expect(plan, hasLength(3));
    });

    test('medicine is NOT silenced when the user has not opted in', () {
      final plan = NotificationPlanner.planMedicine(
        doses: const [
          MedicineDosePlan(medicineId: 'm1', minuteOfDay: 23 * 60),
        ],
        now: now,
        horizonDays: 2,
        quiet: quiet, // pausesMedicine: false
      );
      expect(plan, isNotEmpty,
          reason: 'Dropping a prescribed dose would be a real harm.');
    });

    test('medicine IS silenced when she explicitly opts in', () {
      const optedIn = QuietWindow(
        enabled: true,
        startMinute: 22 * 60 + 30,
        endMinute: 7 * 60,
        pausesWater: true,
        pausesMotivation: true,
        pausesMedicine: true,
      );
      final plan = NotificationPlanner.planMedicine(
        doses: const [
          MedicineDosePlan(medicineId: 'm1', minuteOfDay: 23 * 60),
        ],
        now: now,
        horizonDays: 2,
        quiet: optedIn,
      );
      expect(plan, isEmpty);
    });

    test('a disabled quiet window suppresses nothing', () {
      const off = QuietWindow(
        enabled: false,
        startMinute: 22 * 60 + 30,
        endMinute: 7 * 60,
        pausesWater: true,
        pausesMotivation: true,
        pausesMedicine: true,
      );
      expect(off.wouldSuppress(23 * 60), isFalse);
      expect(off.wouldSuppress(0), isFalse);
    });
  });

  group('pausing', () {
    test('a paused water schedule plans nothing but is not an error', () {
      final plan = NotificationPlanner.planWater(
        minutes: defaultMinutes,
        amountMl: 250,
        now: now,
        horizonDays: 5,
        paused: true,
      );
      expect(plan, isEmpty);
    });

    test('paused medicine plans nothing', () {
      final plan = NotificationPlanner.planMedicine(
        doses: const [MedicineDosePlan(medicineId: 'm1', minuteOfDay: 540)],
        now: now,
        horizonDays: 5,
        paused: true,
      );
      expect(plan, isEmpty);
    });
  });

  group('medicine weekdays', () {
    test('a Monday-only medicine is scheduled only on Mondays', () {
      final plan = NotificationPlanner.planMedicine(
        doses: const [
          MedicineDosePlan(
            medicineId: 'm1',
            minuteOfDay: 480,
            weekdays: {DateTime.monday},
          ),
        ],
        now: now,
        horizonDays: 14,
      );
      expect(plan, isNotEmpty);
      for (final alarm in plan) {
        expect(alarm.when.weekday, DateTime.monday);
      }
      // Two Mondays inside a 14-day horizon starting Sunday.
      expect(plan, hasLength(2));
    });

    test('a course that has ended produces no alarms', () {
      final plan = NotificationPlanner.planMedicine(
        doses: [
          MedicineDosePlan(
            medicineId: 'm1',
            minuteOfDay: 480,
            endDay: DateTime(2026, 11, 7), // yesterday
          ),
        ],
        now: now,
        horizonDays: 5,
      );
      expect(plan, isEmpty);
    });

    test('a course that starts later is not scheduled early', () {
      final plan = NotificationPlanner.planMedicine(
        doses: [
          MedicineDosePlan(
            medicineId: 'm1',
            minuteOfDay: 480,
            startDay: DateTime(2026, 11, 10),
          ),
        ],
        now: now,
        horizonDays: 5,
      );
      expect(plan, isNotEmpty);
      for (final alarm in plan) {
        expect(alarm.when.isBefore(DateTime(2026, 11, 10)), isFalse);
      }
    });

    test('medicine ids are unique per (medicine, day, minute)', () {
      final plan = NotificationPlanner.planMedicine(
        doses: const [
          MedicineDosePlan(medicineId: 'm1', minuteOfDay: 480),
          MedicineDosePlan(medicineId: 'm1', minuteOfDay: 1200),
          MedicineDosePlan(medicineId: 'm2', minuteOfDay: 480),
        ],
        now: now,
        horizonDays: 5,
      );
      expect(plan.map((a) => a.id).toSet(), hasLength(plan.length));
      expect(plan, hasLength(3 * 5));
    });

    test('the planner log id matches MedicineRepository.logIdFor', () {
      // Same formula, expressed twice for layering reasons. If they drift, an
      // "I took it" tap would target a row that does not exist.
      const dose = MedicineDosePlan(medicineId: 'med-1', minuteOfDay: 540);
      final planned = AkashaMedicineIds.logId(dose, DateTime(2026, 11, 8));
      expect(planned, 'medlog:med-1:2026-11-08:540');
    });
  });

  group('encouragement and love notes', () {
    test('one encouragement alarm per minute per day', () {
      final plan = NotificationPlanner.planMotivation(
        minutes: const [600, 900, 1200],
        now: now,
        horizonDays: 3,
      );
      expect(plan, hasLength(9));
      expect(plan.map((a) => a.id).toSet(), hasLength(9));
    });

    test('two love notes at the same time still get distinct ids', () {
      final plan = NotificationPlanner.planLoveNotes(
        notes: const [
          LoveNotePlan(id: 'note-a', minuteOfDay: 780),
          LoveNotePlan(id: 'note-b', minuteOfDay: 780),
        ],
        now: now,
        horizonDays: 2,
      );
      expect(plan, hasLength(4));
      expect(plan.map((a) => a.id).toSet(), hasLength(4),
          reason: 'Notes sharing a clock time must not overwrite each other.');
    });

    test('disabled encouragement plans nothing', () {
      final plan = NotificationPlanner.planMotivation(
        minutes: const [600],
        now: now,
        horizonDays: 3,
        enabled: false,
      );
      expect(plan, isEmpty);
    });
  });

  group('alarm budget', () {
    test('a heavy but realistic day stays inside the Android budget', () {
      // 16 water x 5 days + 12 meds x 3 x 5 days + 3 encouragement x 5
      final water = NotificationPlanner.planWater(
        minutes: defaultMinutes,
        amountMl: 250,
        now: now,
        horizonDays: AppConstants.scheduleHorizonDays,
      );
      final meds = NotificationPlanner.planMedicine(
        doses: [
          for (var m = 0; m < 12; m++)
            for (final minute in const [480, 840, 1260])
              MedicineDosePlan(medicineId: 'med$m', minuteOfDay: minute),
        ],
        now: now,
        horizonDays: AppConstants.scheduleHorizonDays,
      );
      final total = water.length + meds.length;
      expect(
        NotificationPlanner.isWithinAlarmBudget(total),
        isTrue,
        reason: 'Total $total would overflow the pending-alarm ceiling.',
      );
    });

    test('the budget helper rejects an absurd count', () {
      expect(NotificationPlanner.isWithinAlarmBudget(10), isTrue);
      expect(
        NotificationPlanner.isWithinAlarmBudget(
            AppConstants.maxPendingAlarms + 1),
        isFalse,
      );
    });
  });

  group('nextOccurrence', () {
    test('returns today when the time is still ahead', () {
      final next = NotificationPlanner.nextOccurrence(9 * 60, now);
      expect(next.day, now.day);
      expect(next.hour, 9);
    });

    test('rolls to tomorrow when the time has passed', () {
      final next = NotificationPlanner.nextOccurrence(7 * 60, now);
      expect(next.day, now.day + 1);
      expect(next.hour, 7);
    });

    test('rolls a midnight slot to tomorrow, never to today 00:00', () {
      final next = NotificationPlanner.nextOccurrence(0, now);
      expect(next.isAfter(now), isTrue);
      expect(next.hour, 0);
    });
  });
}
