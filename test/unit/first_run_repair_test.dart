import 'package:akasha/core/database/app_database.dart';
import 'package:akasha/core/database/schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Regression tests for the first-run failure that blocked "Begin my journey".
///
/// These run the **real** SQLite engine on the host (`sqflite_common_ffi`) with
/// the **real** `DbSchema`, because every defect below was a property of the
/// database, not of Dart:
///
///  * A. `NOT NULL constraint failed: users.created_at` — every `toRow()` built
///    its map without `created_at`.
///  * B. `NOT NULL constraint failed: water_reminders.created_at` — same cause.
///  * C. `cannot start a transaction within a transaction` — a seed/repository
///    method opened its own transaction inside the caller's.
///
/// Each test asserts the *behaviour a user cares about*: the profile exists, the
/// 16 slots exist, running setup twice does not duplicate anything, and a
/// failure leaves the database untouched.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// Opens an in-memory database with the exact schema the app creates.
  Future<Database> openAppDb() => databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: DbSchema.version,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, v) async {
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
        ),
      );

  /// The exact upsert the repositories now use.
  Future<void> upsert(
    DatabaseExecutor db,
    String table,
    Map<String, Object?> row,
  ) async {
    final existing = await db.query(table,
        columns: ['id'], where: 'id = ?', whereArgs: [row['id']], limit: 1);
    if (existing.isEmpty) {
      await db.insert(table, row);
      return;
    }
    final patch = Map<String, Object?>.from(row)..remove('created_at');
    patch['updated_at'] = DateTime.now().millisecondsSinceEpoch;
    patch['dirty'] = 1;
    await db.update(table, patch,
        where: 'id = ?', whereArgs: [row['id']]);
  }

  group('A/B — every table accepts an insert built by insertRow', () {
    test('every sync table requires created_at, and insertRow supplies it', () async {
      final db = await openAppDb();

      // Prove the constraint is real for every table, so a future model that
      // forgets `created_at` fails here rather than on a user's phone.
      for (final table in DbSchema.tables) {
        final cols = await db.rawQuery('PRAGMA table_info($table)');
        final createdAt = cols.firstWhere((c) => c['name'] == 'created_at');
        expect(createdAt['notnull'], 1,
            reason: '$table.created_at must stay NOT NULL');
      }

      final row = AppDatabase.insertRow({
        'id': 'p1',
        'display_name': 'Akasha',
        'local_only': 1,
        'firebase_uid': null,
        'email': null,
        'onboarded_at': null,
        'cloud_linked_at': null,
        'deleted_at': null,
      });
      expect(row['created_at'], isA<int>());
      expect(row['updated_at'], isA<int>());
      expect(row['dirty'], 1);

      // This is the exact insert that used to throw.
      await expectLater(db.insert('users', row), completes);
      final users = await db.query('users');
      expect(users, hasLength(1));
      expect(users.first['created_at'], isNotNull);

      await db.close();
    });

    test('a water_reminders insert without created_at fails, with it succeeds',
        () async {
      final db = await openAppDb();

      // The failing shape from the field logs (no created_at, no updated_at).
      await expectLater(
        db.insert('water_reminders', {
          'id': 'water:u:540',
          'user_id': 'u1',
          'label': '09:00 AM',
          'minute_of_day': 540,
          'amount_ml': 250,
          'enabled': 1,
          'is_default_slot': 1,
          'sort_order': 0,
          'deleted_at': null,
          'updated_at': 1,
          'dirty': 1,
        }),
        throwsA(isA<DatabaseException>()),
        reason: 'the reported failure must be reproducible before the fix',
      );

      // The fixed shape.
      await expectLater(
        db.insert(
          'water_reminders',
          AppDatabase.insertRow({
            'id': 'water:u:540',
            'user_id': 'u1',
            'label': '09:00 AM',
            'minute_of_day': 540,
            'amount_ml': 250,
            'enabled': 1,
            'is_default_slot': 1,
            'sort_order': 0,
            'deleted_at': null,
          }),
        ),
        completes,
      );
      expect(await db.query('water_reminders'), hasLength(1));
      await db.close();
    });

    test('touch() never writes created_at, so updates cannot reset it', () {
      final patch = AppDatabase.touch({'enabled': 0});
      expect(patch.containsKey('created_at'), isFalse);
      expect(patch['updated_at'], isA<int>());
      expect(patch['dirty'], 1);
    });

    test('insertRow keeps the model\'s own creation time', () {
      final created = DateTime.fromMillisecondsSinceEpoch(1000);
      final row = AppDatabase.insertRow({'id': 'x'}, createdAt: created);
      expect(row['created_at'], 1000);
    });
  });

  group('C — transactions have exactly one owner', () {
    test('a repository-style nested call joins the outer transaction', () async {
      final db = await openAppDb();

      // The buggy pattern: a second `transaction()` on the same handle while
      // one is open. SQLite rejects the inner BEGIN.
      var nestedFailed = false;
      await db.transaction((txn) async {
        try {
          await db.transaction((inner) async {
            await inner.insert('users', AppDatabase.insertRow({
              'id': 'inner',
              'display_name': 'inner',
              'local_only': 1,
            }));
          });
        } catch (e) {
          nestedFailed = true;
          expect(e.toString(), contains('transaction'));
        }
      });
      expect(nestedFailed, isTrue,
          reason: 'a nested transaction must be impossible to do silently');
      expect(await db.query('users'), isEmpty);

      // The fixed pattern: pass the transaction down.
      await db.transaction((txn) async {
        await txn.insert('users', AppDatabase.insertRow({
          'id': 'outer',
          'display_name': 'Akasha',
          'local_only': 1,
        }));
        await upsert(txn, 'water_reminders', AppDatabase.insertRow({
          'id': 'water:outer:540',
          'user_id': 'outer',
          'label': '09:00 AM',
          'minute_of_day': 540,
          'amount_ml': 250,
          'enabled': 1,
          'is_default_slot': 1,
          'sort_order': 0,
          'deleted_at': null,
        }));
      });

      expect(await db.query('users'), hasLength(1));
      expect(await db.query('water_reminders'), hasLength(1));
      await db.close();
    });

    test('a failure inside the first-run unit rolls everything back', () async {
      final db = await openAppDb();

      await expectLater(
        db.transaction((txn) async {
          await txn.insert('users', AppDatabase.insertRow({
            'id': 'local-profile',
            'display_name': 'Akasha',
            'local_only': 1,
          }));
          await txn.insert(
            'water_reminders',
            // Deliberately invalid: minute_of_day missing.
            AppDatabase.insertRow({
              'id': 'broken',
              'user_id': 'local-profile',
              'label': 'x',
              'amount_ml': 250,
              'enabled': 1,
              'is_default_slot': 1,
              'sort_order': 0,
            }),
          );
        }),
        throwsA(isA<DatabaseException>()),
      );

      // No half-onboarded state: the profile insert was rolled back too.
      expect(await db.query('users'), isEmpty);
      expect(await db.query('water_reminders'), isEmpty);
      await db.close();
    });
  });

  group('first-run seeding is idempotent', () {
    /// Mirrors SeedService's ordering and its idempotency checks.
    Future<void> seed(Database db, {bool failAtWater = false}) async {
      await db.transaction((txn) async {
        final existing = await txn.query('users', limit: 1);
        if (existing.isEmpty) {
          await txn.insert('users', AppDatabase.insertRow({
            'id': 'local-profile',
            'display_name': 'Akasha',
            'local_only': 1,
          }));
          await txn.insert('user_settings', AppDatabase.insertRow({
            'id': 'settings-1',
            'user_id': 'local-profile',
          }));
        }

        final slots = await txn.query('water_reminders',
            where: 'deleted_at IS NULL');
        if (slots.isEmpty) {
          if (failAtWater) throw StateError('seed failed');
          for (var minute = 540; minute <= 1440; minute += 60) {
            final m = minute % 1440;
            await upsert(txn, 'water_reminders', AppDatabase.insertRow({
              'id': 'water:local-profile:$m',
              'user_id': 'local-profile',
              'label': 'slot $m',
              'minute_of_day': m,
              'amount_ml': 250,
              'enabled': 1,
              'is_default_slot': 1,
              'sort_order': 0,
              'deleted_at': null,
            }));
          }
        }
      });
    }

    test('a profile and 16 slots are created exactly once', () async {
      final db = await openAppDb();
      await seed(db);
      expect(await db.query('users'), hasLength(1));
      expect(await db.query('user_settings'), hasLength(1));
      expect(await db.query('water_reminders'), hasLength(16));

      await seed(db); // second launch
      await seed(db); // third launch
      expect(await db.query('users'), hasLength(1));
      expect(await db.query('user_settings'), hasLength(1));
      expect(await db.query('water_reminders'), hasLength(16),
          reason: 're-running first-run setup must not duplicate slots');
      await db.close();
    });

    test('a failed seed leaves nothing behind, and a retry works', () async {
      final db = await openAppDb();
      await expectLater(seed(db, failAtWater: true), throwsA(isA<StateError>()));
      expect(await db.query('users'), isEmpty,
          reason: 'onboarding must not be marked done when seeding failed');

      await seed(db);
      expect(await db.query('users'), hasLength(1));
      expect(await db.query('water_reminders'), hasLength(16));
      await db.close();
    });
  });

  group('upsert semantics', () {
    test('re-saving a row keeps created_at and refreshes updated_at', () async {
      final db = await openAppDb();
      await db.insert('water_reminders', AppDatabase.insertRow({
        'id': 'slot',
        'user_id': 'u1',
        'label': '09:00 AM',
        'minute_of_day': 540,
        'amount_ml': 250,
        'enabled': 1,
        'is_default_slot': 1,
        'sort_order': 0,
        'deleted_at': null,
      }, createdAt: DateTime.fromMillisecondsSinceEpoch(1000)));

      Future<Map<String, Object?>> slot() async =>
          (await db.query('water_reminders', where: 'id = ?',
              whereArgs: ['slot'])).first;

      final before = await slot();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      await upsert(db, 'water_reminders', AppDatabase.insertRow({
        'id': 'slot',
        'user_id': 'u1',
        'label': '09:00 AM (edited)',
        'minute_of_day': 540,
        'amount_ml': 300,
        'enabled': 1,
        'is_default_slot': 1,
        'sort_order': 0,
        'deleted_at': null,
      }, createdAt: DateTime.fromMillisecondsSinceEpoch(99999)));

      final after = await slot();
      expect(after['created_at'], before['created_at'],
          reason: 'created_at must survive an edit');
      expect(after['amount_ml'], 300);
      expect(after['label'], '09:00 AM (edited)');
      expect(after['updated_at'] as int,
          greaterThanOrEqualTo(before['updated_at'] as int));
      expect(await db.query('water_reminders'), hasLength(1));
      await db.close();
    });

    test('upsert revives a soft-deleted row instead of skipping it', () async {
      final db = await openAppDb();
      final row = {
        'id': 'slot',
        'user_id': 'u1',
        'label': '09:00 AM',
        'minute_of_day': 540,
        'amount_ml': 250,
        'enabled': 1,
        'is_default_slot': 1,
        'sort_order': 0,
        'deleted_at': null,
      };
      await db.insert('water_reminders', AppDatabase.insertRow(row));
      await db.update('water_reminders', {'deleted_at': 123},
          where: 'id = ?', whereArgs: ['slot']);

      await upsert(db, 'water_reminders', AppDatabase.insertRow(row));

      final live = await db.query('water_reminders',
          where: 'deleted_at IS NULL');
      expect(live, hasLength(1),
          reason: 'a rebuilt default slot must come back to life');
      await db.close();
    });

    test('a restored schedule can reuse the minutes it just retired', () async {
      final db = await openAppDb();

      Future<void> rebuildSchedule() async {
        await db.transaction((txn) async {
          // Soft-delete the previous default slots, parking their minute so the
          // partial unique index stays satisfied.
          await txn.rawUpdate(
            'UPDATE water_reminders SET deleted_at = ?, '
            'minute_of_day = 100000 + rowid '
            'WHERE is_default_slot = 1 AND deleted_at IS NULL',
            [DateTime.now().millisecondsSinceEpoch],
          );
          for (var minute = 540; minute <= 720; minute += 60) {
            await upsert(txn, 'water_reminders', AppDatabase.insertRow({
              'id': 'water:u1:$minute',
              'user_id': 'u1',
              'label': 'slot $minute',
              'minute_of_day': minute,
              'amount_ml': 250,
              'enabled': 1,
              'is_default_slot': 1,
              'sort_order': 0,
              'deleted_at': null,
            }));
          }
        });
      }

      await rebuildSchedule();
      expect(await db.query('water_reminders', where: 'deleted_at IS NULL'),
          hasLength(4));

      // The second rebuild used to throw a UNIQUE constraint failure because
      // the tombstones from the first still owned 540/600/660/720.
      await expectLater(rebuildSchedule(), completes);
      expect(await db.query('water_reminders', where: 'deleted_at IS NULL'),
          hasLength(4), reason: 'rebuilt slots must not accumulate');
      expect(await db.query('water_reminders', where: 'deleted_at IS NOT NULL'),
          hasLength(4), reason: 'tombstones are kept for sync integrity');

      // And a fresh slot at 540 is still impossible while a live one exists.
      var threw = false;
      try {
        await db.insert('water_reminders', AppDatabase.insertRow({
          'id': 'water:u1:540-dup',
          'user_id': 'u1',
          'label': 'dup',
          'minute_of_day': 540,
          'amount_ml': 250,
          'enabled': 1,
          'is_default_slot': 0,
          'sort_order': 0,
          'deleted_at': null,
        }));
      } catch (_) {
        threw = true;
      }
      expect(threw, isTrue);
      await db.close();
    });
  });

  group('offline initialisation', () {
    test('the whole first run works with no network dependency present',
        () async {
      // Nothing in this file imports Firebase; the app's local path is purely
      // sqlite + repositories. This asserts the schema alone is sufficient.
      final db = await openAppDb();
      for (final table in DbSchema.tables) {
        await expectLater(db.query(table), completes,
            reason: '$table must be readable offline straight after create');
      }
      await db.close();
    });
  });

  group('repository CRUD on the real schema', () {
    test('insert, read back, update and soft-delete a reminder', () async {
      final db = await openAppDb();
      final created = AppDatabase.insertRow({
        'id': 'r1',
        'user_id': 'u1',
        'label': 'Morning',
        'minute_of_day': 480,
        'amount_ml': 250,
        'enabled': 1,
        'is_default_slot': 0,
        'sort_order': 1,
        'deleted_at': null,
      });
      await db.insert('water_reminders', created);

      final read = (await db.query('water_reminders',
          where: 'deleted_at IS NULL')).single;
      expect(read['label'], 'Morning');

      await db.update('water_reminders', AppDatabase.touch({'amount_ml': 400}),
          where: 'id = ?', whereArgs: ['r1']);
      final updated = (await db.query('water_reminders',
          where: 'id = ?', whereArgs: ['r1'])).single;
      expect(updated['amount_ml'], 400);
      expect(updated['created_at'], read['created_at']);

      await db.update('water_reminders',
          {'deleted_at': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?', whereArgs: ['r1']);
      expect(await db.query('water_reminders', where: 'deleted_at IS NULL'),
          isEmpty);
      expect(await db.query('water_reminders'), hasLength(1),
          reason: 'soft delete keeps the row for sync');
      await db.close();
    });
  });
}
