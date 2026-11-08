import 'package:flutter/foundation.dart';

import '../core/constants/app_constants.dart';
import '../data/models/mind_models.dart';
import '../data/repositories/motivation_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/water_repository.dart';
import '../data/models/user_settings.dart';
import 'motivation_content.dart';

/// One-time (and idempotent) first-run data setup:
///  * built-in motivational library
///  * the 16 default water reminder slots
///  * the local profile + settings row
///
/// Every step checks before writing, so running it on each launch is safe.
class SeedService {
  SeedService({
    required this.profiles,
    required this.water,
    required this.motivations,
  });

  final ProfileRepository profiles;
  final WaterRepository water;
  final MotivationRepository motivations;

  Future<void> ensureFirstRunData({String displayName = 'Akasha'}) async {
    final profile = await profiles.ensureProfile(displayName: displayName);
    final settings = await profiles.ensureSettings(profile.id);
    await _seedMotivations();
    await _seedWaterSchedule(profile.id, settings);
    debugPrint('AKASHA seed complete for ${profile.displayName}');
  }

  Future<void> _seedMotivations() async {
    final existing = await motivations.count();
    if (existing >= AppConstants.motivationPoolTarget) return;

    for (final entry in kMotivationSeeds.entries) {
      final category = entry.key;
      for (final text in entry.value) {
        await motivations.addCustom(category: category, text: text);
      }
    }
  }

  Future<void> _seedWaterSchedule(String userId, UserSettings settings) async {
    final existing = await water.reminders(userId);
    if (existing.isNotEmpty) return;

    await water.generateDefaultSchedule(
      userId: userId,
      startMinute: settings.waterStartMin,
      endMinute: settings.waterEndMin,
      intervalMinutes: settings.waterIntervalMin,
      amountMl: settings.glassSizeMl,
    );
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
