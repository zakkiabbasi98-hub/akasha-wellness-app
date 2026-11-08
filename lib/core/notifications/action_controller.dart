import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/models/medicine_models.dart';
import '../../data/models/water_models.dart';
import '../../data/repositories/medicine_repository.dart';
import '../../data/repositories/notification_history_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/water_repository.dart';
import '../../data/models/user_settings.dart';
import '../utils/date_utils.dart';
import '../utils/id.dart';
import 'notification_service.dart';
import 'pending_action_queue.dart';
import 'reminder_scheduler.dart';

/// Turns a notification button press into real data — in every app state.
///
/// Paths covered
/// -------------
/// 1. App foregrounded: the plugin callback lands in [handleResponse].
/// 2. App backgrounded: same callback, main isolate alive.
/// 3. App terminated: Android runs the top-level entry point in a headless
///    isolate, which can't safely touch SQLite on every OEM. It appends to
///    [PendingActionQueue]; [drainPending] replays it into the database the
///    next time the app starts (and on every resume).
class NotificationActionController {
  NotificationActionController({
    required this.notifications,
    required this.water,
    required this.medicine,
    required this.profiles,
    required this.history,
    required this.scheduler,
    required this.onDataChanged,
  });

  final NotificationService notifications;
  final WaterRepository water;
  final MedicineRepository medicine;
  final ProfileRepository profiles;
  final NotificationHistoryRepository history;
  final ReminderScheduler scheduler;
  final void Function() onDataChanged;

  /// Wire the plugin → controller bridge.
  Future<void> attach() async {
    BackgroundActionHandler.register(handleResponse);
    BackgroundQueueWriter.register((response, payload) async {
      await PendingActionQueue.instance.push({
        'actionId': response.actionId != null
            ? int.tryParse(response.actionId!) ?? 0
            : 0,
        'payload': response.payload ?? '',
      });
    });
  }

  /// Handles a response in the main isolate. Returns false only on a hard error.
  Future<bool> handleResponse(NotificationResponse response) async {
    final actionId =
        response.actionId != null ? int.tryParse(response.actionId!) ?? 0 : 0;
    final payload = NotificationPayload.decode(response.payload);
    if (payload == null) return false;

    switch (payload.kind) {
      case AkashaActions.payloadWater:
        await _handleWater(actionId, payload);
      case AkashaActions.payloadMedicine:
        await _handleMedicine(actionId, payload);
      case AkashaActions.payloadMotivation:
      case AkashaActions.payloadLoveNote:
      case AkashaActions.payloadDaily:
        await _recordOpen(payload, actionId);
      default:
        return false;
    }
    onDataChanged();
    return true;
  }

  Future<void> _handleWater(int actionId, NotificationPayload payload) async {
    final profile = await profiles.currentProfile();
    if (profile == null) return;
    final settings = await profiles.ensureSettings(profile.id);

    switch (actionId) {
      case AkashaActions.drankWater:
        final amount = payload.value ?? settings.glassSizeMl;
        final log = await water.addLog(
          userId: profile.id,
          amountMl: amount,
          source: WaterLogSource.notification,
          reminderMinute: payload.slotMinute,
          glassSize: _glassLabel(amount, settings),
        );
        await _recordAction(
          kind: 'water',
          refId: log.id,
          title: 'Water reminder',
          body: 'Logged from notification',
          action: 'taken',
        );
      case AkashaActions.skipWater:
        await _recordAction(
          kind: 'water',
          refId: null,
          title: 'Water reminder',
          body: 'Skipped from notification',
          action: 'skipped',
        );
      case AkashaActions.snoozeWater:
        final when = DateTime.now().add(Duration(minutes: settings.snoozeMinutes));
        final snooze = await water.createSnooze(
          userId: profile.id,
          reminderMinute: payload.slotMinute ?? AkashaDates.nowMinutes(),
          scheduledFor: when,
        );
        await notifications.scheduleSnooze(
          snoozeId: snooze.id,
          amountMl: payload.value ?? settings.glassSizeMl,
          when: when,
          originalMinute: payload.slotMinute ?? AkashaDates.nowMinutes(),
          isMedicine: false,
        );
        await _recordAction(
          kind: 'water',
          refId: snooze.id,
          title: 'Water reminder',
          body: 'Snoozed for ${settings.snoozeMinutes} minutes',
          action: 'snoozed',
        );
      default:
        await _recordOpen(payload, actionId);
    }
  }

  Future<void> _handleMedicine(int actionId, NotificationPayload payload) async {
    final profile = await profiles.currentProfile();
    if (profile == null) return;
    final settings = await profiles.ensureSettings(profile.id);
    final logId = payload.refId;

    switch (actionId) {
      case AkashaActions.tookMedicine:
        if (logId == null) return;
        await medicine.recordResponse(logId: logId, status: DoseStatus.taken);
        await _recordAction(
          kind: 'medicine',
          refId: logId,
          title: 'Medicine reminder',
          body: 'Marked as taken',
          action: 'taken',
        );
      case AkashaActions.skipMedicine:
        if (logId == null) return;
        await medicine.recordResponse(logId: logId, status: DoseStatus.skipped);
        await _recordAction(
          kind: 'medicine',
          refId: logId,
          title: 'Medicine reminder',
          body: 'Marked as skipped',
          action: 'skipped',
        );
      case AkashaActions.snoozeMedicine:
        if (logId == null) return;
        final when = DateTime.now().add(Duration(minutes: settings.snoozeMinutes));
        await medicine.recordResponse(
          logId: logId,
          status: DoseStatus.snoozed,
          snoozedUntil: when,
        );
        await notifications.scheduleSnooze(
          snoozeId: snoozeIdFor(logId),
          amountMl: 0,
          when: when,
          originalMinute: payload.slotMinute ?? AkashaDates.nowMinutes(),
          isMedicine: true,
          refId: logId,
        );
        await _recordAction(
          kind: 'medicine',
          refId: logId,
          title: 'Medicine reminder',
          body: 'Snoozed',
          action: 'snoozed',
        );
      default:
        await _recordOpen(payload, actionId);
    }
  }

  Future<void> _recordOpen(NotificationPayload payload, int actionId) async {
    final profile = await profiles.currentProfile();
    if (profile == null) return;
    await _recordAction(
      kind: payload.kind,
      refId: payload.refId,
      title: payload.kind,
      body: 'Opened from notification',
      action: 'opened',
    );
  }

  Future<void> _recordAction({
    required String kind,
    required String? refId,
    required String title,
    required String body,
    required String action,
  }) async {
    final profile = await profiles.currentProfile();
    if (profile == null) return;
    final existing = await history.latestFor(
      userId: profile.id,
      kind: kind,
      refId: refId,
      onDay: DateTime.now(),
    );
    if (existing != null) {
      await history.recordAction(id: existing.id, action: action);
    } else {
      final created = await history.record(
        userId: profile.id,
        kind: kind,
        title: title,
        body: body,
        refId: refId,
      );
      await history.recordAction(id: created.id, action: action);
    }
  }

  String? _glassLabel(int amount, UserSettings settings) {
    if (amount == settings.smallGlassMl) return 'small';
    if (amount == settings.glassSizeMl) return 'medium';
    if (amount == settings.largeGlassMl) return 'large';
    return 'custom';
  }

  /// Replays actions captured while the app was dead. Returns how many were
  /// applied so the dashboard can show an honest "1 glass added while you were
  /// away" message.
  Future<int> drainPending() async {
    final queued = await PendingActionQueue.instance.drain();
    if (queued.isEmpty) return 0;
    var applied = 0;
    for (final item in queued) {
      try {
        final response = NotificationResponse(
          notificationId: 0,
          actionId: (item['actionId'] as int?)?.toString(),
          payload: item['payload'] as String?,
        );
        final ok = await handleResponse(response);
        if (ok) applied++;
      } catch (e) {
        debugPrint('AKASHA: failed to replay queued action: $e');
      }
    }
    if (applied > 0) {
      await scheduler.applyWaterEdit(
        (await profiles.currentProfile())?.id ?? 'local-profile',
      );
      onDataChanged();
    }
    return applied;
  }

  /// Snooze id helper shared with tests.
  static String snoozeIdFor(String logId) => Ids.slotId('medsnooze', logId);
}
