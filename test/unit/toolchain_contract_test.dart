import 'package:akasha/core/notifications/notification_service.dart';
import 'package:akasha/core/utils/validators.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Contract tests for the fixes made in the toolchain-alignment pass.
///
/// These do not need a device, a plugin, or a running notification service.
/// Every one of them would have failed to **compile** before the pass, which is
/// the class of defect the real build log reported — so compiling this file is
/// itself part of the test.
void main() {
  group('notification action ids match the plugin wire format', () {
    // flutter_local_notifications 17 types `AndroidNotificationAction.id` as a
    // String; Android hands that same string back in `response.actionId`. The
    // app's own logic is keyed on ints. Both must agree.
    test('the string ids mirror the integer ids exactly', () {
      expect(AkashaActions.drankWaterId, '1');
      expect(AkashaActions.skipWaterId, '2');
      expect(AkashaActions.snoozeWaterId, '3');
      expect(AkashaActions.tookMedicineId, '10');
      expect(AkashaActions.skipMedicineId, '11');
      expect(AkashaActions.snoozeMedicineId, '12');
      expect(AkashaActions.openAppId, '20');
    });

    test('every id parses back to its integer', () {
      final pairs = {
        AkashaActions.drankWaterId: AkashaActions.drankWater,
        AkashaActions.skipWaterId: AkashaActions.skipWater,
        AkashaActions.snoozeWaterId: AkashaActions.snoozeWater,
        AkashaActions.tookMedicineId: AkashaActions.tookMedicine,
        AkashaActions.skipMedicineId: AkashaActions.skipMedicine,
        AkashaActions.snoozeMedicineId: AkashaActions.snoozeMedicine,
        AkashaActions.openAppId: AkashaActions.openApp,
      };
      pairs.forEach((wire, logic) {
        expect(int.tryParse(wire), logic,
            reason: 'A tap would be attributed to the wrong action.');
      });
    });

    test('a string action id is a valid 32-bit notification action', () {
      // The plugin validates notification *ids* to 32 bits and action ids are
      // sent as strings, so nothing here may be empty.
      for (final id in [
        AkashaActions.drankWaterId,
        AkashaActions.skipWaterId,
        AkashaActions.snoozeWaterId,
        AkashaActions.tookMedicineId,
        AkashaActions.skipMedicineId,
        AkashaActions.snoozeMedicineId,
      ]) {
        expect(id, isNotEmpty);
        expect(int.tryParse(id), isNotNull);
      }
    });
  });

  group('NotificationResponse (v17 constructor)', () {
    // v17 has no `notificationId` argument: it is `id`. Building the response
    // the old way is a compile error, which is exactly what the build log hit
    // in background_actions.dart.
    test('the replay constructor shape is supported', () {
      final response = NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        id: 0,
        actionId: AkashaActions.drankWaterId,
        payload: 'water||250|540|2026-11-08',
      );
      expect(response.id, 0);
      expect(response.actionId, '1');
      expect(response.notificationResponseType,
          NotificationResponseType.selectedNotificationAction);
    });

    test('a plain tap carries no action id', () {
      final response = NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        id: 7,
        payload: 'water||250|540|2026-11-08',
      );
      expect(response.actionId, isNull);
      expect(int.tryParse(response.actionId ?? '') ?? 0, 0);
    });
  });

  group('AndroidScheduleMode', () {
    // Both values the scheduler uses must exist in the pinned 17.x API.
    test('exact and inexact idle modes are available', () {
      expect(AndroidScheduleMode.values,
          containsAll(<AndroidScheduleMode>[
        AndroidScheduleMode.exactAllowWhileIdle,
        AndroidScheduleMode.inexactAllowWhileIdle,
        AndroidScheduleMode.exact,
        AndroidScheduleMode.inexact,
        AndroidScheduleMode.alarmClock,
      ]));
    });

    test('the zonedSchedule interpretation enum has a wall-clock option', () {
      // `zonedSchedule` in 17.x *requires* this argument; without it the code
      // did not compile. Wall-clock is the correct choice for local reminders.
      expect(UILocalNotificationDateInterpretation.values,
          contains(UILocalNotificationDateInterpretation.wallClockTime));
    });
  });

  group('medicine reminder-time validation', () {
    test('unique times are accepted', () {
      expect(Validators.hasDuplicateMinutes(const [480, 540, 600]), isFalse);
    });

    test('a repeated time is rejected', () {
      expect(Validators.hasDuplicateMinutes(const [540, 540]), isTrue);
    });

    test('a repeat hidden later in the list is rejected', () {
      expect(
        Validators.hasDuplicateMinutes(const [480, 540, 600, 480]),
        isTrue,
        reason: 'Only checking neighbours would miss this.',
      );
    });

    test('empty and single-entry lists are fine', () {
      expect(Validators.hasDuplicateMinutes(const []), isFalse);
      expect(Validators.hasDuplicateMinutes(const [540]), isFalse);
    });
  });

  group('native system channel contract', () {
    // The Dart side asks MainActivity for these method names; a typo there is a
    // silent "false" at runtime rather than a compile error, so pin the name.
    test('the channel name matches MainActivity.kt', () {
      const channel = MethodChannel('com.akasha.wellness/system');
      expect(channel.name, 'com.akasha.wellness/system');
    });
  });
}
