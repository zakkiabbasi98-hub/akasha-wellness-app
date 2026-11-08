import '../constants/app_constants.dart';
import '../utils/date_utils.dart';
import 'notification_ids.dart';

/// One concrete alarm the scheduler intends to have registered.
class PlannedAlarm {
  const PlannedAlarm({
    required this.id,
    required this.kind,
    required this.when,
    required this.minuteOfDay,
    this.amountMl,
    this.refId,
    this.voiceLine,
    this.firstOfDay = false,
  });

  final int id;
  final String kind;
  final DateTime when;
  final int minuteOfDay;
  final int? amountMl;

  /// Medicine log id, love-note id, snooze id — whatever the action needs.
  final String? refId;

  /// The spoken line for this occurrence, chosen at schedule time so the
  /// notification body, the spoken audio and the voice-preview button all agree.
  final String? voiceLine;

  /// True for the first slot of a day; used to decide which occurrence is
  /// allowed the full-screen/heads-up treatment.
  final bool firstOfDay;

  @override
  String toString() =>
      '$kind#${id.toString().padLeft(10)} ${AkashaDates.minutesToLabel(minuteOfDay)} '
      '@ ${when.toIso8601String()}';
}

/// Summary of one full planning pass. Returned to the diagnostics screen so the
/// numbers shown are the numbers that were actually registered.
class SchedulePlan {
  const SchedulePlan({
    required this.water,
    required this.medicine,
    required this.motivation,
    required this.loveNotes,
    required this.snoozes,
    required this.skipped,
  });

  final List<PlannedAlarm> water;
  final List<PlannedAlarm> medicine;
  final List<PlannedAlarm> motivation;
  final List<PlannedAlarm> loveNotes;
  final List<PlannedAlarm> snoozes;

  /// Occurrences that were deliberately not scheduled (quiet hours, paused, in
  /// the past). Counted separately so "0 scheduled" can be explained.
  final int skipped;

  int get total =>
      water.length +
      medicine.length +
      motivation.length +
      loveNotes.length +
      snoozes.length;

  /// Every id in the plan, in registration order. The regression test asserts
  /// this list has no duplicates — the exact property that was broken.
  List<int> get ids => [
        for (final a in water) a.id,
        for (final a in medicine) a.id,
        for (final a in motivation) a.id,
        for (final a in loveNotes) a.id,
        for (final a in snoozes) a.id,
      ];

  @override
  String toString() =>
      'water=${water.length} medicine=${medicine.length} '
      'motivation=${motivation.length} love=${loveNotes.length} '
      'snooze=${snoozes.length} skipped=$skipped';
}

/// Quiet-hours window, evaluated on the *local wall clock*.
class QuietWindow {
  const QuietWindow({
    required this.enabled,
    required this.startMinute,
    required this.endMinute,
    required this.pausesWater,
    required this.pausesMotivation,
    required this.pausesMedicine,
  });

  static const QuietWindow off = QuietWindow(
    enabled: false,
    startMinute: 0,
    endMinute: 0,
    pausesWater: false,
    pausesMotivation: false,
    pausesMedicine: false,
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
    // Wraps midnight (e.g. 22:30 → 07:00).
    return minuteOfDay >= startMinute || minuteOfDay < endMinute;
  }
}

/// Pure alarm planner.
///
/// Everything the scheduler decides — which occurrences exist, which id each
/// one gets, which are suppressed — lives here, with **no** plugin, no
/// database and no Flutter binding. `ReminderScheduler` only performs side
/// effects; it makes no decisions. That split is what lets the whole
/// notification contract be unit-tested without a device.
///
/// Contract
/// --------
/// * A slot at 12:00 AM (minute 0) is scheduled on the *next* midnight, not
///   skipped for being "in the past" — the midnight reminder is inclusive.
/// * Occurrences strictly in the past are dropped.
/// * Every (day, minute) pair produces exactly one alarm with a distinct id.
abstract final class NotificationPlanner {
  /// Plans the water reminders for [horizonDays] starting from [now].
  ///
  /// [minutes] must be the enabled slot minutes for the user.
  static List<PlannedAlarm> planWater({
    required List<int> minutes,
    required int amountMl,
    required DateTime now,
    required int horizonDays,
    QuietWindow quiet = QuietWindow.off,
    bool paused = false,
    List<String> voiceLines = const [],
    int voiceSeed = 0,
  }) {
    if (paused) return const [];
    final ordered = [...minutes.toSet().toList()..sort()];
    final out = <PlannedAlarm>[];

    for (var dayOffset = 0; dayOffset < horizonDays; dayOffset++) {
      final day = AkashaDates.dayOnly(now).add(Duration(days: dayOffset));
      var firstOfDay = true;
      for (final minute in ordered) {
        if (quiet.pausesWater && quiet.wouldSuppress(minute)) continue;
        final when = _occurrenceOn(day, minute, now);
        if (when == null) continue;
        out.add(PlannedAlarm(
          id: AkashaNotificationIds.water(minute, day),
          kind: 'water',
          when: when,
          minuteOfDay: minute,
          amountMl: amountMl,
          voiceLine: voiceLines.isEmpty
              ? null
              : voiceLines[(voiceSeed + dayOffset * ordered.length + out.length) %
                  voiceLines.length],
          firstOfDay: firstOfDay,
        ));
        firstOfDay = false;
      }
    }
    return out;
  }

  /// Plans medicine doses. [doses] is (logId, minute, when-is-due) triples
  /// already filtered to enabled, non-deleted, due-on-that-day medicines.
  static List<PlannedAlarm> planMedicine({
    required List<MedicineDosePlan> doses,
    required DateTime now,
    required int horizonDays,
    QuietWindow quiet = QuietWindow.off,
    bool paused = false,
  }) {
    if (paused) return const [];
    final out = <PlannedAlarm>[];
    for (var dayOffset = 0; dayOffset < horizonDays; dayOffset++) {
      final day = AkashaDates.dayOnly(now).add(Duration(days: dayOffset));
      for (final dose in doses) {
        if (!dose.isDueOn(day)) continue;
        // A prescribed dose is never silenced by quiet hours unless she
        // explicitly opted in: dropping a medicine reminder is a real harm.
        if (quiet.pausesMedicine && quiet.wouldSuppress(dose.minuteOfDay)) {
          continue;
        }
        final when = _occurrenceOn(day, dose.minuteOfDay, now);
        if (when == null) continue;
        out.add(PlannedAlarm(
          id: AkashaNotificationIds.medicine(AkashaMedicineIds.logId(dose, day)),
          kind: 'medicine',
          when: when,
          minuteOfDay: dose.minuteOfDay,
          refId: AkashaMedicineIds.logId(dose, day),
        ));
      }
    }
    return out;
  }

  /// Plans encouragement messages (one per configured minute per day).
  static List<PlannedAlarm> planMotivation({
    required List<int> minutes,
    required DateTime now,
    required int horizonDays,
    QuietWindow quiet = QuietWindow.off,
    bool enabled = true,
  }) {
    if (!enabled) return const [];
    final out = <PlannedAlarm>[];
    for (var dayOffset = 0; dayOffset < horizonDays; dayOffset++) {
      final day = AkashaDates.dayOnly(now).add(Duration(days: dayOffset));
      for (final minute in minutes) {
        if (quiet.pausesMotivation && quiet.wouldSuppress(minute)) continue;
        final when = _occurrenceOn(day, minute, now);
        if (when == null) continue;
        out.add(PlannedAlarm(
          id: AkashaNotificationIds.motivation(minute, day),
          kind: 'motivation',
          when: when,
          minuteOfDay: minute,
        ));
      }
    }
    return out;
  }

  /// Plans love notes. [notes] is (id, minute) pairs.
  static List<PlannedAlarm> planLoveNotes({
    required List<LoveNotePlan> notes,
    required DateTime now,
    required int horizonDays,
    QuietWindow quiet = QuietWindow.off,
    bool enabled = true,
  }) {
    if (!enabled) return const [];
    final out = <PlannedAlarm>[];
    for (var dayOffset = 0; dayOffset < horizonDays; dayOffset++) {
      final day = AkashaDates.dayOnly(now).add(Duration(days: dayOffset));
      for (final note in notes) {
        if (quiet.pausesWater && quiet.wouldSuppress(note.minuteOfDay)) continue;
        final when = _occurrenceOn(day, note.minuteOfDay, now);
        if (when == null) continue;
        out.add(PlannedAlarm(
          id: AkashaNotificationIds.loveNote(note.minuteOfDay, day,
              noteId: note.id),
          kind: 'love_note',
          when: when,
          minuteOfDay: note.minuteOfDay,
          refId: note.id,
        ));
      }
    }
    return out;
  }

  /// Resolves the instant a given (day, minute) fires, or `null` if it is in
  /// the past.
  ///
  /// The midnight rule: minute `0` on the horizon's first day means the
  /// *upcoming* midnight, so a reminder at 12:00 AM is never dropped just
  /// because the day has already started.
  static DateTime? _occurrenceOn(DateTime day, int minuteOfDay, DateTime now) {
    if (minuteOfDay < 0 || minuteOfDay >= 24 * 60) return null;
    final when = DateTime(day.year, day.month, day.day)
        .add(Duration(minutes: minuteOfDay));
    if (when.isBefore(now)) return null;
    return when;
  }

  /// Next occurrence of [minuteOfDay] strictly after [now]. Used for snoozes
  /// and for the "next reminder" line on the water screen.
  static DateTime nextOccurrence(int minuteOfDay, DateTime now) {
    final today = DateTime(now.year, now.month, now.day)
        .add(Duration(minutes: minuteOfDay));
    if (today.isAfter(now)) return today;
    return today.add(const Duration(days: 1));
  }

  /// Hard cap from [AppConstants]: Android silently drops alarms beyond a few
  /// hundred, so overflowing is a bug, not a UX detail.
  static bool isWithinAlarmBudget(int count) =>
      count <= AppConstants.maxPendingAlarms;
}

/// Minimal shape the medicine planner needs. Kept as a plain class (not the
/// model) so planning has no dependency on the medicine repository.
class MedicineDosePlan {
  const MedicineDosePlan({
    required this.medicineId,
    required this.minuteOfDay,
    this.weekdays = const <int>{},
    this.startDay,
    this.endDay,
  });

  final String medicineId;
  final int minuteOfDay;

  /// Empty means "every day".
  final Set<int> weekdays;
  final DateTime? startDay;
  final DateTime? endDay;

  bool isDueOn(DateTime day) {
    if (startDay != null && AkashaDates.dayOnly(day).isBefore(AkashaDates.dayOnly(startDay!))) {
      return false;
    }
    if (endDay != null && AkashaDates.dayOnly(day).isAfter(AkashaDates.dayOnly(endDay!))) {
      return false;
    }
    if (weekdays.isEmpty) return true;
    return weekdays.contains(day.weekday);
  }
}

class LoveNotePlan {
  const LoveNotePlan({required this.id, required this.minuteOfDay});
  final String id;
  final int minuteOfDay;
}

/// The medicine log id, expressed once for the planner so it needs no
/// repository import. `MedicineRepository.logIdFor` / `.planLogId` use the
/// identical formula — `Ids.slotId('medlog', '<medicineId>:<dayKey>:<minute>')`
/// — and a unit test pins the two together so they cannot drift apart.
abstract final class AkashaMedicineIds {
  static String logId(MedicineDosePlan dose, DateTime day) =>
      'medlog:${dose.medicineId}:${AkashaDates.key(day)}:${dose.minuteOfDay}';
}
