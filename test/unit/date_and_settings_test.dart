import 'package:akasha/core/constants/app_constants.dart';
import 'package:akasha/core/utils/date_utils.dart';
import 'package:akasha/core/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AkashaDates', () {
    test('dayOnly strips the time component', () {
      final d = AkashaDates.dayOnly(DateTime(2026, 11, 8, 23, 59, 59));
      expect(d, DateTime(2026, 11, 8));
    });

    test('isSameDay ignores time', () {
      expect(
        AkashaDates.isSameDay(
          DateTime(2026, 11, 8, 0, 1),
          DateTime(2026, 11, 8, 23, 59),
        ),
        isTrue,
      );
      expect(
        AkashaDates.isSameDay(
          DateTime(2026, 11, 8, 0, 1),
          DateTime(2026, 11, 9, 0, 1),
        ),
        isFalse,
      );
    });

    test('startOfWeek is Monday-based', () {
      // 8 Nov 2026 is a Sunday → the week starts on Monday 2 Nov.
      expect(AkashaDates.startOfWeek(DateTime(2026, 11, 8)), DateTime(2026, 11, 2));
      expect(AkashaDates.startOfWeek(DateTime(2026, 11, 2)), DateTime(2026, 11, 2));
    });

    test('startOfMonth / endOfMonth', () {
      expect(AkashaDates.startOfMonth(DateTime(2026, 2, 14)), DateTime(2026, 2, 1));
      expect(AkashaDates.endOfMonth(DateTime(2026, 2, 14)).day, 28);
      expect(AkashaDates.endOfMonth(DateTime(2028, 2, 14)).day, 29);
    });

    test('day keys round-trip', () {
      final d = DateTime(2026, 1, 5);
      expect(AkashaDates.key(d), '2026-01-05');
      expect(AkashaDates.parseKey('2026-01-05'), d);
    });

    test('millis round-trip preserves the instant', () {
      final d = DateTime(2026, 11, 8, 13, 42, 7);
      expect(AkashaDates.fromMillis(AkashaDates.millis(d)), d);
    });

    test('minutesToLabel handles midnight and noon', () {
      expect(AkashaDates.minutesToLabel(0), '12:00 AM');
      expect(AkashaDates.minutesToLabel(720), '12:00 PM');
      expect(AkashaDates.minutesToLabel(9 * 60), '9:00 AM');
      expect(AkashaDates.minutesToLabel(1440), '12:00 AM'); // wraps
    });

    test('parseTimeToMinutes understands the formats we store', () {
      expect(AkashaDates.parseTimeToMinutes('09:00'), 540);
      expect(AkashaDates.parseTimeToMinutes('9:00 AM'), 540);
      expect(AkashaDates.parseTimeToMinutes('12:00 AM'), 0);
      expect(AkashaDates.parseTimeToMinutes('12:00 PM'), 720);
      expect(AkashaDates.parseTimeToMinutes('9 PM'), 1260);
      expect(AkashaDates.parseTimeToMinutes('garbage'), isNull);
    });

    test('quiet hours handle same-day and overnight windows', () {
      // Same-day window 13:00 – 15:00
      expect(
        AkashaDates.isWithinQuietHours(
          now: DateTime(2026, 11, 8, 14),
          quietStartMinutes: 13 * 60,
          quietEndMinutes: 15 * 60,
        ),
        isTrue,
      );
      expect(
        AkashaDates.isWithinQuietHours(
          now: DateTime(2026, 11, 8, 16),
          quietStartMinutes: 13 * 60,
          quietEndMinutes: 15 * 60,
        ),
        isFalse,
      );
      // Overnight window 22:30 – 07:00
      expect(
        AkashaDates.isWithinQuietHours(
          now: DateTime(2026, 11, 8, 23),
          quietStartMinutes: 22 * 60 + 30,
          quietEndMinutes: 7 * 60,
        ),
        isTrue,
      );
      expect(
        AkashaDates.isWithinQuietHours(
          now: DateTime(2026, 11, 8, 6),
          quietStartMinutes: 22 * 60 + 30,
          quietEndMinutes: 7 * 60,
        ),
        isTrue,
      );
      expect(
        AkashaDates.isWithinQuietHours(
          now: DateTime(2026, 11, 8, 9),
          quietStartMinutes: 22 * 60 + 30,
          quietEndMinutes: 7 * 60,
        ),
        isFalse,
      );
    });

    test('identical quiet start/end means "no quiet window"', () {
      expect(
        AkashaDates.isWithinQuietHours(
          now: DateTime(2026, 11, 8, 12),
          quietStartMinutes: 600,
          quietEndMinutes: 600,
        ),
        isFalse,
      );
    });

    test('lastNDays returns ascending consecutive days', () {
      final days = AkashaDates.lastNDays(7, anchor: DateTime(2026, 11, 8));
      expect(days, hasLength(7));
      expect(days.first, DateTime(2026, 11, 2));
      expect(days.last, DateTime(2026, 11, 8));
    });

    test('greeting buckets cover the whole day', () {
      expect(AkashaDates.greeting(DateTime(2026, 11, 8, 2)), 'Good night');
      expect(AkashaDates.greeting(DateTime(2026, 11, 8, 8)), 'Good morning');
      expect(AkashaDates.greeting(DateTime(2026, 11, 8, 14)), 'Good afternoon');
      expect(AkashaDates.greeting(DateTime(2026, 11, 8, 19)), 'Good evening');
      expect(AkashaDates.greeting(DateTime(2026, 11, 8, 23)), 'Good night');
    });
  });

  group('constants match the specification', () {
    test('water defaults', () {
      expect(AppConstants.defaultWaterStartMinute, 540);
      expect(AppConstants.defaultWaterEndMinute, 0);
      expect(AppConstants.defaultWaterIntervalMinutes, 60);
      expect(AppConstants.expectedDefaultWaterSlots, 16);
    });

    test('glass sizes', () {
      expect(AppConstants.smallGlassMl, 150);
      expect(AppConstants.defaultGlassMl, 250);
      expect(AppConstants.largeGlassMl, 350);
    });

    test('motivation library target is at least 100', () {
      expect(AppConstants.motivationPoolTarget, greaterThanOrEqualTo(100));
    });
  });

  group('validators', () {
    test('name', () {
      expect(Validators.name(null), isNotNull);
      expect(Validators.name('   '), isNotNull);
      expect(Validators.name('A'), isNotNull);
      expect(Validators.name('Akasha'), isNull);
    });

    test('water amount bounds', () {
      expect(Validators.waterAmount('10'), isNotNull); // below the 50 ml floor
      expect(Validators.waterAmount('250'), isNull);
      expect(Validators.waterAmount('5000'), isNotNull); // above the 3000 ml cap
      expect(Validators.waterAmount('abc'), isNotNull);
      expect(Validators.waterAmount(''), isNotNull);
    });

    test('water target bounds', () {
      // A daily target under 500 ml is not a sensible goal to store silently.
      expect(Validators.waterTarget('100'), isNotNull);
      expect(Validators.waterTarget('2000'), isNull);
      expect(Validators.waterTarget('99999'), isNotNull);
    });

    test('dosage is optional', () {
      expect(Validators.dosage(''), isNull);
      expect(Validators.dosage(null), isNull);
      expect(Validators.dosage('1 tablet after breakfast'), isNull);
    });
  });
}
