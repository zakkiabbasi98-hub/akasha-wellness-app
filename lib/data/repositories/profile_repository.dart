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
///
/// Every write method accepts an optional [Transaction] (`txn`). When one is
/// supplied the method joins the caller's transaction; when it is null the
/// method owns the transaction it opens. This is the only sanctioned pattern in
/// the project (see `AppDatabase.write`).
class ProfileRepository {
  ProfileRepository(this._db);
  final AppDatabase _db;

  static const String _defaultProfileId = 'local-profile';

  Future<UserProfile?> currentProfile({Transaction? txn}) async {
    final rows = await (txn ?? _db.db).query(
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
  ///
  /// Profile + settings are written in one transaction, so a failure can never
  /// leave a user with a profile and no settings row.
  Future<UserProfile> ensureProfile({
    String displayName = 'Akasha',
    Transaction? txn,
  }) =>
      _db.write(txn, (tx) async {
        final existing = await currentProfile(txn: tx);
        if (existing != null) {
          // Repair path: an older build could create a profile without its
          // settings row, which then made every settings read fail.
          await ensureSettings(existing.id, txn: tx);
          return existing;
        }

        final now = DateTime.now();
        final profile = UserProfile(
          id: _defaultProfileId,
          displayName: displayName,
          createdAt: now,
          updatedAt: now,
        );
        // A plain insert: `created_at` is present (so no NOT NULL failure), and
        // any duplicate-id error is real — deleting and recreating the profile
        // would reset `created_at` and detach every child row that references
        // it. The existing-profile check above makes this the only insert path.
        await tx.insert('users', profile.toRow());
        await ensureSettings(profile.id, txn: tx);
        return profile;
      });

  Future<UserProfile> updateProfile(UserProfile profile,
      {Transaction? txn}) async {
    // `toRow()` is insert-shaped and carries the model's own `created_at`, so
    // the row's original creation time is written back unchanged.
    await (txn ?? _db.db).update('users', profile.toRow(),
        where: 'id = ?', whereArgs: [profile.id]);
    return profile;
  }

  /// Marks onboarding complete. Kept in the repository so the profile row and
  /// its settings row commit together — onboarding is never "half done".
  Future<UserProfile> completeOnboarding(String displayName,
          {Transaction? txn}) =>
      _db.write(txn, (tx) async {
        final profile =
            await ensureProfile(displayName: displayName, txn: tx);
        final updated = profile.copyWith(
          displayName: displayName,
          onboardedAt: DateTime.now(),
        );
        return updateProfile(updated, txn: tx);
      });

  // ── Settings ────────────────────────────────────────────────────────────

  Future<UserSettings?> currentSettings({Transaction? txn}) async {
    final rows = await (txn ?? _db.db).query(
      'user_settings',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return UserSettings.fromRow(rows.first);
  }

  Future<UserSettings> ensureSettings(String userId,
          {Transaction? txn}) =>
      _db.write(txn, (tx) async {
        final existing = await currentSettings(txn: tx);
        if (existing != null) return existing;

        final now = DateTime.now();
        final settings = UserSettings(
          id: Ids.newId(),
          userId: userId,
          createdAt: now,
          updatedAt: now,
        );
        await tx.insert('user_settings', settings.toRow());
        return settings;
      });

  Future<UserSettings> saveSettings(UserSettings settings,
      {Transaction? txn}) async {
    await (txn ?? _db.db).update('user_settings', settings.toRow(),
        where: 'id = ?', whereArgs: [settings.id]);
    return settings;
  }

  /// Convenience used by providers: read-modify-write with a copyWith.
  Future<UserSettings> mutateSettings(
    UserSettings Function(UserSettings current) change, {
    Transaction? txn,
  }) =>
      _db.write(txn, (tx) async {
        final profile = await ensureProfile(txn: tx);
        final current = await ensureSettings(profile.id, txn: tx);
        return saveSettings(change(current), txn: tx);
      });

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
