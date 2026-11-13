import '../../core/constants/app_constants.dart';
import '../../core/database/app_database.dart';
import '../../core/utils/date_utils.dart';
import 'sync_entity.dart';

/// Which TTS persona to use. Voice availability depends on the phone's
/// installed engines — the settings screen explains this honestly.
enum VoiceProfile {
  softFeminine('soft_feminine', 'Soft & gentle', 1.08, 0.45),
  cheerfulFeminine('cheerful_feminine', 'Warm & cheerful', 1.18, 0.50),
  calmMasculine('calm_masculine', 'Calm & steady', 0.92, 0.44),
  systemDefault('system_default', 'Device default', 1.0, 0.46),
  disabled('disabled', 'No voice', 1.0, 0.46);

  const VoiceProfile(this.key, this.label, this.pitch, this.rate);
  final String key;
  final String label;
  final double pitch;
  final double rate;

  static VoiceProfile fromKey(String? key) =>
      VoiceProfile.values.firstWhere((v) => v.key == key, orElse: () => softFeminine);
}

enum AppThemeMode { light, dark, system }

class UserSettings with SyncEntity {
  UserSettings({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.isDirty = true,
    this.waterTargetMl = AppConstants.defaultWaterTargetMl,
    this.glassSizeMl = AppConstants.defaultGlassMl,
    this.smallGlassMl = AppConstants.smallGlassMl,
    this.largeGlassMl = AppConstants.largeGlassMl,
    this.waterStartMin = AppConstants.defaultWaterStartMinute,
    this.waterEndMin = AppConstants.defaultWaterEndMinute,
    this.waterIntervalMin = AppConstants.defaultWaterIntervalMinutes,
    this.waterRemindersPaused = false,
    this.medicineRemindersPaused = false,
    this.snoozeMinutes = AppConstants.defaultSnoozeMinutes,
    this.quietModeEnabled = true,
    this.quietStartMin = AppConstants.defaultQuietStartMinute,
    this.quietEndMin = AppConstants.defaultQuietEndMinute,
    this.quietPauseWater = true,
    this.quietPauseMotivation = true,
    this.quietPauseMedicine = false,
    this.voiceEnabled = true,
    this.voiceProfile = VoiceProfile.softFeminine,
    this.voiceRate = 0.46,
    this.voicePitch = 1.08,
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.alarmStyle = true,
    this.motivationEnabled = true,
    this.motivationPerDay = 3,
    this.motivationCategories = const [],
    this.loveNotesEnabled = true,
    this.themeMode = AppThemeMode.system,
    this.languageCode = 'en',
    this.aiEnabled = false,
    this.aiConsentGiven = false,
    this.syncEnabled = false,
    this.syncConsentGiven = false,
    this.appLockEnabled = false,
    this.lastSyncAt,
  });

  @override
  final String id;
  final String userId;

  final int waterTargetMl;
  final int glassSizeMl;
  final int smallGlassMl;
  final int largeGlassMl;
  final int waterStartMin;
  final int waterEndMin;
  final int waterIntervalMin;
  final bool waterRemindersPaused;
  final bool medicineRemindersPaused;
  final int snoozeMinutes;

  final bool quietModeEnabled;
  final int quietStartMin;
  final int quietEndMin;
  final bool quietPauseWater;
  final bool quietPauseMotivation;
  final bool quietPauseMedicine;

  final bool voiceEnabled;
  final VoiceProfile voiceProfile;
  final double voiceRate;
  final double voicePitch;
  final bool soundEnabled;
  final bool vibrationEnabled;
  final bool alarmStyle;

  final bool motivationEnabled;
  final int motivationPerDay;
  final List<String> motivationCategories;
  final bool loveNotesEnabled;

  final AppThemeMode themeMode;
  final String languageCode;

  final bool aiEnabled;
  final bool aiConsentGiven;
  final bool syncEnabled;
  final bool syncConsentGiven;
  final bool appLockEnabled;
  final DateTime? lastSyncAt;

  @override
  final DateTime createdAt;
  @override
  final DateTime updatedAt;
  @override
  final DateTime? deletedAt;
  @override
  final bool isDirty;

  /// Effective voice setting after the master toggle.
  VoiceProfile get effectiveVoice =>
      voiceEnabled ? voiceProfile : VoiceProfile.disabled;

  int get glassesTarget =>
      waterTargetMl <= 0 ? 1 : (waterTargetMl / glassSizeMl).ceil();

  UserSettings copyWith({
    int? waterTargetMl,
    int? glassSizeMl,
    int? smallGlassMl,
    int? largeGlassMl,
    int? waterStartMin,
    int? waterEndMin,
    int? waterIntervalMin,
    bool? waterRemindersPaused,
    bool? medicineRemindersPaused,
    int? snoozeMinutes,
    bool? quietModeEnabled,
    int? quietStartMin,
    int? quietEndMin,
    bool? quietPauseWater,
    bool? quietPauseMotivation,
    bool? quietPauseMedicine,
    bool? voiceEnabled,
    VoiceProfile? voiceProfile,
    double? voiceRate,
    double? voicePitch,
    bool? soundEnabled,
    bool? vibrationEnabled,
    bool? alarmStyle,
    bool? motivationEnabled,
    int? motivationPerDay,
    List<String>? motivationCategories,
    bool? loveNotesEnabled,
    AppThemeMode? themeMode,
    String? languageCode,
    bool? aiEnabled,
    bool? aiConsentGiven,
    bool? syncEnabled,
    bool? syncConsentGiven,
    bool? appLockEnabled,
    DateTime? lastSyncAt,
  }) {
    return UserSettings(
      id: id,
      userId: userId,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      deletedAt: deletedAt,
      isDirty: true,
      waterTargetMl: waterTargetMl ?? this.waterTargetMl,
      glassSizeMl: glassSizeMl ?? this.glassSizeMl,
      smallGlassMl: smallGlassMl ?? this.smallGlassMl,
      largeGlassMl: largeGlassMl ?? this.largeGlassMl,
      waterStartMin: waterStartMin ?? this.waterStartMin,
      waterEndMin: waterEndMin ?? this.waterEndMin,
      waterIntervalMin: waterIntervalMin ?? this.waterIntervalMin,
      waterRemindersPaused: waterRemindersPaused ?? this.waterRemindersPaused,
      medicineRemindersPaused: medicineRemindersPaused ?? this.medicineRemindersPaused,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      quietModeEnabled: quietModeEnabled ?? this.quietModeEnabled,
      quietStartMin: quietStartMin ?? this.quietStartMin,
      quietEndMin: quietEndMin ?? this.quietEndMin,
      quietPauseWater: quietPauseWater ?? this.quietPauseWater,
      quietPauseMotivation: quietPauseMotivation ?? this.quietPauseMotivation,
      quietPauseMedicine: quietPauseMedicine ?? this.quietPauseMedicine,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      voiceProfile: voiceProfile ?? this.voiceProfile,
      voiceRate: voiceRate ?? this.voiceRate,
      voicePitch: voicePitch ?? this.voicePitch,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      alarmStyle: alarmStyle ?? this.alarmStyle,
      motivationEnabled: motivationEnabled ?? this.motivationEnabled,
      motivationPerDay: motivationPerDay ?? this.motivationPerDay,
      motivationCategories: motivationCategories ?? this.motivationCategories,
      loveNotesEnabled: loveNotesEnabled ?? this.loveNotesEnabled,
      themeMode: themeMode ?? this.themeMode,
      languageCode: languageCode ?? this.languageCode,
      aiEnabled: aiEnabled ?? this.aiEnabled,
      aiConsentGiven: aiConsentGiven ?? this.aiConsentGiven,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      syncConsentGiven: syncConsentGiven ?? this.syncConsentGiven,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }

  static const Map<AppThemeMode, String> themeKeys = {
    AppThemeMode.light: 'light',
    AppThemeMode.dark: 'dark',
    AppThemeMode.system: 'system',
  };

  static AppThemeMode themeFromKey(String? key) => AppThemeMode.values.firstWhere(
        (m) => themeKeys[m] == key,
        orElse: () => AppThemeMode.system,
      );

  @override
  Map<String, Object?> toRow() => AppDatabase.insertRow({
        'id': id,
        'user_id': userId,
        'water_target_ml': waterTargetMl,
        'glass_size_ml': glassSizeMl,
        'small_glass_ml': smallGlassMl,
        'large_glass_ml': largeGlassMl,
        'water_start_min': waterStartMin,
        'water_end_min': waterEndMin,
        'water_interval_min': waterIntervalMin,
        'water_reminders_paused': waterRemindersPaused ? 1 : 0,
        'medicine_reminders_paused': medicineRemindersPaused ? 1 : 0,
        'snooze_minutes': snoozeMinutes,
        'quiet_mode_enabled': quietModeEnabled ? 1 : 0,
        'quiet_start_min': quietStartMin,
        'quiet_end_min': quietEndMin,
        'quiet_pause_water': quietPauseWater ? 1 : 0,
        'quiet_pause_motivation': quietPauseMotivation ? 1 : 0,
        'quiet_pause_medicine': quietPauseMedicine ? 1 : 0,
        'voice_enabled': voiceEnabled ? 1 : 0,
        'voice_profile': voiceProfile.key,
        'voice_rate': voiceRate,
        'voice_pitch': voicePitch,
        'sound_enabled': soundEnabled ? 1 : 0,
        'vibration_enabled': vibrationEnabled ? 1 : 0,
        'alarm_style': alarmStyle ? 1 : 0,
        'motivation_enabled': motivationEnabled ? 1 : 0,
        'motivation_per_day': motivationPerDay,
        'motivation_categories': motivationCategories.join(','),
        'love_notes_enabled': loveNotesEnabled ? 1 : 0,
        'theme_mode': themeKeys[themeMode],
        'language_code': languageCode,
        'ai_enabled': aiEnabled ? 1 : 0,
        'ai_consent_given': aiConsentGiven ? 1 : 0,
        'sync_enabled': syncEnabled ? 1 : 0,
        'sync_consent_given': syncConsentGiven ? 1 : 0,
        'app_lock_enabled': appLockEnabled ? 1 : 0,
        'last_sync_at': SyncEntity.toMillis(lastSyncAt),
        'deleted_at': SyncEntity.toMillis(deletedAt),
      }, createdAt: createdAt);

  factory UserSettings.fromRow(Map<String, Object?> r) => UserSettings(
        id: r['id'] as String,
        userId: r['user_id'] as String,
        waterTargetMl: r['water_target_ml'] as int? ?? AppConstants.defaultWaterTargetMl,
        glassSizeMl: r['glass_size_ml'] as int? ?? AppConstants.defaultGlassMl,
        smallGlassMl: r['small_glass_ml'] as int? ?? AppConstants.smallGlassMl,
        largeGlassMl: r['large_glass_ml'] as int? ?? AppConstants.largeGlassMl,
        waterStartMin: r['water_start_min'] as int? ?? AppConstants.defaultWaterStartMinute,
        waterEndMin: r['water_end_min'] as int? ?? AppConstants.defaultWaterEndMinute,
        waterIntervalMin:
            r['water_interval_min'] as int? ?? AppConstants.defaultWaterIntervalMinutes,
        waterRemindersPaused: (r['water_reminders_paused'] as int? ?? 0) == 1,
        medicineRemindersPaused: (r['medicine_reminders_paused'] as int? ?? 0) == 1,
        snoozeMinutes: r['snooze_minutes'] as int? ?? AppConstants.defaultSnoozeMinutes,
        quietModeEnabled: (r['quiet_mode_enabled'] as int? ?? 1) == 1,
        quietStartMin: r['quiet_start_min'] as int? ?? AppConstants.defaultQuietStartMinute,
        quietEndMin: r['quiet_end_min'] as int? ?? AppConstants.defaultQuietEndMinute,
        quietPauseWater: (r['quiet_pause_water'] as int? ?? 1) == 1,
        quietPauseMotivation: (r['quiet_pause_motivation'] as int? ?? 1) == 1,
        quietPauseMedicine: (r['quiet_pause_medicine'] as int? ?? 0) == 1,
        voiceEnabled: (r['voice_enabled'] as int? ?? 1) == 1,
        voiceProfile: VoiceProfile.fromKey(r['voice_profile'] as String?),
        voiceRate: (r['voice_rate'] as num?)?.toDouble() ?? 0.46,
        voicePitch: (r['voice_pitch'] as num?)?.toDouble() ?? 1.08,
        soundEnabled: (r['sound_enabled'] as int? ?? 1) == 1,
        vibrationEnabled: (r['vibration_enabled'] as int? ?? 1) == 1,
        alarmStyle: (r['alarm_style'] as int? ?? 1) == 1,
        motivationEnabled: (r['motivation_enabled'] as int? ?? 1) == 1,
        motivationPerDay: r['motivation_per_day'] as int? ?? 3,
        motivationCategories: (r['motivation_categories'] as String? ?? '')
            .split(',')
            .where((s) => s.trim().isNotEmpty)
            .toList(),
        loveNotesEnabled: (r['love_notes_enabled'] as int? ?? 1) == 1,
        themeMode: themeFromKey(r['theme_mode'] as String?),
        languageCode: r['language_code'] as String? ?? 'en',
        aiEnabled: (r['ai_enabled'] as int? ?? 0) == 1,
        aiConsentGiven: (r['ai_consent_given'] as int? ?? 0) == 1,
        syncEnabled: (r['sync_enabled'] as int? ?? 0) == 1,
        syncConsentGiven: (r['sync_consent_given'] as int? ?? 0) == 1,
        appLockEnabled: (r['app_lock_enabled'] as int? ?? 0) == 1,
        lastSyncAt: SyncEntity.fromMillis(r['last_sync_at']),
        createdAt: AkashaDates.fromMillis(r['created_at'] as int),
        updatedAt: AkashaDates.fromMillis(r['updated_at'] as int),
        deletedAt: SyncEntity.fromMillis(r['deleted_at']),
        isDirty: (r['dirty'] as int? ?? 1) == 1,
      );
}
