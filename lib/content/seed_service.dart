import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' show Transaction;

import '../core/constants/app_constants.dart';
import '../core/database/app_database.dart';
import '../data/models/mind_models.dart';
import '../data/models/user_settings.dart';
import '../data/repositories/motivation_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/water_repository.dart';
import 'motivation_content.dart';

/// One-time (and idempotent) first-run data setup:
///  * the local profile + settings row
///  * the 16 default water reminder slots
///  * the built-in motivational library
///
/// Every step checks before writing, so running it on each launch is safe and
/// cheap. Everything happens inside **one** transaction owned here:
///
///  * the repositories are handed that transaction (`txn:`), so none of them
///    opens its own — the "cannot start a transaction within a transaction"
///    failure mode is structurally impossible, not merely unlikely;
///  * a failure anywhere rolls the whole first run back, so the app can never
///    be left half-seeded (an onboarded profile with no reminder slots);
///  * a retry therefore starts from a clean slate and either succeeds
///    completely or leaves the database exactly as it was.
class SeedService {
  SeedService({
    required this.profiles,
    required this.water,
    required this.motivations,
    required AppDatabase database,
  }) : _db = database;

  final ProfileRepository profiles;
  final WaterRepository water;
  final MotivationRepository motivations;
  final AppDatabase _db;

  /// Serialises first-run seeding within this process, so two callers racing
  /// each other (main()'s bootstrap and the profile provider) share one run
  /// instead of interleaving two.
  Future<void>? _inFlight;

  /// Returns true when this call actually seeded anything.
  Future<bool> ensureFirstRunData({String displayName = 'Akasha'}) async {
    final running = _inFlight;
    if (running != null) {
      await running;
      return false;
    }
    final run = _seed(displayName);
    _inFlight = run;
    try {
      return await run;
    } finally {
      _inFlight = null;
    }
  }

  Future<bool> _seed(String displayName) async {
    return _db.transaction((txn) async {
      var wrote = false;

      // 1. Profile + settings (both created on first launch, never overwritten).
      final existingProfile = await profiles.currentProfile(txn: txn);
      final profile =
          existingProfile ?? await profiles.ensureProfile(displayName: displayName, txn: txn);
      final settings = await profiles.ensureSettings(profile.id, txn: txn);
      if (existingProfile == null) wrote = true;

      // 2. Water schedule: only when none exists, so a schedule the user
      //    customised is never replaced by the factory default.
      final seededWater =
          await _seedWaterSchedule(profile.id, settings, txn: txn);
      wrote |= seededWater;

      // 3. Motivational library: written last, because it is the largest and
      //    least critical step; if it fails everything above rolls back too.
      final seededMessages = await _seedMotivations(txn);
      wrote |= seededMessages;

      debugPrint('AKASHA seed complete for ${profile.displayName} '
          '(profile=${existingProfile == null}, water=$seededWater, '
          'messages=$seededMessages)');
      return wrote;
    });
  }

  Future<bool> _seedMotivations(Transaction txn) async {
    final existing = await motivations.count(txn: txn);
    if (existing >= AppConstants.motivationPoolTarget) return false;

    // Skip texts that are already present. Without this, a run interrupted
    // half-way through the library would duplicate the messages it had already
    // written on the next launch.
    final already = await motivations.allTexts(txn: txn);
    var added = 0;
    for (final entry in kMotivationSeeds.entries) {
      for (final text in entry.value) {
        if (already.contains(text)) continue;
        await motivations.addCustom(
          category: entry.key,
          text: text,
          txn: txn,
        );
        added++;
      }
    }
    return added > 0;
  }

  Future<bool> _seedWaterSchedule(
    String userId,
    UserSettings settings, {
    Transaction? txn,
  }) async {
    final existing = await water.reminders(userId, txn: txn);
    if (existing.isNotEmpty) return false;

    final created = await water.generateDefaultSchedule(
      userId: userId,
      startMinute: settings.waterStartMin,
      endMinute: settings.waterEndMin,
      intervalMinutes: settings.waterIntervalMin,
      amountMl: settings.glassSizeMl,
      txn: txn,
    );
    return created.isNotEmpty;
  }

  /// Restores the factory-default water schedule (spec §6: "Restore the
  /// default schedule").
  Future<int> restoreDefaultWaterSchedule(String userId, UserSettings settings) async {
    final created = await water.generateDefaultSchedule(
      userId: userId,
      startMinute: AppConstants.defaultWaterStartMinute,
      endMinute: AppConstants.defaultWaterEndMinute,
      intervalMinutes: AppConstants.defaultWaterIntervalMinutes,
      amountMl: settings.glassSizeMl,
    );
    return created.length;
  }

  /// Counts that the diagnostics screen can show as proof the schedule is
  /// materialised correctly (should be 16 for stock settings).
  Future<int> activeSlotCount(String userId) async {
    final slots = await water.enabledReminders(userId);
    return slots.length;
  }

  /// Message count for the about screen.
  Future<int> messageCount() => motivations.count();

  Future<MotivationCategory> categoryOf(MotivationCategory c) async => c;
}
