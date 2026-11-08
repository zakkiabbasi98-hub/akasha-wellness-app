import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/medicine_models.dart';
import '../data/models/mind_models.dart';
import '../data/models/user_profile.dart';
import '../data/models/user_settings.dart';
import '../data/models/water_models.dart';
import '../data/repositories/love_note_repository.dart';
import '../data/repositories/medicine_repository.dart';
import '../data/repositories/mind_repository.dart';
import '../data/repositories/motivation_repository.dart';
import '../data/repositories/notification_history_repository.dart';
import '../data/repositories/profile_repository.dart';
import '../data/repositories/reports_repository.dart';
import '../data/repositories/water_repository.dart';
import '../content/seed_service.dart';
import '../features/sync/sync_service.dart';
import 'database/app_database.dart';
import 'notifications/notification_ids.dart';
import 'notifications/notification_service.dart';
import 'notifications/reminder_scheduler.dart';
import 'services/lock_service.dart';
import 'services/system_channel.dart';
import 'services/voice_service.dart';
import 'utils/date_utils.dart';

// ─── Infrastructure ────────────────────────────────────────────────────────

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase.instance);

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();
  ref.onDispose(service.cancelAll);
  return service;
});

final voiceServiceProvider = Provider<VoiceService>((ref) {
  final service = VoiceService();
  ref.onDispose(service.dispose);
  return service;
});

final lockServiceProvider = Provider<LockService>((ref) => LockService());

final systemChannelProvider = Provider<SystemChannel>((ref) => const SystemChannel());

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService(
    database: ref.watch(databaseProvider),
    water: ref.watch(waterRepositoryProvider),
    medicine: ref.watch(medicineRepositoryProvider),
    mind: ref.watch(mindRepositoryProvider),
    loveNotes: ref.watch(loveNoteRepositoryProvider),
    profiles: ref.watch(profileRepositoryProvider),
  );
});

// ─── Repositories ──────────────────────────────────────────────────────────

final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(databaseProvider)));

final waterRepositoryProvider =
    Provider<WaterRepository>((ref) => WaterRepository(ref.watch(databaseProvider)));

final medicineRepositoryProvider =
    Provider<MedicineRepository>((ref) => MedicineRepository(ref.watch(databaseProvider)));

final mindRepositoryProvider =
    Provider<MindRepository>((ref) => MindRepository(ref.watch(databaseProvider)));

final motivationRepositoryProvider =
    Provider<MotivationRepository>((ref) => MotivationRepository(ref.watch(databaseProvider)));

final loveNoteRepositoryProvider =
    Provider<LoveNoteRepository>((ref) => LoveNoteRepository(ref.watch(databaseProvider)));

final notificationHistoryProvider = Provider<NotificationHistoryRepository>(
    (ref) => NotificationHistoryRepository(ref.watch(databaseProvider)));

final reportsRepositoryProvider = Provider<ReportsRepository>((ref) => ReportsRepository(
      water: ref.watch(waterRepositoryProvider),
      medicine: ref.watch(medicineRepositoryProvider),
      mind: ref.watch(mindRepositoryProvider),
    ));

final seedServiceProvider = Provider<SeedService>((ref) => SeedService(
      profiles: ref.watch(profileRepositoryProvider),
      water: ref.watch(waterRepositoryProvider),
      motivations: ref.watch(motivationRepositoryProvider),
    ));

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) => ReminderScheduler(
      notifications: ref.watch(notificationServiceProvider),
      water: ref.watch(waterRepositoryProvider),
      medicine: ref.watch(medicineRepositoryProvider),
      motivations: ref.watch(motivationRepositoryProvider),
      loveNotes: ref.watch(loveNoteRepositoryProvider),
      profiles: ref.watch(profileRepositoryProvider),
    ));

// ─── Bootstrapped profile / settings ───────────────────────────────────────

/// Resolves once the profile + settings rows exist (created on first launch).
final profileProvider = FutureProvider<UserProfile>((ref) async {
  final repo = ref.watch(profileRepositoryProvider);
  final seed = ref.watch(seedServiceProvider);
  await seed.ensureFirstRunData();
  final profile = await repo.currentProfile();
  return profile ?? await repo.ensureProfile();
});

final settingsProvider = FutureProvider<UserSettings>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  final repo = ref.watch(profileRepositoryProvider);
  return await repo.currentSettings() ?? await repo.ensureSettings(profile.id);
});

/// Mutable settings controller used by every settings screen.
final settingsControllerProvider =
    StateNotifierProvider<SettingsController, AsyncValue<UserSettings>>((ref) {
  return SettingsController(ref);
});

class SettingsController extends StateNotifier<AsyncValue<UserSettings>> {
  SettingsController(this.ref) : super(const AsyncValue.loading()) {
    _load();
  }

  final Ref ref;

  Future<void> _load() async {
    state = AsyncValue.data(await ref.read(settingsProvider.future));
  }

  Future<void> update(UserSettings Function(UserSettings) change) async {
    final repo = ref.read(profileRepositoryProvider);
    final current = state.valueOrNull ?? await ref.read(settingsProvider.future);
    final saved = await repo.saveSettings(change(current));
    state = AsyncValue.data(saved);
    ref.invalidate(settingsProvider);
  }

  /// Applies the change AND re-materialises notifications when the change
  /// affects scheduling (reminders, quiet hours, voice, pause).
  Future<void> updateAndReschedule(UserSettings Function(UserSettings) change) async {
    await update(change);
    final exact = await ref.read(notificationServiceProvider).canScheduleExactAlarms();
    await ref.read(reminderSchedulerProvider).rescheduleAll(exact: exact);
    ref.invalidate(schedulingStatusProvider);
  }
}

// ─── Today's data ──────────────────────────────────────────────────────────

/// A revision counter: bump it after any mutation to refresh dependants.
final dataRevisionProvider = StateProvider<int>((ref) => 0);

void refreshData(WidgetRef ref) => ref.read(dataRevisionProvider.notifier).state++;

final currentUserIdProvider = Provider<String>((ref) {
  return ref.watch(profileProvider).valueOrNull?.id ?? 'local-profile';
});

final todayWaterProvider = FutureProvider<DailyWaterSummary>((ref) async {
  ref.watch(dataRevisionProvider);
  final profile = await ref.watch(profileProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  return ref.read(waterRepositoryProvider).summaryForDay(
        profile.id,
        DateTime.now(),
        targetMl: settings.waterTargetMl,
        glassSizeMl: settings.glassSizeMl,
      );
});

final todayDosesProvider = FutureProvider<List<DoseView>>((ref) async {
  ref.watch(dataRevisionProvider);
  final profile = await ref.watch(profileProvider.future);
  final repo = ref.read(medicineRepositoryProvider);
  // Reconcile before reading so a dose from yesterday that was never answered
  // shows as "missed" rather than silently staying "scheduled".
  await repo.reconcileMissedDoses(profile.id);
  return repo.dosesForDay(profile.id, DateTime.now());
});

final latestMoodProvider = FutureProvider<MoodEntry?>((ref) async {
  ref.watch(dataRevisionProvider);
  final profile = await ref.watch(profileProvider.future);
  return ref.read(mindRepositoryProvider).latestMood(profile.id);
});

final todayGratitudeProvider = FutureProvider<GratitudeEntry?>((ref) async {
  ref.watch(dataRevisionProvider);
  final profile = await ref.watch(profileProvider.future);
  return ref.read(mindRepositoryProvider).gratitudeForDay(profile.id, DateTime.now());
});

final todayBreathingProvider = FutureProvider<List<BreathingSession>>((ref) async {
  ref.watch(dataRevisionProvider);
  final profile = await ref.watch(profileProvider.future);
  return ref.read(mindRepositoryProvider).breathingForDay(profile.id, DateTime.now());
});

final todayJournalCountProvider = FutureProvider<int>((ref) async {
  ref.watch(dataRevisionProvider);
  final profile = await ref.watch(profileProvider.future);
  return ref
      .read(mindRepositoryProvider)
      .journalCountInRange(profile.id, DateTime.now(), DateTime.now());
});

final messageOfDayProvider = FutureProvider<MotivationalMessage?>((ref) async {
  final repo = ref.read(motivationRepositoryProvider);
  return repo.messageOfTheDay(dayKey: AkashaDates.key(DateTime.now()));
});

final todayReportProvider = FutureProvider((ref) async {
  ref.watch(dataRevisionProvider);
  final profile = await ref.watch(profileProvider.future);
  final settings = await ref.watch(settingsProvider.future);
  return ref.read(reportsRepositoryProvider).daily(
        userId: profile.id,
        day: DateTime.now(),
        targetMl: settings.waterTargetMl,
        glassSizeMl: settings.glassSizeMl,
      );
});

final waterRemindersProvider = FutureProvider<List<WaterReminder>>((ref) async {
  ref.watch(dataRevisionProvider);
  final profile = await ref.watch(profileProvider.future);
  return ref.read(waterRepositoryProvider).reminders(profile.id);
});

final medicinesProvider = FutureProvider<List<Medicine>>((ref) async {
  ref.watch(dataRevisionProvider);
  final profile = await ref.watch(profileProvider.future);
  return ref.read(medicineRepositoryProvider).all(profile.id);
});

final loveNotesProvider = FutureProvider<List<LoveNote>>((ref) async {
  ref.watch(dataRevisionProvider);
  final profile = await ref.watch(profileProvider.future);
  final repo = ref.read(loveNoteRepositoryProvider);
  await repo.seedIfEmpty(profile.id);
  return repo.all(profile.id);
});

/// Keys are notification ids; used by the diagnostics screen to prove what is
/// actually scheduled on the device right now.
final schedulingStatusProvider = FutureProvider((ref) async {
  final service = ref.watch(notificationServiceProvider);
  final pending = await service.pendingRequests();
  // Count by the same ranges AkashaNotificationIds allocates, so this screen
  // cannot disagree with the scheduler about what is pending.
  final water = pending
      .where((p) =>
          p.id >= AkashaNotificationIds.waterBase &&
          p.id < AkashaNotificationIds.medicineBase)
      .length;
  final medicine = pending
      .where((p) =>
          p.id >= AkashaNotificationIds.medicineBase &&
          p.id < AkashaNotificationIds.motivationBase)
      .length;
  return SchedulingStatus(
    pendingTotal: pending.length,
    pendingWater: water,
    pendingMedicine: medicine,
    notificationsEnabled: await service.areNotificationsEnabled(),
    exactAlarms: await service.canScheduleExactAlarms(),
    fullScreenAllowed: await service.areFullScreenIntentsAllowed(),
    batteryOptimised:
        !(await ref.read(systemChannelProvider).isIgnoringBatteryOptimizations()),
    dndActive: await ref.read(systemChannelProvider).isDndActive(),
    sdkInt: await ref.read(systemChannelProvider).deviceSdkInt(),
  );
});

class SchedulingStatus {
  const SchedulingStatus({
    required this.pendingTotal,
    required this.pendingWater,
    required this.pendingMedicine,
    required this.notificationsEnabled,
    required this.exactAlarms,
    required this.fullScreenAllowed,
    required this.batteryOptimised,
    required this.dndActive,
    required this.sdkInt,
  });

  final int pendingTotal;
  final int pendingWater;
  final int pendingMedicine;
  final bool notificationsEnabled;
  final bool exactAlarms;
  final bool fullScreenAllowed;
  final bool batteryOptimised;
  final bool dndActive;
  final int sdkInt;
}

/// Theme mode for MaterialApp.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final settings = ref.watch(settingsControllerProvider).valueOrNull;
  return switch (settings?.themeMode) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    _ => ThemeMode.light, // light is the primary experience by design
  };
});
