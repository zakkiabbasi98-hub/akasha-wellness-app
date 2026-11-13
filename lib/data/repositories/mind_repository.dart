import 'package:sqflite/sqflite.dart' show ConflictAlgorithm, Transaction;

import '../../core/database/app_database.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/id.dart';
import '../models/mind_models.dart';

/// Mood, journal, gratitude, breathing and reflection persistence.
///
/// Journal content never leaves the device unless Akasha explicitly turns on
/// cloud sync, and even then it is written under her own UID path.
class MindRepository {
  MindRepository(this._db);
  final AppDatabase _db;

  // ── Mood ────────────────────────────────────────────────────────────────

  Future<MoodEntry> addMood({
    required String userId,
    required MoodType mood,
    int intensity = 3,
    String? note,
    DateTime? at,
  }) async {
    final when = at ?? DateTime.now();
    final entry = MoodEntry(
      id: Ids.newId(),
      userId: userId,
      dayKey: AkashaDates.key(when),
      mood: mood,
      intensity: intensity.clamp(1, 5),
      note: note?.trim().isEmpty == true ? null : note?.trim(),
      loggedAt: when,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.db.insert('mood_entries', entry.toRow());
    return entry;
  }

  Future<List<MoodEntry>> moodsForDay(String userId, DateTime day) async {
    final rows = await _db.db.query(
      'mood_entries',
      where: 'user_id = ? AND day_key = ? AND deleted_at IS NULL',
      whereArgs: [userId, AkashaDates.key(day)],
      orderBy: 'logged_at DESC',
    );
    return rows.map(MoodEntry.fromRow).toList();
  }

  Future<MoodEntry?> latestMood(String userId) async {
    final rows = await _db.db.query(
      'mood_entries',
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
      orderBy: 'logged_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : MoodEntry.fromRow(rows.first);
  }

  Future<List<MoodEntry>> moodRange(
    String userId,
    DateTime from,
    DateTime to,
  ) async {
    final rows = await _db.db.query(
      'mood_entries',
      where: 'user_id = ? AND day_key BETWEEN ? AND ? AND deleted_at IS NULL',
      whereArgs: [userId, AkashaDates.key(from), AkashaDates.key(to)],
      orderBy: 'logged_at ASC',
    );
    return rows.map(MoodEntry.fromRow).toList();
  }

  Future<void> deleteMood(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.update(
      'mood_entries',
      {'deleted_at': now, 'updated_at': now, 'dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Counts per mood over a range — powers the weekly pattern chart.
  Future<Map<MoodType, int>> moodDistribution(
    String userId,
    DateTime from,
    DateTime to,
  ) async {
    final entries = await moodRange(userId, from, to);
    final counts = <MoodType, int>{};
    for (final e in entries) {
      counts[e.mood] = (counts[e.mood] ?? 0) + 1;
    }
    return counts;
  }

  // ── Journal ─────────────────────────────────────────────────────────────

  Future<JournalEntry> saveJournal({
    String? id,
    required String userId,
    required String body,
    String? title,
    MoodType? mood,
    List<String> tags = const [],
    bool isPinned = false,
    DateTime? day,
  }) async {
    final now = DateTime.now();
    if (id != null) {
      final existing = await journalById(id);
      if (existing != null) {
        final updated = existing.copyWith(
          title: title,
          body: body,
          mood: mood,
          clearMood: mood == null,
          tags: tags,
          isPinned: isPinned,
        );
        // `toRow()` is insert-shaped, so `created_at` is written back with the
        // value the loaded row carried — an edit never re-dates the entry.
        await _db.db.update('journal_entries', updated.toRow(),
            where: 'id = ?', whereArgs: [id]);
        return updated;
      }
    }
    final entry = JournalEntry(
      id: Ids.newId(),
      userId: userId,
      dayKey: AkashaDates.key(day ?? now),
      title: title?.trim().isEmpty == true ? null : title?.trim(),
      body: body,
      mood: mood,
      tags: tags,
      isPinned: isPinned,
      createdLocal: now,
      createdAt: now,
      updatedAt: now,
    );
    await _db.db.insert('journal_entries', entry.toRow());
    return entry;
  }

  Future<JournalEntry?> journalById(String id) async {
    final rows = await _db.db.query('journal_entries',
        where: 'id = ? AND deleted_at IS NULL', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : JournalEntry.fromRow(rows.first);
  }

  Future<List<JournalEntry>> journalEntries(
    String userId, {
    String? query,
    DateTime? from,
    DateTime? to,
    MoodType? mood,
    int limit = 200,
  }) async {
    final where = <String>['user_id = ?', 'deleted_at IS NULL'];
    final args = <Object?>[userId];

    if (query != null && query.trim().isNotEmpty) {
      where.add('(body LIKE ? OR IFNULL(title, \'\') LIKE ?)');
      final like = '%${query.trim()}%';
      args.add(like);
      args.add(like);
    }
    if (from != null) {
      where.add('day_key >= ?');
      args.add(AkashaDates.key(from));
    }
    if (to != null) {
      where.add('day_key <= ?');
      args.add(AkashaDates.key(to));
    }
    if (mood != null) {
      where.add('mood = ?');
      args.add(mood.key);
    }

    final rows = await _db.db.query(
      'journal_entries',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'is_pinned DESC, created_local DESC',
      limit: limit,
    );
    return rows.map(JournalEntry.fromRow).toList();
  }

  Future<void> deleteJournal(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.update(
      'journal_entries',
      {'deleted_at': now, 'updated_at': now, 'dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> journalCountInRange(String userId, DateTime from, DateTime to) async {
    final rows = await _db.db.rawQuery(
      'SELECT COUNT(*) AS c FROM journal_entries '
      'WHERE user_id = ? AND day_key BETWEEN ? AND ? AND deleted_at IS NULL',
      [userId, AkashaDates.key(from), AkashaDates.key(to)],
    );
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  // ── Gratitude ───────────────────────────────────────────────────────────

  Future<GratitudeEntry> saveGratitude({
    required String userId,
    required List<String> items,
    DateTime? day,
  }) async {
    final target = day ?? DateTime.now();
    final key = AkashaDates.key(target);
    final existing = await gratitudeForDay(userId, target);
    final cleaned = items.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (cleaned.isEmpty) {
      throw ArgumentError('At least one grateful thought is needed');
    }

    final entry = GratitudeEntry(
      id: existing?.id ?? Ids.newId(),
      userId: userId,
      dayKey: key,
      first: cleaned[0],
      second: cleaned.length > 1 ? cleaned[1] : null,
      third: cleaned.length > 2 ? cleaned[2] : null,
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    // Upsert, not REPLACE: `replace` deletes and re-inserts, which would reset
    // `created_at` on a record the user is still editing.
    await AppDatabase.upsert(_db.db, 'gratitude_entries', entry.toRow());
    return entry;
  }

  Future<GratitudeEntry?> gratitudeForDay(String userId, DateTime day) async {
    final rows = await _db.db.query(
      'gratitude_entries',
      where: 'user_id = ? AND day_key = ? AND deleted_at IS NULL',
      whereArgs: [userId, AkashaDates.key(day)],
      limit: 1,
    );
    return rows.isEmpty ? null : GratitudeEntry.fromRow(rows.first);
  }

  Future<List<GratitudeEntry>> gratitudeHistory(String userId, {int limit = 60}) async {
    final rows = await _db.db.query(
      'gratitude_entries',
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
      orderBy: 'day_key DESC',
      limit: limit,
    );
    return rows.map(GratitudeEntry.fromRow).toList();
  }

  // ── Breathing ───────────────────────────────────────────────────────────

  Future<BreathingSession> saveBreathing({
    required String userId,
    required int durationSeconds,
    required bool completed,
    String pattern = '4-4-6',
    DateTime? startedAt,
  }) async {
    final start = startedAt ?? DateTime.now();
    final session = BreathingSession(
      id: Ids.newId(),
      userId: userId,
      dayKey: AkashaDates.key(start),
      startedAt: start,
      durationSeconds: durationSeconds,
      completed: completed,
      pattern: pattern,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _db.db.insert('breathing_sessions', session.toRow());
    return session;
  }

  Future<List<BreathingSession>> breathingForDay(String userId, DateTime day) async {
    final rows = await _db.db.query(
      'breathing_sessions',
      where: 'user_id = ? AND day_key = ? AND deleted_at IS NULL',
      whereArgs: [userId, AkashaDates.key(day)],
      orderBy: 'started_at DESC',
    );
    return rows.map(BreathingSession.fromRow).toList();
  }

  Future<int> breathingMinutesInRange(String userId, DateTime from, DateTime to) async {
    final rows = await _db.db.rawQuery(
      'SELECT COALESCE(SUM(duration_seconds), 0) AS s FROM breathing_sessions '
      'WHERE user_id = ? AND day_key BETWEEN ? AND ? AND deleted_at IS NULL',
      [userId, AkashaDates.key(from), AkashaDates.key(to)],
    );
    return (((rows.first['s'] as num?)?.toInt() ?? 0) / 60).round();
  }

  // ── Reflections ─────────────────────────────────────────────────────────

  Future<Reflection> saveReflection({
    required String userId,
    String? situation,
    String? assumption,
    String? evidenceFor,
    String? alternative,
    String? actionStep,
    bool completed = false,
    MoodType? moodAfter,
    String? id,
  }) async {
    Reflection? existing;
    if (id != null) {
      final rows = await _db.db
          .query('reflections', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isNotEmpty) existing = Reflection.fromRow(rows.first);
    }
    final reflection = Reflection(
      id: existing?.id ?? Ids.newId(),
      userId: userId,
      dayKey: existing?.dayKey ?? AkashaDates.key(DateTime.now()),
      situation: situation ?? existing?.situation,
      assumption: assumption ?? existing?.assumption,
      evidenceFor: evidenceFor ?? existing?.evidenceFor,
      alternative: alternative ?? existing?.alternative,
      actionStep: actionStep ?? existing?.actionStep,
      completed: completed,
      moodAfter: moodAfter ?? existing?.moodAfter,
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    // Upsert, not REPLACE (see the gratitude note above).
    await AppDatabase.upsert(_db.db, 'reflections', reflection.toRow());
    return reflection;
  }

  Future<List<Reflection>> reflections(String userId, {int limit = 30}) async {
    final rows = await _db.db.query(
      'reflections',
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(Reflection.fromRow).toList();
  }

  Future<void> deleteReflection(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.update(
      'reflections',
      {'deleted_at': now, 'updated_at': now, 'dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
