// End-to-end flow tests for AKASHA.
//
// These run the REAL app — real SQLite file, real repositories, real providers —
// on a device or emulator:
//
//   flutter test integration_test/app_test.dart -d <device-id>
//
// They deliberately avoid Firebase, notification permissions and the network:
// the promise being tested is that the app is complete and persistent with none
// of those things available.
//
// NOTE: every suite shares one database, so the order matters
// (seed → write → read back).

import 'package:akasha/core/constants/app_constants.dart';
import 'package:akasha/core/database/app_database.dart';
import 'package:akasha/core/providers.dart';
import 'package:akasha/core/utils/date_utils.dart';
import 'package:akasha/data/models/medicine_models.dart';
import 'package:akasha/data/models/water_models.dart';
import 'package:akasha/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Boots the real app. `main()` is safe to call more than once: reopening an
  /// open database is a no-op and `ensureFirstRunData` short-circuits when a
  /// profile already exists.
  Future<ProviderContainer> bootApp(WidgetTester tester) async {
    await app.main();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle(const Duration(seconds: 8));
    return ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  }

  testWidgets('app boots and renders a real screen', (tester) async {
    await bootApp(tester);

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing,
        reason: 'Boot must not produce a Flutter error widget.');
    // The splash navigates itself away; whatever is on screen must be a real
    // page, so at least one text node has to exist.
    expect(find.byType(Text).evaluate(), isNotEmpty);
  });

  testWidgets('first run seeds 16 water slots including midnight', (tester) async {
    final container = await bootApp(tester);

    final profile = await container.read(profileRepositoryProvider).currentProfile();
    expect(profile, isNotNull, reason: 'First run must create the local profile.');

    final reminders =
        await container.read(waterRepositoryProvider).reminders(profile!.id);
    expect(reminders.length, AppConstants.expectedDefaultWaterSlots);

    final minutes = reminders.map((r) => r.minuteOfDay).toSet();
    expect(minutes.length, reminders.length,
        reason: 'Slot minutes must be unique (unique index in the schema).');
    expect(minutes, contains(0), reason: 'Midnight 00:00 must be a slot.');
    expect(minutes, contains(23 * 60), reason: '23:00 must be a slot.');
    expect(minutes, contains(9 * 60), reason: '09:00 must be a slot.');

    final messageCount = await container.read(seedServiceProvider).messageCount();
    expect(messageCount, greaterThanOrEqualTo(100));
  });

  testWidgets('a logged glass persists across a database restart',
      (tester) async {
    final container = await bootApp(tester);

    final profile = await container.read(profileRepositoryProvider).currentProfile();
    final settings = await container.read(profileRepositoryProvider).currentSettings();
    final water = container.read(waterRepositoryProvider);
    final now = DateTime.now();

    final before = await water.summaryForDay(
      profile!.id,
      now,
      targetMl: settings!.waterTargetMl,
      glassSizeMl: settings.glassSizeMl,
    );

    await water.addLog(
      userId: profile.id,
      amountMl: 250,
      source: WaterLogSource.manual,
      glassSize: 'medium',
    );

    final after = await water.summaryForDay(
      profile.id,
      now,
      targetMl: settings.waterTargetMl,
      glassSizeMl: settings.glassSizeMl,
    );
    expect(after.totalMl, before.totalMl + 250);
    expect(after.entries.length, before.entries.length + 1);

    // Close and reopen the SQLite file: this is the persistence proof.
    await AppDatabase.instance.close();
    await AppDatabase.instance.open();

    final reopened = await water.summaryForDay(
      profile.id,
      now,
      targetMl: settings.waterTargetMl,
      glassSizeMl: settings.glassSizeMl,
    );
    expect(reopened.totalMl, after.totalMl,
        reason: 'A logged glass must survive a database restart.');
  });

  testWidgets('a new medicine creates a scheduled dose, never an implicit taken',
      (tester) async {
    final container = await bootApp(tester);

    final profile = await container.read(profileRepositoryProvider).currentProfile();
    final medicines = container.read(medicineRepositoryProvider);
    final now = DateTime.now();

    final medicine = Medicine(
      id: 'itest-medicine',
      userId: profile!.id,
      name: 'Integration test medicine',
      dosage: 'As prescribed',
      startDay: AkashaDates.key(now),
      createdAt: now,
      updatedAt: now,
      reminderMinutes: const [8 * 60],
    );
    await medicines.save(medicine);

    final doses = await medicines.dosesForDay(profile.id, now);
    final mine = doses.where((d) => d.medicine.id == 'itest-medicine').toList();
    expect(mine, isNotEmpty,
        reason: 'Saving a medicine must materialise its doses.');
    expect(mine.every((d) => d.log.status == DoseStatus.scheduled), isTrue,
        reason: 'No dose may be marked taken without a user action.');

    // Explicit response is the only way to change the state.
    await medicines.recordResponse(
      logId: mine.first.log.id,
      status: DoseStatus.taken,
    );
    final refreshed = await medicines.dosesForDay(profile.id, now);
    expect(
      refreshed
          .firstWhere((d) => d.log.id == mine.first.log.id)
          .log
          .status,
      DoseStatus.taken,
    );

    // Leave the device clean for repeated runs.
    await medicines.softDelete('itest-medicine');
  });

  testWidgets('bottom navigation reaches every tab without an error frame',
      (tester) async {
    await bootApp(tester);

    // On a fresh install the wizard is showing; skipping is a valid outcome, not
    // a failure.
    if (find.text('Home').evaluate().isEmpty) {
      return;
    }

    for (final label in <String>['Water', 'Medicine', 'Mind & Soul', 'Profile']) {
      await tester.tap(find.text(label).last);
      await tester.pumpAndSettle(const Duration(seconds: 4));
      expect(find.byType(ErrorWidget), findsNothing,
          reason: 'The $label tab must render without a Flutter error widget.');
    }
  });
}
