import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../content/motivation_content.dart';
import '../../data/models/medicine_models.dart';
import '../../data/models/mind_models.dart';
import '../../data/models/user_settings.dart';
import '../../data/repositories/love_note_repository.dart';
import '../../data/repositories/medicine_repository.dart';
import '../../data/repositories/motivation_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/water_repository.dart';
import '../constants/app_constants.dart';
import '../utils/date_utils.dart';
import 'notification_ids.dart';
import 'notification_planner.dart';
import 'notification_service.dart';
import 'spoken_reminders.dart';
import 'voice_plan_service.dart';

/// Applies [NotificationPlanner]'s decisions to the operating system.
///
/// No policy lives here: the planner decides *what* the alarm set should be,
/// this class registers it. That split is what makes the whole notification
/// contract unit-testable without a device.
///
/// Invariants
/// ----------
/// * **Idempotent** — every id is deterministic, so a second full pass replaces
///   rather than duplicates.
/// * **Budgeted** — stops before [AppConstants.maxPendingAlarms]; Android drops
///   alarms silently past its own ceiling and the app must not rely on luck.
/// * **Ordered safely** — water is registered before medicine, so if the budget
///   is ever tight the reminders she will miss least are the ones dropped.
class ReminderScheduler {
  ReminderScheduler({
    required this.notifications,
    required this.water,
    required this.medicine,
    required this.motivations,
    required this.loveNotes,
    required this.profiles,
    required this.voicePlan,
  });

  final NotificationService notifications;
  final WaterRepository water;
  final MedicineRepository medicine;
  final MotivationRepository motivations;
  final LoveNoteRepository loveNotes;
  final ProfileRepository profiles;
  final VoicePlanService voicePlan;

  /// Full rebuild. Call on launch, after boot, after a timezone/clock change,
  /// and after any reminder edit.
  Future<SchedulingReport> rescheduleAll({bool? exact}) async {
    final profile = await profiles.currentProfile();
    if (profile == null) return SchedulingReport.empty;

    final settings = await profiles.ensureSettings(profile.id);
    final useExact = exact ?? await notifications.canScheduleExactAlarms();
    final now = DateTime.now();
    final horizon = AppConstants.scheduleHorizonDays;
    final quiet = quietWindowFrom(settings);
    final voiceOn = SpokenReminders.shouldSpeak(settings.effectiveVoice);

    await notifications.cancelAll();

    var registered = 0;
    var refused = 0;
    var skipped = 0;

    // ── Water ───────────────────────────────────────────────────────────────
    final reminders = await water.enabledReminders(profile.id);
    final amountByMinute = {
      for (final r in reminders) r.minuteOfDay: r.amountMl,
    };
    final waterPlan = NotificationPlanner.planWater(
      minutes: amountByMinute.keys.toList(),
      amountMl: settings.glassSizeMl,
      now: now,
      horizonDays: horizon,
      quiet: quiet,
      paused: settings.waterRemindersPaused,
      voiceLines: voiceOn ? kWaterVoiceLines : const [],
      voiceSeed: DateTime.now().millisecondsSinceEpoch % 997,
    );

    for (final alarm in waterPlan) {
      if (!_hasBudget(registered, refused)) {
        skipped += waterPlan.length - waterPlan.indexOf(alarm);
        break;
      }
      final amount = amountByMinute[alarm.minuteOfDay] ?? settings.glassSizeMl;
      final ok = await notifications.schedulePlanned(
        PlannedAlarm(
          id: alarm.id,
          kind: alarm.kind,
          when: alarm.when,
          minuteOfDay: alarm.minuteOfDay,
          amountMl: amount,
          voiceLine: alarm.voiceLine,
          firstOfDay: alarm.firstOfDay,
        ),
        exact: useExact,
        text: waterCopyFor(alarm),
        voiceSpoken: voiceOn,
      );
      ok ? registered++ : refused++;
    }

    // ── Medicine ────────────────────────────────────────────────────────────
    var medicineScheduled = 0;
    final medicines = await medicine.all(profile.id, includeDisabled: false);
    final dosePlans = <MedicineDosePlan>[];
    final nameById = <String, String>{};
    for (final med in medicines) {
      nameById[med.id] = med.name;
      for (final minute in med.reminderMinutes) {
        dosePlans.add(MedicineDosePlan(
          medicineId: med.id,
          minuteOfDay: minute,
          weekdays: med.weekdays.toSet(),
          startDay: AkashaDates.parseKey(med.startDay),
          endDay: med.endDay == null ? null : AkashaDates.parseKey(med.endDay!),
        ));
      }
    }

    final medicinePlan = NotificationPlanner.planMedicine(
      doses: dosePlans,
      now: now,
      horizonDays: horizon,
      quiet: quiet,
      paused: settings.medicineRemindersPaused,
    );

    for (final alarm in medicinePlan) {
      if (!_hasBudget(registered, refused)) {
        skipped++;
        continue;
      }
      final logId = alarm.refId!;
      final medId = _medicineIdFromLogId(logId);
      final name = nameById[medId] ?? 'your medicine';
      // The body is the spoken line when voice is on, so what she reads and
      // what she is told never disagree.
      final body = voiceOn
          ? SpokenReminders.medicineLineFor(
              occurrence: alarm.when,
              slotMinute: alarm.minuteOfDay,
              medicineName: name,
            )
          : 'It is time for $name. Open AKASHA when you can.';
      final ok = await notifications.schedulePlanned(
        alarm,
        exact: useExact,
        text: NotificationText(title: 'Time for $name', body: body),
        voiceSpoken: false,
      );
      if (ok) {
        registered++;
        medicineScheduled++;
      } else {
        refused++;
      }
    }

    // ── Encouragement ───────────────────────────────────────────────────────
    var motivationsScheduled = 0;
    if (settings.motivationEnabled) {
      final minutes = await motivations.scheduledMinutes(profile.id);
      final categories =
          settings.motivationCategories.map(MotivationCategory.fromKey).toList();
      final plan = NotificationPlanner.planMotivation(
        minutes: minutes,
        now: now,
        horizonDays: horizon,
        quiet: quiet,
      );
      for (final alarm in plan) {
        if (!_hasBudget(registered, refused)) {
          skipped++;
          continue;
        }
        final message = await motivations.nextMessage(categories: categories);
        if (message == null) continue;
        final ok = await notifications.schedulePlanned(
          alarm,
          exact: useExact,
          text: NotificationText(
            title: 'For you, ${profile.displayName}',
            body: message.text,
          ),
          voiceSpoken: false,
        );
        if (ok) {
          registered++;
          motivationsScheduled++;
          await motivations.markShown(message.id);
        } else {
          refused++;
        }
      }
    }

    // ── Love notes ──────────────────────────────────────────────────────────
    var notesScheduled = 0;
    if (settings.loveNotesEnabled) {
      final notes = await loveNotes.enabled(profile.id);
      final byId = {for (final n in notes) n.id: n};
      final plan = NotificationPlanner.planLoveNotes(
        notes: [
          for (final n in notes)
            if (n.minuteOfDay != null)
              LoveNotePlan(id: n.id, minuteOfDay: n.minuteOfDay!),
        ],
        now: now,
        horizonDays: horizon,
        quiet: quiet,
      );
      for (final alarm in plan) {
        if (!_hasBudget(registered, refused)) {
          skipped++;
          continue;
        }
        final note = byId[alarm.refId];
        final ok = await notifications.schedulePlanned(
          alarm,
          exact: useExact,
          text: NotificationText(
            title: 'A little love note',
            body: '${note?.text ?? ''}\n\n— ${note?.author ?? ''}'.trim(),
          ),
          voiceSpoken: false,
        );
        ok ? (registered++, notesScheduled++) : refused++;
      }
    }

    // ── Pending snoozes ─────────────────────────────────────────────────────
    for (final snooze in await water.pendingSnoozes(profile.id)) {
      if (!snooze.scheduledFor.isAfter(now)) {
        await water.cancelSnooze(snooze.id);
        continue;
      }
      final ok = await notifications.scheduleSnooze(
        snoozeId: snooze.id,
        amountMl: settings.glassSizeMl,
        when: snooze.scheduledFor,
        originalMinute: snooze.reminderMinute,
        isMedicine: false,
        exact: useExact,
      );
      ok ? registered++ : refused++;
    }

    // ── Native spoken reminders ─────────────────────────────────────────────
    // Speech is executed by Kotlin so it works with the app closed; Dart only
    // supplies the plan. Failure here must never break notification scheduling,
    // so it is isolated and reported in the scheduling report instead.
    VoicePlanResult? voiceResult;
    try {
      voiceResult = await voicePlan.apply(
        settings: settings,
        reminders: reminders,
        waterPaused: settings.waterRemindersPaused,
        speechEngineAvailable: await voicePlan.isAvailable(),
      );
    } catch (e) {
      debugPrint('AKASHA: spoken reminder plan failed: $e');
    }

    // ── Daily summary ───────────────────────────────────────────────────────
    final summaryOk = await notifications.schedulePlanned(
      PlannedAlarm(
        id: AkashaNotificationIds.dailyReport,
        kind: 'daily',
        when: NotificationPlanner.nextOccurrence(20 * 60 + 30, now),
        minuteOfDay: 20 * 60 + 30,
      ),
      exact: useExact,
      text: const NotificationText(
        title: 'Your day, gently wrapped up',
        body: 'Tap to see how you cared for yourself today.',
      ),
      voiceSpoken: false,
    );
    summaryOk ? registered++ : refused++;

    final report = SchedulingReport(
      waterSlots: waterPlan.length,
      doses: medicineScheduled,
      motivations: motivationsScheduled,
      loveNotes: notesScheduled,
      registered: registered,
      refused: refused,
      skipped: skipped,
      exact: useExact,
      horizonDays: horizon,
      spokenReminders: voiceResult?.armed ?? false,
      voiceNote: voiceResult?.reason,
    );
    debugPrint('AKASHA reschedule → $report');
    return report;
  }

  /// Rebuild after a single water edit. Named separately so call sites read as
  /// intent; the implementation is the same full pass (idempotent, cheap).
  Future<void> applyWaterEdit(String userId) async {
    await rescheduleAll();
  }

  Future<void> setWaterPaused({required bool paused}) async {
    final profile = await profiles.currentProfile();
    if (profile == null) return;
    await profiles.mutateSettings(
      (s) => s.copyWith(waterRemindersPaused: paused),
    );
    await rescheduleAll();
  }

  /// True while there is room for another alarm under the budget.
  bool _hasBudget(int registered, int refused) =>
      registered < AppConstants.maxPendingAlarms;

  /// `medlog:<medicineId>:<yyyy-MM-dd>:<minute>` → `<medicineId>`.
  ///
  /// The medicine id itself may contain colons (UUIDs do not, but a future id
  /// scheme might), so the split is from the right.
  static String _medicineIdFromLogId(String logId) {
    const prefix = 'medlog:';
    if (!logId.startsWith(prefix)) return '';
    final rest = logId.substring(prefix.length);
    final parts = rest.split(':');
    if (parts.length < 3) return '';
    return parts.sublist(0, parts.length - 2).join(':');
  }

  /// Title/body for a water alarm, rotating the title so the notification list
  /// does not look like a stuck record, and using the *same* line that will be
  /// spoken (or would have been, if the engine is missing).
  NotificationText waterCopyFor(PlannedAlarm alarm) {
    final pair = kWaterNotificationCopy[
        (alarm.id % kWaterNotificationCopy.length).abs()];
    final line = alarm.voiceLine ?? pair[1];
    return NotificationText(title: pair[0], body: line);
  }
}

/// Builds the planner's quiet window from her settings.
QuietWindow quietWindowFrom(UserSettings s) => QuietWindow(
      enabled: s.quietModeEnabled,
      startMinute: s.quietStartMin,
      endMinute: s.quietEndMin,
      pausesWater: s.quietPauseWater,
      pausesMotivation: s.quietPauseMotivation,
      pausesMedicine: s.quietPauseMedicine,
    );

/// What one build produced. Surfaced verbatim in Settings → Diagnostics, so the
/// numbers shown are the numbers that were really registered.
class SchedulingReport {
  const SchedulingReport({
    required this.waterSlots,
    required this.doses,
    required this.motivations,
    required this.loveNotes,
    this.registered = 0,
    this.refused = 0,
    this.skipped = 0,
    this.exact = false,
    this.horizonDays = AppConstants.scheduleHorizonDays,
    this.spokenReminders = false,
    this.voiceNote,
  });

  static const SchedulingReport empty = SchedulingReport(
    waterSlots: 0,
    doses: 0,
    motivations: 0,
    loveNotes: 0,
  );

  final int waterSlots;
  final int doses;
  final int motivations;
  final int loveNotes;

  /// Alarms actually accepted by the OS.
  final int registered;

  /// Alarms the OS refused (e.g. exact-alarm permission revoked).
  final int refused;

  /// Occurrences deliberately not scheduled: quiet hours, paused, budget.
  final int skipped;

  final bool exact;
  final int horizonDays;

  /// True when Android accepted a native spoken-reminder plan.
  final bool spokenReminders;

  /// Why speech is off, in words that can be shown to her unchanged.
  final String? voiceNote;

  int get total => registered;

  bool get overBudget => registered > AppConstants.maxPendingAlarms;

  @override
  String toString() =>
      'water=$waterSlots doses=$doses motivation=$motivations notes=$loveNotes '
      'registered=$registered refused=$refused skipped=$skipped '
      'exact=$exact horizon=${horizonDays}d';
}
