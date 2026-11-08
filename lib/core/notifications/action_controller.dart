import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/models/user_settings.dart';
import '../database/app_database.dart';
import '../utils/date_utils.dart';
import 'background_actions.dart';
import 'notification_service.dart';
import 'reminder_scheduler.dart';

/// UI-isolate companion to [BackgroundActionEngine].
///
/// Responsibilities are deliberately narrow now (repair R2): **all** database
/// work happens in [ActionExecutor], which the headless isolate also uses. This
/// class only:
///
///  1. forwards taps that arrive while the app is alive into the same executor,
///  2. replays the durable queue on launch and on every resume,
///  3. tells the UI to refresh, and
///  4. re-runs the alarm planner when an action changes the schedule.
///
/// The previous version re-implemented the write logic here *and* relied on
/// statics being seeded by the main isolate, which is exactly why background
/// actions could be lost. There is now one code path, not two.
class NotificationActionController {
  NotificationActionController({
    required this.notifications,
    required this.scheduler,
    required this.database,
    required this.onDataChanged,
  });

  final NotificationService notifications;
  final ReminderScheduler scheduler;
  final AppDatabase database;
  final void Function() onDataChanged;

  late final ActionExecutor _executor = ActionExecutor(database);

  /// Wires the foreground tap stream. No static registration any more: the
  /// background isolate is self-sufficient, so nothing has to survive a
  /// process boundary in static state.
  Future<void> attach() async {
    await notifications.initialize(
      onForegroundResponse: (response) => _handleForeground(response),
    );
  }

  Future<void> _handleForeground(NotificationResponse response) async {
    final actionId = int.tryParse(response.actionId ?? '') ?? 0;
    final payload = NotificationPayload.decode(response.payload);
    if (payload == null || actionId == 0) return;

    final event = ActionEvent(
      actionId: actionId,
      payload: payload,
      respondedAt: DateTime.now(),
    );
    try {
      final applied = await _executor.execute(event);
      if (applied) {
        await _executor.rescheduleIfNeeded(event);
        onDataChanged();
        if (_changesSchedule(actionId)) await scheduler.rescheduleAll();
      }
    } catch (e) {
      debugPrint('AKASHA: foreground action failed, queueing: $e');
      // Same durability guarantee as the background path.
      await PendingActionQueue.instance.push({
        'actionId': actionId,
        'payload': response.payload ?? '',
        'at': DateTime.now().millisecondsSinceEpoch,
      });
    }
  }

  /// Replays actions captured while the app was dead. Returns how many were
  /// applied so the dashboard can say "1 glass added while you were away"
  /// honestly instead of pretending nothing happened.
  Future<int> drainPending() async {
    final applied = await PendingActionQueue.instance.replay();
    if (applied > 0) {
      onDataChanged();
      await scheduler.rescheduleAll();
    }
    return applied;
  }

  /// Reads the in-memory events the plugin pushed while the UI was alive.
  /// Kept for the diagnostics screen's "recent actions" list.
  List<NotificationActionEvent> takePendingEvents() =>
      notifications.takePendingEvents();

  bool _changesSchedule(int actionId) =>
      actionId == AkashaActions.snoozeWater ||
      actionId == AkashaActions.snoozeMedicine ||
      actionId == AkashaActions.drankWater ||
      actionId == AkashaActions.tookMedicine;

  // ── Helpers kept for the diagnostics screen ───────────────────────────────

  /// Human description of what the last action did, for the settings screen.
  static String describe(int actionId, NotificationPayload payload) {
    final day = payload.dayKey ?? AkashaDates.key(DateTime.now());
    return switch (actionId) {
      AkashaActions.drankWater =>
        'Water logged for $day at slot ${payload.slotMinute ?? 0}',
      AkashaActions.skipWater => 'Water reminder skipped for $day',
      AkashaActions.snoozeWater => 'Water reminder snoozed',
      AkashaActions.tookMedicine => 'Medicine marked taken ($day)',
      AkashaActions.skipMedicine => 'Medicine marked skipped ($day)',
      AkashaActions.snoozeMedicine => 'Medicine snoozed',
      _ => 'Opened from a notification',
    };
  }

  /// Voice profile currently in force — used by the diagnostics screen so the
  /// reported speech state matches what the scheduler actually used.
  static VoiceProfile voiceFor(UserSettings settings) => settings.effectiveVoice;
}
