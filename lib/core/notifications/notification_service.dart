import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../content/motivation_content.dart';
import '../constants/app_constants.dart';
import 'notification_ids.dart';

/// Action ids used by the notification buttons. Kept as ints because that is
/// what Android's action callbacks give back.
abstract final class AkashaActions {
  static const int drankWater = 1;
  static const int skipWater = 2;
  static const int snoozeWater = 3;
  static const int tookMedicine = 10;
  static const int skipMedicine = 11;
  static const int snoozeMedicine = 12;
  static const int openApp = 20;

  static const String payloadWater = 'water';
  static const String payloadMedicine = 'medicine';
  static const String payloadMotivation = 'motivation';
  static const String payloadLoveNote = 'love_note';
  static const String payloadDaily = 'daily';
}

/// Payload format: `kind|refId|extraInt`
/// e.g. `water|540|250` or `medicine|medlog-id|480`
class NotificationPayload {
  const NotificationPayload({
    required this.kind,
    this.refId,
    this.value,
    this.slotMinute,
  });

  final String kind;
  final String? refId;
  final int? value;
  final int? slotMinute;

  String encode() => [kind, refId ?? '', value?.toString() ?? '', slotMinute?.toString() ?? '']
      .join('|');

  static NotificationPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final parts = raw.split('|');
    return NotificationPayload(
      kind: parts.isNotEmpty ? parts[0] : '',
      refId: parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null,
      value: parts.length > 2 && parts[2].isNotEmpty ? int.tryParse(parts[2]) : null,
      slotMinute:
          parts.length > 3 && parts[3].isNotEmpty ? int.tryParse(parts[3]) : null,
    );
  }
}

/// Top-level entry point required by flutter_local_notifications.
///
/// MUST be a top-level (or static) function: Android invokes it in a separate
/// isolate when the app is terminated. It deliberately does almost nothing —
/// it appends the action to the durable queue — so it cannot fail on an OEM
/// device that kills us while opening SQLite.
@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) async {
  // Import is deferred to keep this function allocation-light.
  await BackgroundActionHandler.handle(response);
}

/// Static holder so the background entry point has no constructor dependency.
abstract final class BackgroundActionHandler {
  static Future<bool> Function(NotificationResponse response)? _delegate;

  /// Registered by the main isolate during bootstrap. In the background
  /// isolate this is null, so the built-in queue-only path runs instead.
  static void register(Future<bool> Function(NotificationResponse) delegate) {
    _delegate = delegate;
  }

  static Future<void> handle(NotificationResponse response) async {
    final delegate = _delegate;
    if (delegate != null) {
      try {
        await delegate(response);
        return;
      } catch (e) {
        debugPrint('AKASHA background delegate failed: $e');
      }
    }
    // Headless path: persist for the next app launch.
    final payload = NotificationPayload.decode(response.payload);
    await BackgroundQueueWriter.enqueue(response, payload);
  }
}

/// Thin indirection so notification_service.dart does not import dart:io
/// utilities in the entry point path.
abstract final class BackgroundQueueWriter {
  static Future<void> Function(NotificationResponse, NotificationPayload?)?
      _writer;

  static void register(
    Future<void> Function(NotificationResponse, NotificationPayload?) writer,
  ) {
    _writer = writer;
  }

  static Future<void> enqueue(
    NotificationResponse response,
    NotificationPayload? payload,
  ) async {
    final writer = _writer;
    if (writer == null) {
      debugPrint(
        'AKASHA: background action received without persistence '
        '(actionId=${response.actionId}, payload=${response.payload})',
      );
      return;
    }
    await writer(response, payload);
  }
}

/// What the user did on a notification, normalised.
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

/// Schedules and shows every local notification in the app.
///
/// Design notes
/// ------------
/// * All times are *local wall-clock* in the device timezone (via the
///   `timezone` database), so a reminder set for 09:00 stays at 09:00 across a
///   DST shift or a flight.
/// * Recurring reminder slots are materialised day-by-day over a 7-day horizon
///   instead of using `matchDateTimeComponents: DateTimeComponents.time`.
///   Reason: with matchDateTimeComponents the payload cannot vary per day, and
///   medicine notifications *must* carry the day key. A rolling horizon is
///   re-materialised on every app launch, after boot, and after timezone
///   changes — which is also what makes duplicate suppression testable.
/// * Ids are deterministic (see [AkashaNotificationIds]) so scheduling twice
///   replaces rather than duplicates.
class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel waterChannel = AndroidNotificationChannel(
    AppConstants.channelWater,
    'Water reminders',
    description: 'Gentle reminders to drink water through your day.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel medicineChannel = AndroidNotificationChannel(
    AppConstants.channelMedicine,
    'Medicine reminders',
    description: 'Your scheduled medicine times, as a calm message.',
    importance: Importance.high,
    playSound: true,
    enableVibration: true,
  );

  static const AndroidNotificationChannel motivationChannel = AndroidNotificationChannel(
    AppConstants.channelMotivation,
    'Encouragement',
    description: 'Small supportive messages during your day.',
    importance: Importance.defaultImportance,
    playSound: true,
  );

  static const AndroidNotificationChannel loveNoteChannel = AndroidNotificationChannel(
    AppConstants.channelLoveNotes,
    'Little love notes',
    description: 'Warm notes from someone who cares.',
    importance: Importance.defaultImportance,
    playSound: true,
  );

  static const AndroidNotificationChannel dailyChannel = AndroidNotificationChannel(
    AppConstants.channelDaily,
    'Daily summary',
    description: 'A quiet evening summary of your day.',
    importance: Importance.low,
    playSound: false,
  );

  bool _initialised = false;
  NotificationSettings? _settings;
  final List<NotificationActionEvent> _pendingEvents = [];
  final math.Random _random = math.Random();

  /// Set by the app so the UI can react to notification taps that arrive while
  /// running (e.g. open the water screen).
  void Function(NotificationPayload payload)? onForegroundTap;

  bool get isInitialised => _initialised;

  Future<bool> initialize({
    void Function(NotificationResponse response)? onForegroundResponse,
  }) async {
    if (_initialised) return true;

    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation(await _deviceTimeZoneName()));

      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: false,
        requestSoundPermission: true,
      );
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
      );

      final ok = await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          _pendingEvents.add(NotificationActionEvent(
            actionId: response.actionId != null ? int.tryParse(response.actionId!) ?? 0 : 0,
            payload: NotificationPayload.decode(response.payload) ??
                const NotificationPayload(kind: 'unknown'),
            respondedAt: DateTime.now(),
          ));
          onForegroundResponse?.call(response);
          final payload = NotificationPayload.decode(response.payload);
          if (payload != null) onForegroundTap?.call(payload);
        },
        // Headless callback: Android uses this when the app is terminated.
        onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationResponse,
      );

      _initialised = ok ?? false;
      if (_initialised) await _createChannels();
      return _initialised;
    } catch (e, st) {
      debugPrint('AKASHA: notification init failed: $e\n$st');
      return false;
    }
  }

  Future<String> _deviceTimeZoneName() async => _fallbackZoneName();

  /// Maps the device's current UTC offset onto a zone name that exists in the
  /// tz database. We cannot read the IANA name without an extra plugin, but
  /// every name we return produces the same wall-clock offset, which is all
  /// scheduling needs.
  ///
  /// A DST transition is handled by the app re-materialising the whole horizon
  /// (see ReminderScheduler) on launch, on the native TIME_SET/TIMEZONE_CHANGED
  /// broadcast, and in the daily background pass.
  String _fallbackZoneName() {
    final offset = DateTime.now().timeZoneOffset;
    if (offset == Duration.zero) return 'UTC';
    const known = [
      'Asia/Karachi',
      'Asia/Kolkata',
      'Asia/Dhaka',
      'Asia/Dubai',
      'Asia/Riyadh',
      'Asia/Jakarta',
      'Asia/Singapore',
      'Asia/Tokyo',
      'Europe/London',
      'Europe/Berlin',
      'Europe/Paris',
      'Europe/Istanbul',
      'America/New_York',
      'America/Chicago',
      'America/Denver',
      'America/Los_Angeles',
      'America/Sao_Paulo',
      'Africa/Cairo',
      'Africa/Lagos',
      'Australia/Sydney',
      'Pacific/Auckland',
    ];
    for (final name in known) {
      try {
        final loc = tz.getLocation(name);
        if (tz.TZDateTime.now(loc).timeZoneOffset == offset) return name;
      } catch (_) {
        continue;
      }
    }
    // Fixed-offset fallback for whole-hour zones (Etc/GMT signs are inverted).
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
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return;
    for (final channel in [
      waterChannel,
      medicineChannel,
      motivationChannel,
      loveNoteChannel,
      dailyChannel,
    ]) {
      await android.createNotificationChannel(channel);
    }
  }

  // ── Permission helpers ──────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final granted = await android.requestNotificationsPermission();
    _settings = NotificationSettings();
    return granted ?? false;
  }

  Future<bool> areNotificationsEnabled() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    final enabled = await android.areNotificationsEnabled();
    _settings = NotificationSettings();
    return enabled ?? false;
  }

  Future<bool> requestExactAlarmsPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    return await android.requestExactAlarmsPermission() ?? false;
  }

  Future<bool> canScheduleExactAlarms() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    return await android.canScheduleExactNotifications() ?? false;
  }

  Future<bool> areFullScreenIntentsAllowed() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    return await android.canUseFullScreenIntent() ?? false;
  }

  NotificationSettings? get lastSettings => _settings;

  // ── Water ───────────────────────────────────────────────────────────────

  /// Schedules one daily reminder slot across the horizon.
  Future<void> scheduleWaterSlot({
    required int minuteOfDay,
    required int amountMl,
    required int horizonDays,
    required bool exact,
    String? customTitle,
    String? customBody,
    bool alarmStyle = true,
  }) async {
    final copy = customTitle != null && customBody != null
        ? [customTitle, customBody]
        : kWaterNotificationCopy[_random.nextInt(kWaterNotificationCopy.length)];
    final voiceLine = kWaterVoiceLines[_random.nextInt(kWaterVoiceLines.length)];

    for (var dayOffset = 0; dayOffset < horizonDays; dayOffset++) {
      final when = _nextInstanceOf(minuteOfDay, dayOffset: dayOffset);
      if (when == null) continue;
      if (when.isBefore(DateTime.now())) continue;

      await _plugin.zonedSchedule(
        AkashaNotificationIds.water(minuteOfDay),
        copy[0],
        copy[1],
        _toTz(when),
        NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.channelWater,
            'Water reminders',
            channelDescription: 'Gentle reminders to drink water through your day.',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            // Head-up + the alarm-style full screen on the most recent slot
            // only; when the OS refuses a full screen intent it silently
            // degrades to a heads-up notification (which is the honest,
            // policy-compliant outcome).
            fullScreenIntent: alarmStyle && dayOffset == 0,
            visibility: NotificationVisibility.public,
            enableVibration: true,
            ticker: 'Water reminder',
            styleInformation: BigTextStyleInformation(copy[1]),
            icon: 'ic_stat_water',
            actions: const [
              AndroidNotificationAction(
                AkashaActions.drankWater,
                'I drank water',
                showsUserInterface: false,
                cancelNotification: true,
                icon: DrawableResourceAndroidBitmap('ic_stat_water'),
              ),
              AndroidNotificationAction(
                AkashaActions.skipWater,
                'Skip',
                showsUserInterface: false,
                cancelNotification: true,
              ),
              AndroidNotificationAction(
                AkashaActions.snoozeWater,
                'Later',
                showsUserInterface: false,
                cancelNotification: true,
              ),
            ],
          ),
          iOS: const DarwinNotificationDetails(presentSound: true),
        ),
        androidScheduleMode:
            exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexact,
        payload: NotificationPayload(
          kind: AkashaActions.payloadWater,
          refId: voiceLine,
          value: amountMl,
          slotMinute: minuteOfDay,
        ).encode(),
        // No matchDateTimeComponents: we materialise the horizon ourselves.
      );
    }
  }

  // ── Medicine ────────────────────────────────────────────────────────────

  Future<void> scheduleMedicineDose({
    required String logId,
    required String medicineName,
    required DateTime when,
    required int minuteOfDay,
    required bool exact,
    required bool alarmStyle,
  }) async {
    if (when.isBefore(DateTime.now())) return;
    final copy = kMedicineNotificationCopy[
        _random.nextInt(kMedicineNotificationCopy.length)];
    final body = copy[1].replaceFirst('your medicine', medicineName);

    await _plugin.zonedSchedule(
      AkashaNotificationIds.medicine(
        logId,
        _dayKey(when),
        minuteOfDay,
      ),
      copy[0],
      body,
      _toTz(when),
      NotificationDetails(
        android: AndroidNotificationDetails(
          AppConstants.channelMedicine,
          'Medicine reminders',
          channelDescription: 'Your scheduled medicine times, as a calm message.',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          // A quiet message tone, not an alarm — medication reminders should
          // feel like a note, not a siren.
          playSound: true,
          fullScreenIntent: false,
          onlyAlertOnce: true,
          icon: 'ic_stat_medicine',
          styleInformation: BigTextStyleInformation(
            '$body\n\n$medicineName',
          ),
          actions: const [
            AndroidNotificationAction(
              AkashaActions.tookMedicine,
              'I took it',
              showsUserInterface: false,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              AkashaActions.skipMedicine,
              'Skip',
              showsUserInterface: false,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              AkashaActions.snoozeMedicine,
              'Later',
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(presentSound: true),
      ),
      androidScheduleMode:
          exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexact,
      payload: NotificationPayload(
        kind: AkashaActions.payloadMedicine,
        refId: logId,
        slotMinute: minuteOfDay,
      ).encode(),
    );
  }

  // ── Snooze ──────────────────────────────────────────────────────────────

  Future<void> scheduleSnooze({
    required String snoozeId,
    required int amountMl,
    required DateTime when,
    required int originalMinute,
    required bool isMedicine,
    String? refId,
    bool exact = true,
  }) async {
    final title = isMedicine ? 'A gentle nudge, again' : 'Your water is still waiting ♡';
    final body = isMedicine
        ? 'Just checking in about your medicine. Only take it if it is due.'
        : 'You asked me to remind you. One little glass when you can.';

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
          fullScreenIntent: !isMedicine,
          actions: [
            AndroidNotificationAction(
              isMedicine ? AkashaActions.tookMedicine : AkashaActions.drankWater,
              isMedicine ? 'I took it' : 'I drank water',
              showsUserInterface: false,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              AkashaActions.skipWater,
              'Skip',
              showsUserInterface: false,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              AkashaActions.snoozeWater,
              'Later',
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
          styleInformation: BigTextStyleInformation(body),
        ),
      ),
      androidScheduleMode:
          exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexact,
      payload: NotificationPayload(
        kind: isMedicine ? AkashaActions.payloadMedicine : AkashaActions.payloadWater,
        refId: isMedicine ? refId : null,
        value: amountMl,
        slotMinute: originalMinute,
      ).encode(),
    );
  }

  // ── Encouragement / love notes / daily summary ──────────────────────────

  Future<void> scheduleMotivation({
    required int minuteOfDay,
    required String message,
    required int horizonDays,
    required bool exact,
  }) async {
    for (var dayOffset = 0; dayOffset < horizonDays; dayOffset++) {
      final when = _nextInstanceOf(minuteOfDay, dayOffset: dayOffset);
      if (when == null || when.isBefore(DateTime.now())) continue;
      await _plugin.zonedSchedule(
        AkashaNotificationIds.motivation(minuteOfDay) + dayOffset,
        'For you, Akasha',
        message,
        _toTz(when),
        NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.channelMotivation,
            'Encouragement',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            styleInformation: BigTextStyleInformation(message),
            category: AndroidNotificationCategory.social,
          ),
        ),
        androidScheduleMode:
            exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexact,
        payload: const NotificationPayload(kind: AkashaActions.payloadMotivation).encode(),
      );
    }
  }

  Future<void> scheduleLoveNote({
    required String noteId,
    required String text,
    required String author,
    required int minuteOfDay,
    required int horizonDays,
    required bool exact,
  }) async {
    for (var dayOffset = 0; dayOffset < horizonDays; dayOffset++) {
      final when = _nextInstanceOf(minuteOfDay, dayOffset: dayOffset);
      if (when == null || when.isBefore(DateTime.now())) continue;
      await _plugin.zonedSchedule(
        AkashaNotificationIds.loveNote(minuteOfDay) + dayOffset,
        'A little love note',
        text,
        _toTz(when),
        NotificationDetails(
          android: AndroidNotificationDetails(
            AppConstants.channelLoveNotes,
            'Little love notes',
            importance: Importance.defaultImportance,
            styleInformation: BigTextStyleInformation('$text\n\n— $author'),
          ),
        ),
        androidScheduleMode:
            exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexact,
        payload: NotificationPayload(
          kind: AkashaActions.payloadLoveNote,
          refId: noteId,
        ).encode(),
      );
    }
  }

  Future<void> scheduleDailySummary({required int minuteOfDay, required bool exact}) async {
    final when = _nextInstanceOf(minuteOfDay, dayOffset: 0);
    if (when == null) return;
    await _plugin.zonedSchedule(
      AkashaNotificationIds.dailyReport,
      'Your day, gently wrapped up',
      'Tap to see how you cared for yourself today.',
      _toTz(when.isBefore(DateTime.now()) ? when.add(const Duration(days: 1)) : when),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          AppConstants.channelDaily,
          'Daily summary',
          importance: Importance.low,
          priority: Priority.low,
          playSound: false,
        ),
      ),
      androidScheduleMode:
          exact ? AndroidScheduleMode.exactAllowWhileIdle : AndroidScheduleMode.inexact,
      payload: const NotificationPayload(kind: AkashaActions.payloadDaily).encode(),
    );
  }

  // ── Management ──────────────────────────────────────────────────────────

  /// Cancels every AKASHA reminder. Used before a full re-materialisation,
  /// when pausing reminders, and when the user resets the app.
  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('AKASHA: cancelAll failed: $e');
    }
  }

  Future<void> cancelWaterSlots(Iterable<int> minutes) async {
    for (final m in minutes) {
      try {
        await _plugin.cancel(AkashaNotificationIds.water(m));
      } catch (e) {
        debugPrint('AKASHA: cancel water $m failed: $e');
      }
    }
  }

  Future<PendingNotificationRequest[]> pendingRequests() async {
    try {
      return await _plugin.pendingNotificationRequests();
    } catch (e) {
      debugPrint('AKASHA: pendingNotificationRequests failed: $e');
      return const [];
    }
  }

  Future<int> pendingCount() async => (await pendingRequests()).length;

  Future<List<ActiveNotification>> activeNotifications() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      return await android?.getActiveNotifications() ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Shows an immediate notification (used by "Try a reminder" diagnostics and
  /// by the in-app reminder screen fallback).
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

  /// Consumes any notification actions that arrived while the UI was alive.
  List<NotificationActionEvent> takePendingEvents() {
    final copy = List<NotificationActionEvent>.unmodifiable(_pendingEvents);
    _pendingEvents.clear();
    return copy;
  }

  // ── Time helpers ────────────────────────────────────────────────────────

  /// Next wall-clock instance of [minuteOfDay], optionally [dayOffset] days on.
  /// Returns null only for invalid input.
  DateTime? _nextInstanceOf(int minuteOfDay, {int dayOffset = 0}) {
    if (minuteOfDay < 0 || minuteOfDay >= 24 * 60) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.add(Duration(days: dayOffset, minutes: minuteOfDay));
  }

  tz.TZDateTime _toTz(DateTime local) => tz.TZDateTime.from(local, tz.local);

  String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
