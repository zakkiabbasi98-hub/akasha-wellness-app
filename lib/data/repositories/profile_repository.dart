import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, Transaction;

import '../../core/database/app_database.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/id.dart';
import '../models/user_profile.dart';
import '../models/user_settings.dart';

/// Owns the local user row + settings row.
///
/// AKASHA has exactly one local profile by design ("a personal app for one
/// person"). Cloud accounts are optional and map onto this row via
/// `firebase_uid`.
class ProfileRepository {
  ProfileRepository(this._db);
  final AppDatabase _db;

  static const String _defaultProfileId = 'local-profile';

  Future<UserProfile?> currentProfile() async {
    final rows = await _db.db.query(
      'users',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UserProfile.fromRow(rows.first);
  }

  /// Creates the profile on first launch. Never overwrites an existing one —
  /// this is the guard that keeps her name and settings across reinstalls of
  /// the onboarding flow.
  Future<UserProfile> ensureProfile({String displayName = 'Akasha'}) async {
    final existing = await currentProfile();
    if (existing != null) return existing;

    final profile = UserProfile(
      id: _defaultProfileId,
      displayName: displayName,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.db.insert('users', profile.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await ensureSettings(profile.id);
    return profile;
  }

  Future<UserProfile> updateProfile(UserProfile profile) async {
    await _db.db.update('users', profile.toRow(),
        where: 'id = ?', whereArgs: [profile.id]);
    return profile;
  }

  Future<void> completeOnboarding(String displayName) async {
    final profile = await ensureProfile(displayName: displayName);
    await updateProfile(profile.copyWith(
      displayName: displayName,
      onboardedAt: DateTime.now(),
    ));
  }

  // ── Settings ────────────────────────────────────────────────────────────

  Future<UserSettings?> currentSettings() async {
    final rows = await _db.db.query(
      'user_settings',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UserSettings.fromRow(rows.first);
  }

  Future<UserSettings> ensureSettings(String userId) async {
    final existing = await currentSettings();
    if (existing != null) return existing;

    final now = DateTime.now();
    final settings = UserSettings(
      id: Ids.newId(),
      userId: userId,
      createdAt: now,
      updatedAt: now,
    );
    await _db.db.insert('user_settings', settings.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return settings;
  }

  Future<UserSettings> saveSettings(UserSettings settings) async {
    await _db.db.update('user_settings', settings.toRow(),
        where: 'id = ?', whereArgs: [settings.id]);
    return settings;
  }

  /// Convenience used by providers: read-modify-write with a copyWith.
  Future<UserSettings> mutateSettings(
    UserSettings Function(UserSettings current) change,
  ) async {
    final profile = await ensureProfile();
    final current = await ensureSettings(profile.id);
    return saveSettings(change(current));
  }

  Future<void> wipeAll() async {
    await _db.deleteEverything();
  }

  /// Exports everything a person owns as a JSON-ish structure (used by
  /// Settings → Data export). Journal bodies are included because the file is
  /// written locally and shared only by an explicit user action.
  Future<Map<String, Object?>> exportSnapshot() async {
    final db = _db.db;
    final result = <String, Object?>{};
    for (final table in ['users', 'user_settings', 'water_logs', 'water_reminders',
      'medicines', 'medicine_logs', 'mood_entries', 'journal_entries',
      'gratitude_entries', 'breathing_sessions', 'love_notes', 'reflections']) {
      result[table] = await db.query(table);
    }
    result['exported_at'] = AkashaDates.millis(DateTime.now());
    result['schema_version'] = 1;
    return result;
  }
}
