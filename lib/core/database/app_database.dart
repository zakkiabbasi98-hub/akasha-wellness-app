import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'schema.dart';

/// Thin, synchronous-friendly wrapper around the SQLite database.
///
/// Why not Drift: see the note at the top of pubspec.yaml and
/// docs/DATABASE.md. Everything above this file talks to repositories, so the
/// engine is replaceable.
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const String fileName = 'akasha.db';

  Database? _db;
  Future<Database>? _opening;

  bool get isOpen => _db != null;

  /// Opens (and on first run creates + seeds) the database.
  /// Safe to call many times: concurrent callers share one future.
  Future<Database> open() async {
    if (_db != null) return _db!;
    return _opening ??= _openInternal();
  }

  Future<Database> _openInternal() async {
    try {
      final dir = await getDatabasesPath();
      final path = p.join(dir, fileName);
      final db = await openDatabase(
        path,
        version: DbSchema.version,
        onConfigure: (db) async {
          // Referential integrity is essential: deleting a medicine must not
          // orphan its logs.
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          final batch = db.batch();
          for (final stmt in DbSchema.createStatements()) {
            batch.execute(stmt);
          }
          for (final stmt in DbSchema.indexStatements()) {
            batch.execute(stmt);
          }
          await batch.commit(noResult: true);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          for (var v = oldVersion; v < newVersion; v++) {
            for (final stmt in DbSchema.migrations[v] ?? const <String>[]) {
              await db.execute(stmt);
            }
          }
        },
        onDowngrade: onDatabaseDowngradeDelete,
      );
      _db = db;
      return db;
    } catch (e, st) {
      _opening = null;
      debugPrint('AKASHA DB open failed: $e\n$st');
      rethrow;
    }
  }

  Database get db {
    final database = _db;
    if (database == null) {
      throw StateError('AppDatabase.open() must be awaited before use.');
    }
    return database;
  }

  /// Convenience for tests and for wiping everything from Settings.
  ///
  /// Both the handle *and* the memoised open future are dropped, so a later
  /// [open] really re-opens the file instead of returning a closed handle.
  Future<void> close() async {
    final database = _db;
    _db = null;
    _opening = null;
    await database?.close();
  }

  Future<void> deleteEverything() async {
    final database = await open();
    final batch = database.batch();
    for (final table in DbSchema.tables.reversed) {
      batch.delete(table);
    }
    await batch.commit(noResult: true);
  }

  /// Runs [action] in a transaction owned by this method.
  ///
  /// Prefer [write] for repository code: it takes an optional executor so a
  /// caller that already owns a transaction can pass it down instead of opening
  /// a second one.
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final database = await open();
    return database.transaction<T>(action);
  }

  /// Runs [action] against [txn] when a caller already owns a transaction, or
  /// opens (and owns) one otherwise.
  ///
  /// This is the project's single transaction-ownership rule:
  ///
  ///  * the **outermost** call opens the transaction and owns COMMIT/ROLLBACK,
  ///  * every repository / seed / action method beneath it accepts the
  ///    `Transaction` it was handed and only ever uses that executor.
  ///
  /// `Database.transaction` is not re-entrant, and SQLite rejects a second
  /// `BEGIN` on the same connection with exactly the message seen in the field
  /// logs: "cannot start a transaction within a transaction". Centralising the
  /// rule here is what stops it drifting per repository.
  Future<T> write<T>(
    Transaction? txn,
    Future<T> Function(Transaction txn) action,
  ) async {
    if (txn != null) return action(txn);
    final database = await open();
    return database.transaction<T>(action);
  }

  /// Row helper for an INSERT (or an overwrite that must keep REPLACE
  /// semantics): stamps `created_at`, a fresh `updated_at`, and `dirty = 1`.
  ///
  /// `created_at` is `NOT NULL` on every sync table, so an INSERT built without
  /// it fails with `NOT NULL constraint failed: <table>.created_at`. Passing
  /// the model's own [createdAt] means a re-save keeps the row's real creation
  /// time instead of silently resetting it to "now".
  ///
  /// For UPDATE patches use [touch] instead — an update must never rewrite
  /// `created_at`, and must never resurrect a soft-deleted row.
  static Map<String, Object?> insertRow(
    Map<String, Object?> values, {
    DateTime? createdAt,
  }) =>
      stamp(values, isInsert: true, createdAt: createdAt);

  /// Inserts [row], or updates the existing row with the same `id`.
  ///
  /// This is the project's replacement for `ConflictAlgorithm.replace`, which
  /// SQLite implements as **DELETE + INSERT**: it silently drops the old row
  /// (losing `created_at`, and with it the record's real creation time) and
  /// bypasses foreign-key/cascade bookkeeping while doing so.
  ///
  /// The upsert here keeps `created_at` from the existing row, refreshes
  /// `updated_at`, re-marks the row dirty, and — because callers pass the full
  /// row — is also able to *resurrect* a soft-deleted row (a rebuilt reminder
  /// slot with a deterministic id must clear `deleted_at`, not be skipped).
  /// [markDirty] is false only for a row arriving from the cloud: such a row
  /// must keep the remote `updated_at` (so conflict resolution stays honest)
  /// and stay `dirty = 0` (or it would be pushed straight back).
  static Future<void> upsert(
    DatabaseExecutor executor,
    String table,
    Map<String, Object?> row, {
    bool markDirty = true,
  }) async {
    final id = row['id'];
    assert(id != null, 'upsert into $table requires an id');

    final existing = await executor.query(
      table,
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (existing.isEmpty) {
      await executor.insert(table, row);
      return;
    }
    final patch = Map<String, Object?>.from(row)..remove('created_at');
    await executor.update(
      table,
      markDirty ? touch(patch) : patch,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Row helper for an UPDATE patch: refreshes `updated_at` and marks the row
  /// `dirty` for sync, and deliberately writes nothing else.
  static Map<String, Object?> touch(Map<String, Object?> values) {
    final out = Map<String, Object?>.from(values);
    out['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    out['dirty'] = 1;
    return out;
  }

  /// Low-level stamp. Prefer [insertRow] / [touch], which name the intent.
  ///
  /// The one place that must *clear* the dirty flag — merging a remote row into
  /// the local mirror — deliberately does not use this helper (see
  /// `SyncService._pullAndMerge`, which inserts with `dirty: 0`).
  static Map<String, Object?> stamp(
    Map<String, Object?> values, {
    bool isInsert = false,
    DateTime? createdAt,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = Map<String, Object?>.from(values);
    if (isInsert) {
      out['created_at'] ??= createdAt?.millisecondsSinceEpoch ?? now;
    }
    out['updated_at'] = now;
    out['dirty'] = 1;
    return out;
  }
}
