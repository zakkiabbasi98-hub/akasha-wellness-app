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
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _opening = null;
  }

  Future<void> deleteEverything() async {
    final database = await open();
    final batch = database.batch();
    for (final table in DbSchema.tables.reversed) {
      batch.delete(table);
    }
    await batch.commit(noResult: true);
  }

  Future<T> transaction<T>(Future<T> Function(Transaction txn) action) async {
    final database = await open();
    return database.transaction<T>(action);
  }

  /// Row helper: applies the sync columns to any local write.
  ///
  /// Every row that goes through [stamp] is by definition a local mutation, so
  /// it is always marked `dirty = 1` and given a fresh `updated_at`. Forgetting
  /// this on a single update path is how an offline edit silently never reaches
  /// the cloud, so it is centralised rather than repeated per call site.
  ///
  /// The one place that must *clear* the flag — merging a remote row into the
  /// local mirror — deliberately does not use this helper (see
  /// `SyncService._pullAndMerge`, which inserts with `dirty: 0`).
  static Map<String, Object?> stamp(
    Map<String, Object?> values, {
    bool isInsert = false,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final out = Map<String, Object?>.from(values);
    if (isInsert) {
      out['created_at'] ??= now;
    }
    out['updated_at'] = now;
    out['dirty'] = 1;
    return out;
  }
}
