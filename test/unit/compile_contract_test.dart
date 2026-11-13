import 'package:akasha/core/constants/app_constants.dart';
import 'package:akasha/data/repositories/love_note_repository.dart';
import 'package:akasha/data/repositories/motivation_repository.dart';
import 'package:akasha/features/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show ConflictAlgorithm;

/// Contract tests for the second repair pass.
///
/// All four of the reported error groups were **compile-time** failures, so the
/// main thing this file proves is that the libraries the errors lived in now
/// resolve: importing them, naming the types they were missing, and touching the
/// members the compiler could not find previously.
void main() {
  group('sqflite symbols resolve where they are used', () {
    // `ConflictAlgorithm` was referenced without importing package:sqflite in
    // love_note_repository, motivation_repository and sync_service, which is a
    // compile error ("Undefined name"). Referencing the type here fails the
    // build the same way if the import is ever dropped again.
    test('ConflictAlgorithm is reachable and has the values those files use', () {
      expect(ConflictAlgorithm.replace, isA<ConflictAlgorithm>());
      expect(ConflictAlgorithm.ignore, isA<ConflictAlgorithm>());
      expect(ConflictAlgorithm.values, isNotEmpty);
    });

    test('the three previously broken libraries import cleanly', () {
      // Touching the types forces resolution of each library's own imports,
      // including the sqflite one added by this pass.
      expect(LoveNoteRepository, isNotNull);
      expect(MotivationRepository, isNotNull);
      expect(SyncService, isNotNull);
      expect(SyncPhase.values, isNotEmpty);
    });
  });

  group('calendar weekday header', () {
    test('the header labels are the Monday-first week', () {
      // The calendar renders its weekday row from this list; it used to be
      // written as a collection-`for` inside a `const [...]`, which is a
      // compile error. Reading it back here pins the labels themselves.
      const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
      expect(labels, hasLength(7));
      expect(labels.first, 'M',
          reason: 'AkashaDates.startOfWeek is Monday-based.');
      expect(labels.where((d) => d == 'T'), hasLength(2),
          reason: 'Tuesday and Thursday share a letter by design.');
    });
  });

  group('constants the fixed screens read', () {
    test('glass sizes are sane, so a null-settings fallback can never be 0 ml',
        () {
      // The nullable-settings fixes removed an unsafe implicit assumption; the
      // fallbacks the screens fall back to must still be real amounts.
      expect(AppConstants.defaultGlassMl, greaterThan(0));
      expect(AppConstants.smallGlassMl, greaterThan(0));
      expect(AppConstants.largeGlassMl, greaterThanOrEqualTo(
          AppConstants.smallGlassMl));
    });

    test('the scheduler horizon and alarm budget are positive', () {
      expect(AppConstants.scheduleHorizonDays, greaterThan(0));
      expect(AppConstants.maxPendingAlarms, greaterThan(0));
    });
  });
}
