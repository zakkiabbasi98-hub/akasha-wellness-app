import 'dart:math';

import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../core/database/app_database.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/id.dart';
import '../models/mind_models.dart';

/// Serves supportive messages from the local pool with anti-repetition logic,
/// and stores favourites plus per-message rotation metadata.
class MotivationRepository {
  MotivationRepository(this._db);
  final AppDatabase _db;

  final Random _random = Random();

  Future<List<MotivationalMessage>> all({
    MotivationCategory? category,
    bool favoritesOnly = false,
  }) async {
    final where = <String>['deleted_at IS NULL'];
    final args = <Object?>[];
    if (category != null) {
      where.add('category = ?');
      args.add(category.key);
    }
    if (favoritesOnly) where.add('is_favorite = 1');

    final rows = await _db.db.query(
      'motivational_messages',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'category ASC, text ASC',
    );
    return rows.map(MotivationalMessage.fromRow).toList();
  }

  Future<int> count() async {
    final rows = await _db.db.rawQuery(
        'SELECT COUNT(*) AS c FROM motivational_messages WHERE deleted_at IS NULL');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Picks the next message to show.
  ///
  /// Anti-repetition: never a message shown in the last [_recentWindow] picks,
  /// and prefers the least-shown message in the requested categories. That
  /// makes the pool feel much larger than it is without any server.
  Future<MotivationalMessage?> nextMessage({
    required List<MotivationCategory> categories,
    int recentWindow = 20,
  }) async {
    final cats = categories.isEmpty ? MotivationCategory.values : categories;
    final recent = await _db.db.query(
      'motivational_messages',
      where: 'deleted_at IS NULL AND last_shown_at IS NOT NULL',
      orderBy: 'last_shown_at DESC',
      limit: recentWindow,
    );
    final recentIds = recent.map((r) => r['id'] as String).toSet();

    final placeholders = List.filled(cats.length, '?').join(',');
    final rows = await _db.db.query(
      'motivational_messages',
      where: 'deleted_at IS NULL AND category IN ($placeholders)',
      whereArgs: cats.map((c) => c.key).toList(),
      orderBy: 'show_count ASC, RANDOM()',
      limit: 40,
    );
    if (rows.isEmpty) return null;

    final messages = rows.map(MotivationalMessage.fromRow).toList();
    final fresh = messages.where((m) => !recentIds.contains(m.id)).toList();
    final pool = fresh.isNotEmpty ? fresh : messages;

    // Among the least-shown, pick randomly for variety.
    final lowest = pool.map((m) => m.showCount).reduce(min);
    final candidates = pool.where((m) => m.showCount <= lowest + 1).toList();
    final chosen = candidates[_random.nextInt(candidates.length)];
    return chosen;
  }

  /// Records that a message was shown (used by the anti-repetition window).
  Future<void> markShown(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.rawQuery(
      'UPDATE motivational_messages SET last_shown_at = ?, show_count = show_count + 1 '
      'WHERE id = ?',
      [now, id],
    );
  }

  Future<void> toggleFavorite(String id, bool favorite) async {
    await _db.db.update(
      'motivational_messages',
      AppDatabase.stamp({'is_favorite': favorite ? 1 : 0}),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Adds a user-written message to the pool (used by "save my own words").
  Future<MotivationalMessage> addCustom({
    required MotivationCategory category,
    required String text,
  }) async {
    final message = MotivationalMessage(
      id: Ids.newId(),
      category: category,
      text: text.trim(),
      source: 'custom',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isDirty: true,
    );
    await _db.db.insert('motivational_messages', message.toRow());
    return message;
  }

  /// A deterministic "message of the day" so the dashboard doesn't reshuffle
  /// on every rebuild but does change daily.
  Future<MotivationalMessage?> messageOfTheDay({required String dayKey}) async {
    final rows = await _db.db.query(
      'motivational_messages',
      where: 'deleted_at IS NULL',
      orderBy: 'category ASC, text ASC',
    );
    if (rows.isEmpty) return null;
    final messages = rows.map(MotivationalMessage.fromRow).toList();
    final seed = dayKey.codeUnits.fold<int>(7, (acc, c) => (acc * 31 + c) & 0x7FFFFFFF);
    return messages[seed % messages.length];
  }

  // ── Scheduled motivational notifications ────────────────────────────────

  Future<List<int>> scheduledMinutes(String userId) async {
    final rows = await _db.db.query(
      'scheduled_motivations',
      where: 'user_id = ? AND enabled = 1 AND deleted_at IS NULL',
      whereArgs: [userId],
      orderBy: 'minute_of_day ASC',
    );
    return rows.map((r) => r['minute_of_day'] as int).toList();
  }

  /// Distributes [count] gentle nudges across the waking day, avoiding quiet
  /// hours, and never placing two in the same minute.
  Future<List<int>> regenerateSchedule({
    required String userId,
    required int count,
    required int wakeMinute,
    required int sleepMinute,
  }) async {
    final slots = _distribute(
      count: count.clamp(0, 8),
      wakeMinute: wakeMinute,
      sleepMinute: sleepMinute,
    );
    await _db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await txn.update(
        'scheduled_motivations',
        {'deleted_at': now, 'updated_at': now},
        where: 'user_id = ? AND deleted_at IS NULL',
        whereArgs: [userId],
      );
      for (final minute in slots) {
        final row = {
          'id': Ids.slotId('motivation', '$userId:$minute'),
          'user_id': userId,
          'message_id': null,
          'minute_of_day': minute,
          'enabled': 1,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
          'deleted_at': null,
          'dirty': 1,
        };
        await txn.insert('scheduled_motivations', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    return slots;
  }

  List<int> _distribute({
    required int count,
    required int wakeMinute,
    required int sleepMinute,
  }) {
    if (count <= 0) return [];
    final start = wakeMinute;
    var end = sleepMinute;
    if (end <= start) end += 24 * 60; // overnight window
    final span = end - start;
    final step = span / (count + 1);
    return List.generate(count, (i) {
      final raw = start + (step * (i + 1)).round();
      // round to 5 minutes for human-friendly times
      final rounded = (raw / 5).round() * 5;
      return ((rounded % (24 * 60)) + (24 * 60)) % (24 * 60);
    }).toSet().toList()
      ..sort();
  }
}
