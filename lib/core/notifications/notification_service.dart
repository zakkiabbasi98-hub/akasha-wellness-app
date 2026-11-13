import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../constants/app_constants.dart';
import '../services/system_channel.dart';
import '../utils/date_utils.dart';
import 'background_actions.dart';
import 'notification_ids.dart';
import 'notification_planner.dart';

/// Action ids used by the notification buttons.
///
/// Android hands these back in `NotificationResponse.actionId`, always as a
/// **string** — flutter_local_notifications declares
/// `AndroidNotificationAction.id` as a `String` and never converts it back. The
/// integer constants below are the single source of truth for the app's logic
/// (the switch statements in `background_actions.dart` and
/// `action_controller.dart`); the `*Id` string constants are the wire format and
/// are derived from the integers, so the two can never drift apart.
abstract final class AkashaActions {
  static const int drankWater = 1;
  static const int skipWater = 2;
  static const int snoozeWater = 3;
  static const int tookMedicine = 10;
  static const int skipMedicine = 11;
  static const int snoozeMedicine = 12;
  static const int openApp = 20;

  /// The same ids as **strings**, because v17 of flutter_local_notifications
  /// declares `AndroidNotificationAction.id` as a `String`. Keeping both forms
  /// means the integer constants stay the single source of truth: the strings
  /// are derived from them at compile time, so the two can never drift apart.
  static const String drankWaterId = '$drankWater';
  static const String skipWaterId = '$skipWater';
  static const String snoozeWaterId = '$snoozeWater';
  static const String tookMedicineId = '$tookMedicine';
  static const String skipMedicineId = '$skipMedicine';
  static const String snoozeMedicineId = '$snoozeMedicine';
  static const String openAppId = '$openApp';

  static const String payloadWater = 'water';
  static const String payloadMedicine = 'medicine';
  static const String payloadMotivation = 'motivation';
  static const String payloadLoveNote = 'love_note';
  static const String payloadDaily = 'daily';
}

/// Wire format of a notification payload: `kind|refId|amountMl|slotMinute|dayKey`
///
/// `dayKey` was added in repair R1/R2 so a background action can attribute the
/// tap to the **correct calendar day** even if the user answers at 00:05 for a
/// reminder that fired at 23:55. Without it, "I drank water" just after
/// midnight was booked against the wrong day.
class NotificationPayload {
  const NotificationPayload({
    required this.kind,
    this.refId,
    this.value,
    this.slotMinute,
    this.dayKey,
  });

  final String kind;
  final String? refId;
  final int? value;
  final int? slotMinute;
  final String? dayKey;

  /// The calendar day this notification belongs to. Falls back to today when
  /// the payload predates the field (alarms scheduled by an older build and
  /// still pending after an app update).
  DateTime get occurredOn {
    final key = dayKey;
    if (key != null && key.isNotEmpty) {
      final parsed = AkashaDates.parseKey(key);
      return parsed;
    }
    return AkashaDates.today();
  }

  String encode() => [
        kind,
        refId ?? '',
        value?.toString() ?? '',
        slotMinute?.toString() ?? '',
        dayKey ?? '',
      ].join('|');

  static NotificationPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|');
    if (parts.isEmpty || parts[0].isEmpty) return null;
    return NotificationPayload(
      kind: parts[0],
      refId: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null,
      value:
          parts.length > 2 && parts[2].isNotEmpty ? int.tryParse(parts[2]) : null,
      slotMinute:
          parts.length > 3 && parts[3].isNotEmpty ? int.tryParse(parts[3]) : null,
      dayKey: parts.length > 4 && parts[4].isNotEmpty ? parts[4] : null,
    );
  }
}

/// Top-level entry point required by flutter_local_notifications.
///
/// MUST be top-level: Android invokes it in a **separate isolate** when the app
/// is terminated. It therefore touches no static state that the main isolate
/// sets up — [BackgroundActionEngine] opens its own database connection.
@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {
  // Fire and forget: the plugin signature is void, and the queue inside
  // BackgroundActionEngine guarantees durability if this isolate is killed.
  BackgroundActionEngine.handle(response);
}

/// Schedules and shows every local notification in the app.
///
/// Design notes
/// ------------
/// * Times are local wall-clock in the device timezone, so 09:00 stays 09:00
///   across a DST shift or a flight.
/// * Recurring slots are materialised day-by-day over a rolling horizon rather
///   than using `matchDateTimeComponents`, because the payload must differ per
///   day (medicine rows are addressed by a day-specific id) and because ids must
///   differ per day (repair R1 — a shared id made each day overwrite the last).
/// * All ids come from [AkashaNotificationIds] via [NotificationPlanner]; this
///   class performs side effects only and decides nothing.
class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  // ── Channels ──────────────────────────────────────────────────────────────
  //
  // Audio usage is what makes water feel like an alarm and medicine feel like a
  // message. Android maps `alarm` onto the alarm volume stream (so a muted
  // media volume does not silence a reminder) while `notification` follows the
  // normal message tone. Neither bypasses Do Not Disturb — that stays the
  // user's decision, always.

  static const AndroidNotificationChannel waterChannel = AndroidNotificationChannel(
    AppConstants.channelWater,
    'Water reminders',
    description: 'Gentle reminders to drink water through your day.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
  );

  static const AndroidNotificationChannel medicineChannel = AndroidNotificationChannel(
    AppConstants.channelMedicine,
    'Medicine reminders',
    description: 'Your scheduled medicine times, as a calm message.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.notification,
  );

  static const AndroidNotificationChannel motivationChannel = AndroidNotificationChannel(
    AppConstants.channelMotivation,
    'Encouragement',
    description: 'Small supportive messages during your day.',
    importance: Importance.defaultImportance,
    playSound: true,
    audioAttributesUsage: AudioAttributesUsage.notification,
  );

  static const AndroidNotificationChannel loveNoteChannel = AndroidNotificationChannel(
    AppConstants.channelLoveNotes,
    'Little love notes',
    description: 'Warm notes from someone who cares.',
    importance: Importance.defaultImportance,
    playSound: true,
    audioAttributesUsage: AudioAttributesUsage.notification,
  );

  static const AndroidNotificationChannel dailyChannel = AndroidNotificationChannel(
    AppConstants.channelDaily,
    'Daily summary',
    description: 'A quiet evening summary of your day.',
    importance: Importance.low,
    playSound: false,
  );

  bool _initialised = false;
  bool _lastInitFailed = false;
  String? _lastInitError;

  /// Actions answered while the UI was alive. Drained by the action controller.
  final List<NotificationActionEvent> _pendingEvents = [];

  /// Fired when a notification is tapped (not an action button), so the UI can
  /// navigate. Set by the app shell.
  void Function(NotificationPayload payload)? onForegroundTap;

  bool get isInitialised => _initialised;
  bool get lastInitFailed => _lastInitFailed;
  String? get lastInitError => _lastInitError;

  Future<bool> initialize({
    void Function(NotificationResponse response)? onForegroundResponse,
  }) async {
    if (_initialised) return true;

    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(_zoneNameForOffset(DateTime.now())));

      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: false, // asked explicitly, in context
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      final ok = await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          final payload = NotificationPayload.decode(response.payload);
          if (payload == null) return;
          final actionId = int.tryParse(response.actionId ?? '') ?? 0;
          _pendingEvents.add(NotificationActionEvent(
            actionId: actionId,
            payload: payload,
            respondedAt: DateTime.now(),
          ));
          onForegroundResponse?.call(response);
          if (actionId == 0) onForegroundTap?.call(payload);
        },
        // Runs in a headless isolate when the app is not in memory.
        onDidReceiveBackgroundNotificationResponse:
            onBackgroundNotificationResponse,
      );

      _initialised = ok ?? false;
      if (_initialised) {
        await _createChannels();
      } else {
        _lastInitFailed = true;
        _lastInitError = 'The notification plugin refused to initialise.';
      }
      return _initialised;
    } catch (e, st) {
      _lastInitFailed = true;
      _lastInitError = e.toString();
      debugPrint('AKASHA: notification init failed: $e\n$st');
      return false;
    }
  }

  /// Picks a tz-database zone whose current UTC offset matches the device's.
  ///
  /// Every zone with the same offset produces identical *instants*, and every
  /// scheduled alarm is first converted to a [tz.TZDateTime] in this zone and
  /// then interpreted as wall-clock time by the plugin, so an alarm always
  /// fires at the intended local minute. A DST shift is picked up because
  /// [tz.setLocalLocation] is re-run on every cold start (the offset it reads
  /// is the *current* one, which is the post-shift offset), and because the
  /// horizon is re-materialised on launch, on the native
  /// TIME_SET/TIMEZONE_CHANGED broadcast, and once a day while the app runs.
  ///
  /// `latest_all` is used for the timezone database (not the 20 KB `latest`),
  /// so the full IANA list is available and the offset scan below usually finds
  /// an exact named match rather than the `Etc/GMT` fallback.
  static String _zoneNameForOffset(DateTime now) {
    final offset = now.timeZoneOffset;
    if (offset == Duration.zero) return 'UTC';

    const candidates = [
      'Asia/Karachi',
      'Asia/Kolkata',
      'Asia/Dhaka',
      'Asia/Kathmandu',
      'Asia/Dubai',
      'Asia/Riyadh',
      'Asia/Tehran',
      'Asia/Karachi',
      'Asia/Jakarta',
      'Asia/Shanghai',
      'Asia/Singapore',
      'Asia/Tokyo',
      'Asia/Seoul',
      'Australia/Sydney',
      'Europe/London',
      'Europe/Paris',
      'Europe/Berlin',
      'Europe/Istanbul',
      'Europe/Moscow',
      'Africa/Lagos',
      'Africa/Johannesburg',
      'America/Sao_Paulo',
      'America/New_York',
      'America/Chicago',
      'America/Denver',
      'America/Los_Angeles',
      'Pacific/Auckland',
    ];

    for (final name in candidates) {
      try {
        final zone = tz.getLocation(name);
        final nowInZone = tz.TZDateTime.now(zone);
        if (nowInZone.timeZoneOffset == offset) return name;
      } catch (_) {
        continue;
      }
    }
    // Whole-hour fallback. Etc/GMT signs are inverted relative to ISO.
    if (offset.inMinutes % 60 == 0) {
      final hours = offset.inHours;
      final sign = hours >= 0 ? '-' : '+';
      final name = 'Etc/GMT$sign${hours.abs()}';
      try {
        tz.getLocation(name);
        return name;
      } catch (_) {}
    }
    return 'UTC';
  }

  Future<void> _createChannels() async {
    final android = _android;
    if (android == null) return;
    for (final channel in [
      waterChannel,
      medicineChannel,
      motivationChannel,
      loveNoteChannel,
      dailyChannel,
    ]) {
      try {
        await android.createNotificationChannel(channel);
      } catch (e) {
        debugPrint('AKASHA: channel ${channel.id} failed: $e');
      }
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  // ── Permissions ───────────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    final android = _android;
    if (android == null) return false;
    return await android.requestNotificationsPermission() ?? false;
  }

  Future<bool> areNotificationsEnabled() async =>
      await _android?.areNotificationsEnabled() ?? false;

  Future<bool> canScheduleExactAlarms() async =>
      await _android?.canScheduleExactNotifications() ?? false;

  Future<bool> requestExactAlarmsPermission() async =>
      await _android?.requestExactAlarmsPermission() ?? false;

  /// Whether Android currently lets AKASHA post a full-screen (alarm-style)
  /// reminder over the lock screen.
  ///
  /// flutter_local_notifications v17 exposes **no** getter for this — only the
  /// request. Rather than invent a method the plugin does not have, the answer
  /// is derived from the system permission the platform actually gates it on:
  /// `USE_FULL_SCREEN_INTENT` is a normal permission that is granted on install
  /// up to Android 13 and can be revoked by the user from Android 14 onwards.
  /// The native `system` channel in MainActivity answers it exactly.
  Future<bool> areFullScreenIntentsAllowed() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return const SystemChannel().canUseFullScreenIntent();
  }

  /// Asks Android for full-screen-intent permission.
  ///
  /// `requestFullScreenIntentPermission()` **is** part of the 17.x Android
  /// implementation (it opens the per-app settings page on Android 14+), so
  /// this is a real plugin call, not an invention. Its result means "the
  /// settings screen was opened", so callers re-read
  /// [areFullScreenIntentsAllowed] rather than trusting the bool.
  Future<bool> requestFullScreenIntentsPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return await _android?.requestFullScreenIntentPermission() ?? false;
  }

  /// Current user-facing importance of a channel, or null when it does not
  /// exist yet. The diagnostics screen uses this to notice that the user
  /// downgraded water reminders to "silent" and stopped hearing them.
  ///
  /// v17 has no single-channel getter, so the full list is fetched and
  /// filtered — the list is at most a handful of entries.
  Future<Importance?> channelImportance(String channelId) async {
    try {
      final channels = await _android?.getNotificationChannels();
      if (channels == null) return null;
      for (final channel in channels) {
        if (channel.id == channelId) return channel.importance;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Scheduling ────────────────────────────────────────────────────────────

  /// Registers one planned alarm.
  ///
  /// Returning a bool (instead of throwing) matters: the planner may produce
  /// 200 alarms and one refusal from the OS must not abort the whole pass.
  Future<bool> schedulePlanned(
    PlannedAlarm alarm, {
    required bool exact,
    required NotificationText text,
    bool voiceSpoken = false,
  }) async {
    final details = _detailsFor(alarm, text, voiceSpoken: voiceSpoken);
    // The payload records the day the *occurrence* belongs to, not the day the
    // user answers.
    final payload = NotificationPayload(
      kind: alarm.kind,
      refId: alarm.refId,
      value: alarm.amountMl,
      slotMinute: alarm.minuteOfDay,
      dayKey: AkashaDates.key(alarm.when),
    ).encode();

    try {
      await _plugin.zonedSchedule(
        alarm.id,
        text.title,
        text.body,
        _toTz(alarm.when),
        details,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.wallClockTime,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
      return true;
    } catch (e) {
      // The classic cause is `exact_alarms_not_permitted` after the user
      // revokes the permission. Retry once inexactly rather than losing the
      // reminder entirely.
      debugPrint('AKASHA: exact schedule failed for ${alarm.id} ($e); '
          'retrying inexact');
      try {
        await _plugin.zonedSchedule(
          alarm.id,
          text.title,
          text.body,
          _toTz(alarm.when),
          details,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.wallClockTime,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
        return true;
      } catch (e2) {
        debugPrint('AKASHA: scheduling ${alarm.id} failed completely: $e2');
        return false;
      }
    }
  }

  NotificationDetails _detailsFor(
    PlannedAlarm alarm,
    NotificationText text, {
    required bool voiceSpoken,
  }) {
    switch (alarm.kind) {
      case 'water':
        return NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.channelWater,
            'Water reminders',
            channelDescription:
                'Gentle reminders to drink water through your day.',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            visibility: NotificationVisibility.public,
            enableVibration: true,
            ticker: 'Water reminder',
            styleInformation: BigTextStyleInformation(text.body),
            icon: 'ic_stat_water',
            actions: const [
              AndroidNotificationAction(
                AkashaActions.drankWaterId,
                'I drank water',
                showsUserInterface: false,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                AkashaActions.skipWaterId,
                'Skip',
                showsUserInterface: false,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                AkashaActions.snoozeWaterId,
                'Later',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ],
          ),
          iOS: const DarwinNotificationDetails(presentSound: true),
        );

      case 'medicine':
        return NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.channelMedicine,
            'Medicine reminders',
            channelDescription: 'Your scheduled medicine times, as a calm message.',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            // A message tone, not a siren: medication reminders should feel
            // like a note from someone who cares, not an alarm clock.
            onlyAlertOnce: true,
            icon: 'ic_stat_medicine',
            styleInformation: BigTextStyleInformation(text.body),
            actions: const [
              AndroidNotificationAction(
                AkashaActions.tookMedicineId,
                'I took it',
                showsUserInterface: false,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                AkashaActions.skipMedicineId,
                'Skip',
                showsUserInterface: false,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                AkashaActions.snoozeMedicineId,
                'Later',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ],
          ),
          iOS: const DarwinNotificationDetails(presentSound: true),
        );

      case 'love_note':
        return NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.channelLoveNotes,
            'Little love notes',
            importance: Importance.defaultImportance,
            styleInformation: BigTextStyleInformation(text.body),
          ),
        );

      case 'daily':
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.channelDaily,
            'Daily summary',
            importance: Importance.low,
            priority: Priority.low,
            playSound: false,
          ),
        );

      default: // motivation
        return NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.channelMotivation,
            'Encouragement',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            category: AndroidNotificationCategory.social,
            styleInformation: BigTextStyleInformation(text.body),
          ),
        );
    }
  }

  /// A snooze alarm. Deliberately **not** derived from the original slot id, so
  /// it can never overwrite the next regular reminder (repair R1b).
  Future<bool> scheduleSnooze({
    required String snoozeId,
    required int amountMl,
    required DateTime when,
    required int originalMinute,
    required bool isMedicine,
    String? refId,
    bool exact = true,
    String? voiceLine,
  }) async {
    final title = isMedicine ? 'A gentle nudge, again' : 'Your water is still waiting ♡';
    final body = isMedicine
        ? 'Just checking in about your medicine. Only take it if it is due.'
        : (voiceLine ?? 'You asked me to remind you. One little glass when you can.');

    try {
      await _plugin.zonedSchedule(
        AkashaNotificationIds.snooze(snoozeId),
        title,
        body,
        _toTz(when),
        NotificationDetails(
          android: AndroidNotificationDetails(
            isMedicine ? AppConstants.channelMedicine : AppConstants.channelWater,
            isMedicine ? 'Medicine reminders' : 'Water reminders',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(body),
            actions: [
              AndroidNotificationAction(
                isMedicine
                    ? AkashaActions.tookMedicineId
                    : AkashaActions.drankWaterId,
                isMedicine ? 'I took it' : 'I drank water',
                showsUserInterface: false,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                isMedicine
                    ? AkashaActions.skipMedicineId
                    : AkashaActions.skipWaterId,
                'Skip',
                showsUserInterface: false,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                isMedicine
                    ? AkashaActions.snoozeMedicineId
                    : AkashaActions.snoozeWaterId,
                'Later',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ],
          ),
        ),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.wallClockTime,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        payload: NotificationPayload(
          kind: isMedicine
              ? AkashaActions.payloadMedicine
              : AkashaActions.payloadWater,
          refId: isMedicine ? refId : snoozeId,
          value: amountMl,
          slotMinute: originalMinute,
          dayKey: AkashaDates.key(when),
        ).encode(),
      );
      return true;
    } catch (e) {
      debugPrint('AKASHA: snooze schedule failed: $e');
      return false;
    }
  }

  // ── Cancellation ──────────────────────────────────────────────────────────

  /// Cancels every AKASHA reminder. Only used before a full re-materialisation
  /// and by "pause everything" — the planner then re-registers in the same pass,
  /// so a crash in between costs at most one launch's reminders rather than
  /// leaving stale ones forever.
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('AKASHA: cancelAll failed: $e');
    }
  }

  Future<void> cancelId(int id) async {
    try {
      await _plugin.cancel(id);
    } catch (e) {
      debugPrint('AKASHA: cancel $id failed: $e');
    }
  }

  /// Cancels every water alarm for a single slot across the whole horizon.
  Future<void> cancelWaterSlot(int minuteOfDay, {int horizonDays = 7}) async {
    final today = AkashaDates.today();
    for (var d = 0; d < horizonDays; d++) {
      await cancelId(
        AkashaNotificationIds.water(minuteOfDay, today.add(Duration(days: d))),
      );
    }
  }

  // ── Diagnostics ───────────────────────────────────────────────────────────

  Future<List<PendingNotificationRequest>> pendingRequests() async {
    try {
      return await _plugin.pendingNotificationRequests();
    } catch (e) {
      debugPrint('AKASHA: pendingNotificationRequests failed: $e');
      return const [];
    }
  }

  Future<int> pendingCount() async => (await pendingRequests()).length;

  Future<List<ActiveNotification>> activeNotifications() async {
    try {
      return await _android?.getActiveNotifications() ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Immediate notification, used by "try a reminder" in diagnostics and by the
  /// spoken-reminder test button.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool water = true,
  }) async {
    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          water ? AppConstants.channelWater : AppConstants.channelMotivation,
          water ? 'Water reminders' : 'Encouragement',
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      payload: payload,
    );
  }

  List<NotificationActionEvent> takePendingEvents() {
    final copy = List<NotificationActionEvent>.unmodifiable(_pendingEvents);
    _pendingEvents.clear();
    return copy;
  }

  tz.TZDateTime _toTz(DateTime local) => tz.TZDateTime.from(local, tz.local);
}

/// Title + body for one notification. Separated from [PlannedAlarm] so copy can
/// be rotated without touching scheduling, and so the same text can be spoken.
class NotificationText {
  const NotificationText({required this.title, required this.body});
  final String title;
  final String body;
}

/// Everything the UI layer reports about a notification event.
class NotificationActionEvent {
  const NotificationActionEvent({
    required this.actionId,
    required this.payload,
    required this.respondedAt,
  });

  final int actionId;
  final NotificationPayload payload;
  final DateTime respondedAt;
}
