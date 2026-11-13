import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

import '../../core/database/app_database.dart';
import '../../core/utils/id.dart';
import '../models/mind_models.dart';

/// Little Love Notes — entirely local by default.
///
/// There is deliberately NO hidden channel here: notes are written by whoever
/// holds the device (or, if a future release adds remote notes, only via an
/// explicitly linked, authenticated account with Akasha's consent). Nothing is
/// shared unless she turns on cloud sync.
class LoveNoteRepository {
  LoveNoteRepository(this._db);
  final AppDatabase _db;

  Future<List<LoveNote>> all(String userId) async {
    final rows = await _db.db.query(
      'love_notes',
      where: 'user_id = ? AND deleted_at IS NULL',
      whereArgs: [userId],
      orderBy: 'is_favorite DESC, created_at DESC',
    );
    return rows.map(LoveNote.fromRow).toList();
  }

  Future<List<LoveNote>> enabled(String userId) async {
    final rows = await _db.db.query(
      'love_notes',
      where: 'user_id = ? AND deleted_at IS NULL AND enabled = 1',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return rows.map(LoveNote.fromRow).toList();
  }

  Future<LoveNote> save({
    String? id,
    required String userId,
    required String text,
    String author = 'Someone who cares',
    int? minuteOfDay,
    bool enabled = true,
    bool isFavorite = false,
  }) async {
    LoveNote? existing;
    if (id != null) {
      final rows = await _db.db
          .query('love_notes', where: 'id = ?', whereArgs: [id], limit: 1);
      if (rows.isNotEmpty) existing = LoveNote.fromRow(rows.first);
    }
    final note = LoveNote(
      id: existing?.id ?? Ids.newId(),
      userId: userId,
      text: text.trim(),
      author: author.trim().isEmpty ? 'Someone who cares' : author.trim(),
      minuteOfDay: minuteOfDay ?? existing?.minuteOfDay ?? 21 * 60,
      enabled: enabled,
      isFavorite: isFavorite,
      lastDeliveredAt: existing?.lastDeliveredAt,
      deliveryCount: existing?.deliveryCount ?? 0,
      source: existing?.source ?? 'local',
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    // Upsert, not REPLACE: editing a note must not reset its `created_at`,
    // nor delete the row a sync tombstone refers to.
    await AppDatabase.upsert(_db.db, 'love_notes', note.toRow());
    return note;
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _db.db.update(
      'love_notes',
      AppDatabase.touch({'enabled': enabled ? 1 : 0}),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> toggleFavorite(String id, bool favorite) async {
    await _db.db.update(
      'love_notes',
      AppDatabase.touch({'is_favorite': favorite ? 1 : 0}),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markDelivered(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    // `rawUpdate`, not `rawQuery`: an UPDATE issued through a query call is
    // executed (so it "works") but its result is thrown away unchecked and it
    // reads as a SELECT to anyone scanning the code.
    await _db.db.rawUpdate(
      'UPDATE love_notes SET last_delivered_at = ?, '
      'delivery_count = delivery_count + 1, updated_at = ?, dirty = 1 '
      'WHERE id = ?',
      [now, now, id],
    );
  }

  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.db.update(
      'love_notes',
      {'deleted_at': now, 'updated_at': now, 'dirty': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Seeds a small set of example notes the very first time the feature is
  /// opened, so the screen is never a blank wall. These are real, editable
  /// rows — not placeholder text drawn in the UI.
  Future<void> seedIfEmpty(String userId) async {
    final existing = await all(userId);
    if (existing.isNotEmpty) return;
    final seeds = [
      'Just checking on you. Don\'t forget how special you are. ❤️',
      'Keep smiling, Akasha. Your happiness matters.',
      'Take care of yourself. You deserve all the beautiful things in life.',
      'Someone is always wishing you the best.',
    ];
    for (var i = 0; i < seeds.length; i++) {
      await save(
        userId: userId,
        text: seeds[i],
        author: 'Someone who cares',
        minuteOfDay: 12 * 60 + i * 60,
        enabled: i == 0,
      );
    }
  }
}
