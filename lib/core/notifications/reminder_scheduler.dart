import 'package:flutter/foundation.dart';

import '../../data/models/medicine_models.dart';
import '../../data/models/mind_models.dart';
import '../../data/models/user_settings.dart';
import '../../data/models/water_models.dart';
import '../../data/repositories/love_note_repository.dart';
import '../../data/repositories/medicine_repository.dart';
import '../../data/repositories/motivation_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/water_repository.dart';
import '../constants/app_constants.dart';
import '../utils/date_utils.dart';
import 'notification_service.dart';

/// The single place that decides *what* is scheduled.
///
/// Screens never schedule notifications directly — they ask this class, which
/// always does a full, idempotent re-materialisation. That is what prevents
/// duplicates after edits, reboots, timezone changes and app updates: there is
/// exactly one code path that owns the alarm set.
class ReminderScheduler {
  ReminderScheduler({
    required this.notifications,
    required this.water,
    required this.medicine,
    required this.motivations,
    required this.loveNotes,
    required this.profiles,
  });

  final NotificationService notifications;
  final WaterRepository water;
  final MedicineRepository medicine;
  final MotivationRepository motivations;
  final LoveNoteRepository loveNotes;
  final ProfileRepository profiles;

  /// Full rebuild. Call on launch, after boot, after timezone change, and after
  /// any settings/reminder edit.
  Future<SchedulingReport> rescheduleAll({bool exact = false}) async {
    final profile = await profiles.currentProfile();
    if (profile == null) {
      return const SchedulingReport(waterSlots: 0, doses: 0, motivations: 0, loveNotes: 0);
    }
    final settings = await profiles.ensureSettings(profile.id);

    // Clear everything first: a full rebuild must be idempotent. Notification
    // ids are deterministic so even a partial failure cannot duplicate.
    await notifications.cancelAll();

    final waterCount = await _scheduleWater(profile.id, settings, exact: exact);
    final doseCount = await _scheduleMedicine(profile.id, settings, exact: exact);
    final motivationCount = await _scheduleMotivation(profile.id, settings, exact: exact);
    final noteCount = await _scheduleLoveNotes(profile.id, settings, exact: exact);
    await notifications.scheduleDailySummary(minuteOfDay: 20 * 60 + 30, exact: exact);

    final report = SchedulingReport(
      waterSlots: waterCount,
      doses: doseCount,
      motivations: motivationCount,
      loveNotes: noteCount,
    );
    debugPrint('AKASHA reschedule → $report');
    return report;
  }

  // ── Water ───────────────────────────────────────────────────────────────

  Future<int> _scheduleWater(
    String userId,
    UserSettings settings, {
    required bool exact,
  }) async {
    if (settings.waterRemindersPaused) return 0;

    final reminders = await water.enabledReminders(userId);
    if (reminders.isEmpty) return 0;

    final horizon = AppConstants.scheduleHorizonDays;
    final quiet = _QuietWindow.from(settings);

    var scheduled = 0;
    for (final reminder in reminders) {
      if (quiet.pausesWater && quiet.wouldSuppress(reminder.minuteOfDay)) {
        // Quiet hours: a water reminder at 23:00 during a 22:30–07:00 quiet
        // window is dropped, not delayed. She can still see it in the app.
        continue;
      }
      await notifications.scheduleWaterSlot(
        minuteOfDay: reminder.minuteOfDay,
        amountMl: reminder.amountMl,
        horizonDays: horizon,
        exact: exact,
        alarmStyle: settings.alarmStyle,
      );
      scheduled += horizon;
    }

    // Re-arm any pending snoozes so they survive app restarts.
    for (final snooze in await water.pendingSnoozes(userId)) {
      if (snooze.scheduledFor.isAfter(DateTime.now())) {
        await notifications.scheduleSnooze(
          snoozeId: snooze.id,
          amountMl: settings.glassSizeMl,
          when: snooze.scheduledFor,
          originalMinute: snooze.reminderMinute,
          isMedicine: false,
          exact: exact,
        );
        scheduled++;
      } else {
        await water.cancelSnooze(snooze.id);
      }
    }
    return scheduled;
  }

  // ── Medicine ────────────────────────────────────────────────────────────

  Future<int> _scheduleMedicine(
    String userId,
    UserSettings settings, {
    required bool exact,
  }) async {
    if (settings.medicineRemindersPaused) return 0;

    final medicines = await medicine.all(userId, includeDisabled: false);
    var scheduled = 0;
    final now = DateTime.now();
    final quiet = _QuietWindow.from(settings);

    for (final med in medicines) {
      for (var dayOffset = 0; dayOffset < AppConstants.scheduleHorizonDays; dayOffset++) {
        final day = AkashaDates.today().add(Duration(days: dayOffset));
        if (!med.isDueOn(day)) continue;
        for (final minute in med.reminderMinutes) {
          final when = AkashaDates.withMinutes(day, minute);
          if (when.isBefore(now)) continue;
          // Medicine reminders are NOT silenced by quiet hours unless she
          // explicitly opted in (settings.quietPauseMedicine) — silently
          // dropping a prescribed dose would be a real harm.
          if (quiet.pausesMedicine && quiet.wouldSuppress(minute)) {
            continue;
          }
          // The notification payload must carry the *log row id*, because that
          // is what "I took it" marks. The id is deterministic (see
          // MedicineRepository.logIdFor), so the row is addressable even if
          // it has not been materialised yet on this device.
          await notifications.scheduleMedicineDose(
            logId: MedicineRepository.logIdFor(
              medicineId: med.id,
              day: day,
              minute: minute,
            ),
            medicineName: med.name,
            when: when,
            minuteOfDay: minute,
            exact: exact,
            alarmStyle: settings.alarmStyle,
          );
          scheduled++;
        }
      }
    }
    return scheduled;
  }

  // ── Encouragement ───────────────────────────────────────────────────────

  Future<int> _scheduleMotivation(
    String userId,
    UserSettings settings, {
    required bool exact,
  }) async {
    if (!settings.motivationEnabled) return 0;

    final quiet = _QuietWindow.from(settings);
    final categories = settings.motivationCategories
        .map(MotivationCategory.fromKey)
        .toList();
    final minutes = await motivations.scheduledMinutes(userId);
    var scheduled = 0;

    for (final minute in minutes) {
      // Encouragement is the one kind of notification that should always
      // respect quiet hours when the user asked it to.
      if (quiet.pausesMotivation && quiet.wouldSuppress(minute)) continue;

      final message = await motivations.nextMessage(categories: categories);
      if (message == null) continue;

      await motivations.markShown(message.id);
      await notifications.scheduleMotivation(
        minuteOfDay: minute,
        message: message.text,
        horizonDays: AppConstants.scheduleHorizonDays,
        exact: exact,
      );
      scheduled++;
    }
    return scheduled;
  }

  // ── Love notes ──────────────────────────────────────────────────────────

  Future<int> _scheduleLoveNotes(
    String userId,
    UserSettings settings, {
    required bool exact,
  }) async {
    if (!settings.loveNotesEnabled) return 0;
    final notes = await loveNotes.enabled(userId);
    var scheduled = 0;
    for (final note in notes) {
      final minute = note.minuteOfDay;
      if (minute == null) continue;
      await notifications.scheduleLoveNote(
        noteId: note.id,
        text: note.text,
        author: note.author,
        minuteOfDay: minute,
        horizonDays: AppConstants.scheduleHorizonDays,
        exact: exact,
      );
      scheduled++;
    }
    return scheduled;
  }

  // ── Targeted updates (cheap, used after a single edit) ──────────────────

  Future<void> applyWaterEdit(String userId) async {
    final settings = await profiles.ensureSettings(userId);
    final exact = await notifications.canScheduleExactAlarms();
    await notifications.cancelAll();
    await _scheduleWater(userId, settings, exact: exact);
    await _scheduleMedicine(userId, settings, exact: exact);
    await _scheduleMotivation(userId, settings, exact: exact);
    await _scheduleLoveNotes(userId, settings, exact: exact);
  }

  /// Pause / resume all water reminders without losing the slot definitions.
  Future<void> setWaterPaused({required bool paused}) async {
    final profile = await profiles.currentProfile();
    if (profile == null) return;
    await profiles.mutateSettings((s) => s.copyWith(waterRemindersPaused: paused));
    await rescheduleAll(exact: await notifications.canScheduleExactAlarms());
  }
}

class _QuietWindow {
  const _QuietWindow({
    required this.enabled,
    required this.startMinute,
    required this.endMinute,
    required this.pausesWater,
    required this.pausesMotivation,
    required this.pausesMedicine,
  });

  factory _QuietWindow.from(UserSettings s) => _QuietWindow(
        enabled: s.quietModeEnabled,
        startMinute: s.quietStartMin,
        endMinute: s.quietEndMin,
        pausesWater: s.quietPauseWater,
        pausesMotivation: s.quietPauseMotivation,
        pausesMedicine: s.quietPauseMedicine,
      );

  final bool enabled;
  final int startMinute;
  final int endMinute;
  final bool pausesWater;
  final bool pausesMotivation;
  final bool pausesMedicine;

  bool wouldSuppress(int minuteOfDay) {
    if (!enabled) return false;
    if (startMinute == endMinute) return false;
    if (startMinute < endMinute) {
      return minuteOfDay >= startMinute && minuteOfDay < endMinute;
    }
    return minuteOfDay >= startMinute || minuteOfDay < endMinute;
  }
}

class SchedulingReport {
  const SchedulingReport({
    required this.waterSlots,
    required this.doses,
    required this.motivations,
    required this.loveNotes,
  });

  final int waterSlots;
  final int doses;
  final int motivations;
  final int loveNotes;

  int get total => waterSlots + doses + motivations + loveNotes;

  @override
  String toString() =>
      'water=$waterSlots doses=$doses motivation=$motivations notes=$loveNotes';
}

/// Normalises a collection of enabled water reminders into minute values.
List<int> minutesOf(List<WaterReminder> reminders) =>
    reminders.map((r) => r.minuteOfDay).toList()..sort();

/// Convenience used by the medicine editor to validate times.
bool hasDuplicateMinutes(List<int> minutes) =>
    minutes.length != minutes.toSet().length;

/// Small helper so the medicine page can show today's remaining doses.
int remainingDoses(List<DoseView> doses, DateTime now) {
  final minutes = now.hour * 60 + now.minute;
  return doses
      .where((d) =>
          d.log.status == DoseStatus.scheduled && d.log.scheduledMinute >= minutes)
      .length;
}
