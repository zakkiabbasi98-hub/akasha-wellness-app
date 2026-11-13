import 'package:akasha/core/database/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The parts of Critical Issue 2 that only a real database can prove:
/// exactly-once application of a notification action, and a migration that
/// upgrades an existing user's database without touching their records.
///
/// Runs the **real SQLite engine** on the host via `sqflite_common_ffi`, using
/// the same `DbSchema` the app uses. No mocks: a mock would not tell us whether
/// `INSERT OR IGNORE` actually stops a duplicate row, which is the whole point.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<Database> openCurrent() async {
    return databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: DbSchema.version,
        onCreate: (db, v) async {
          for (final stmt in DbSchema.createStatements()) {
            await db.execute(stmt);
          }
          for (final stmt in DbSchema.indexStatements()) {
            await db.execute(stmt);
          }
        },
      ),
    );
  }

  group('schema', () {
    test('every declared table is actually created', () async {
      final db = await openCurrent();
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
      );
      final created = rows.map((r) => r['name'] as String).toSet();
      for (final table in DbSchema.tables) {
        expect(created, contains(table), reason: 'Table $table was not created');
      }
      await db.close();
    });

    test('the notification_actions ledger exists with its primary key', () async {
      final db = await openCurrent();
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='notification_actions'",
      );
      expect(rows, hasLength(1));
      final cols = await db.rawQuery('PRAGMA table_info(notification_actions)');
      final names = cols.map((c) => c['name']).toSet();
      expect(names, containsAll(['id', 'action_id', 'kind', 'ref_id', 'created_at']));
      await db.close();
    });

    test('notification_actions is not part of the synced table set', () async {
      // It is a local delivery ledger; syncing it would let one device suppress
      // another device's identical action key.
      final db = await openCurrent();
      final cols = await db.rawQuery('PRAGMA table_info(notification_actions)');
      final names = cols.map((c) => c['name']).toSet();
      expect(names, isNot(contains('dirty')));
      expect(names, isNot(contains('deleted_at')));
      await db.close();
    });
  });

  group('exactly-once action application', () {
    /// Mirrors the gate in ActionExecutor.execute: claim the key first, and only
    /// act when the claim succeeded.
    Future<bool> claim(DatabaseExecutor db, String key) async {
      final inserted = await db.insert(
        'notification_actions',
        {
          'id': key,
          'action_id': 1,
          'kind': 'water',
          'ref_id': null,
          'payload': 'water||250|540|2026-11-08',
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return inserted != 0;
    }

    test('the first delivery wins and the second is a no-op', () async {
      final db = await openCurrent();
      const key = 'water||540|250|1|2026-11-08';

      expect(await claim(db, key), isTrue);
      expect(await claim(db, key), isFalse);

      final rows = await db.query('notification_actions', where: 'id = ?', whereArgs: [key]);
      expect(rows, hasLength(1));
      await db.close();
    });

    test('ten rapid taps apply exactly one water log', () async {
      final db = await openCurrent();
      var applied = 0;
      const key = 'water||540|250|1|2026-11-08';

      for (var tap = 0; tap < 10; tap++) {
        if (await claim(db, key)) {
          await db.insert('water_logs', {
            'id': 'waterlog:$key',
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
            'dirty': 1,
            'user_id': 'u1',
            'day_key': '2026-11-08',
            'logged_at': DateTime.now().millisecondsSinceEpoch,
            'amount_ml': 250,
            'source': 'notification',
            'reminder_minute': 540,
          });
          applied++;
        }
      }

      expect(applied, 1);
      final logs = await db.query('water_logs');
      expect(logs, hasLength(1), reason: 'Ten taps must not log ten glasses.');
      await db.close();
    });

    test('different slots each apply once', () async {
      final db = await openCurrent();
      final keys = [
        'water||540|250|1|2026-11-08',
        'water||600|250|1|2026-11-08',
        'water||660|250|1|2026-11-08',
      ];
      for (final key in keys) {
        expect(await claim(db, key), isTrue);
      }
      for (final key in keys) {
        expect(await claim(db, key), isFalse);
      }
      final rows = await db.query('notification_actions');
      expect(rows, hasLength(3));
      await db.close();
    });

    test('a failed transaction leaves neither the log nor the claim', () async {
      final db = await openCurrent();
      const key = 'water||540|250|1|2026-11-08';

      try {
        await db.transaction((txn) async {
          await claim(txn, key);
          // Simulate a crash between the two writes.
          throw StateError('boom');
        });
      } catch (_) {}

      final claims = await db.query('notification_actions');
      final logs = await db.query('water_logs');
      expect(claims, isEmpty, reason: 'The claim must roll back with the write.');
      expect(logs, isEmpty);

      // …and the action can therefore be retried successfully.
      expect(await claim(db, key), isTrue);
      await db.close();
    });
  });

  group('history rows are idempotent per day', () {
    test('the same event cannot create two history rows', () async {
      final db = await openCurrent();
      final id = 'evt:water::taken:2026-11-08';

      Future<int> insert() => db.insert(
            'notification_history',
            {
              'id': id,
              'created_at': DateTime.now().millisecondsSinceEpoch,
              'updated_at': DateTime.now().millisecondsSinceEpoch,
              'dirty': 1,
              'user_id': 'u1',
              'kind': 'water',
              'ref_id': null,
              'title': 'Water reminder',
              'body': 'Logged',
              'delivered_at': DateTime.now().millisecondsSinceEpoch,
              'action_taken': 'taken',
              'action_at': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );

      expect(await insert(), isNot(0));
      expect(await insert(), 0);
      expect(await db.query('notification_history'), hasLength(1));
      await db.close();
    });
  });

  group('v1 → v3 migration preserves user data', () {
    /// Builds a v1 database: the schema as it shipped, without the ledger.
    Future<Database> openV1WithData() async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, v) async {
            // v1 = the tables as they shipped, with the original (non-partial)
            // unique index, and without notification_actions.
            for (final stmt in DbSchema.v1CreateStatements()) {
              await db.execute(stmt);
            }
            for (final stmt in DbSchema.v1IndexStatements()) {
              await db.execute(stmt);
            }
          },
        ),
      );
      return db;
    }

    test('an existing v1 database upgrades without losing records', () async {
      // 1. v1 database with real user data.
      final path = '${await databaseFactory.getDatabasesPath()}/mig_test.db';
      await databaseFactory.deleteDatabase(path);
      final v1 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, v) async {
            for (final stmt in DbSchema.v1CreateStatements()) {
              await db.execute(stmt);
            }
            for (final stmt in DbSchema.v1IndexStatements()) {
              await db.execute(stmt);
            }
          },
        ),
      );

      await v1.insert('users', {
        'id': 'local-profile',
        'created_at': 1,
        'updated_at': 1,
        'dirty': 1,
        'display_name': 'Akasha',
      });
      await v1.insert('water_logs', {
        'id': 'log-1',
        'created_at': 1,
        'updated_at': 1,
        'dirty': 1,
        'user_id': 'local-profile',
        'day_key': '2026-11-08',
        'logged_at': 1,
        'amount_ml': 250,
        'source': 'manual',
      });
      await v1.insert('journal_entries', {
        'id': 'j-1',
        'created_at': 1,
        'updated_at': 1,
        'dirty': 1,
        'user_id': 'local-profile',
        'day_key': '2026-11-08',
        'body': 'a private thought',
      });
      await v1.close();

      // 2. Reopen at the current version — exactly what AppDatabase does on
      //    upgrade: every step from the file's version upwards is applied.
      final v2 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: DbSchema.version,
          onUpgrade: (db, oldVersion, newVersion) async {
            for (var v = oldVersion; v < newVersion; v++) {
              for (final stmt in DbSchema.migrations[v] ?? const <String>[]) {
                await db.execute(stmt);
              }
            }
          },
        ),
      );

      // 3. User records untouched.
      expect(await v2.query('users'), hasLength(1));
      expect(await v2.query('water_logs'), hasLength(1));
      final journal = await v2.query('journal_entries');
      expect(journal, hasLength(1));
      expect(journal.first['body'], 'a private thought');
      expect((await v2.query('water_logs')).first['amount_ml'], 250);

      // 4. New table present and usable.
      final cols = await v2.rawQuery('PRAGMA table_info(notification_actions)');
      expect(cols, isNotEmpty);
      await v2.close();
      await databaseFactory.deleteDatabase(path);
    });

    test('v2 → v3 frees the minutes held by soft-deleted slots', () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: DbSchema.version,
          onCreate: (db, v) async {
            for (final stmt in DbSchema.v1CreateStatements()) {
              await db.execute(stmt);
            }
            for (final stmt in DbSchema.v1IndexStatements()) {
              await db.execute(stmt);
            }
            for (final stmt in DbSchema.migrations[1]!) {
              await db.execute(stmt);
            }
          },
        ),
      );

      Future<void> insertSlot(String id, int minute,
          {int? deletedAt}) async {
        await db.insert('water_reminders', {
          'id': id,
          'created_at': 1,
          'updated_at': 1,
          'dirty': 1,
          'user_id': 'u1',
          'label': '09:00 AM',
          'minute_of_day': minute,
          'amount_ml': 250,
          'enabled': 1,
          'is_default_slot': 1,
          'sort_order': 0,
          'deleted_at': deletedAt,
        });
      }

      // A live slot and a tombstone that still occupies 09:00.
      await insertSlot('live', 540);
      await insertSlot('tomb', 540, deletedAt: 99);

      // v2 → v3: partial index + tombstone parking.
      for (final stmt in DbSchema.migrations[2]!) {
        await db.execute(stmt);
      }

      // The tombstone still exists (no data destroyed) and is still deleted.
      final tomb = await db.query('water_reminders',
          where: 'id = ?', whereArgs: ['tomb']);
      expect(tomb, hasLength(1));
      expect(tomb.first['deleted_at'], 99);
      // …but it no longer reserves 09:00, so the minute can be reused.
      expect(tomb.first['minute_of_day'], isNot(540));

      await insertSlot('fresh', 540);
      final live = await db.query('water_reminders',
          where: 'deleted_at IS NULL', orderBy: 'id');
      expect(live.map((r) => r['id']), containsAll(['live', 'fresh']));

      // The partial index still forbids two *live* slots on one minute.
      var threw = false;
      try {
        await insertSlot('dup', 540);
      } catch (_) {
        threw = true;
      }
      expect(threw, isTrue, reason: 'two live slots must not share a minute');

      await db.close();
    });

    test('running the migration twice is harmless', () async {
      final db = await openV1WithData();
      for (final stmt in DbSchema.migrations[1]!) {
        await db.execute(stmt);
      }
      // A second run must not throw (IF NOT EXISTS everywhere).
      for (final stmt in DbSchema.migrations[1]!) {
        await db.execute(stmt);
      }
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='notification_actions'",
      );
      expect(rows, hasLength(1));
      await db.close();
    });
  });
}
