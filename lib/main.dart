import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/notifications/background_actions.dart';
import 'core/providers.dart';
import 'features/sync/cloud_backend.dart';
import 'features/sync/firebase_backend.dart';

/// AKASHA entry point.
///
/// Startup order — each step is individually failure-tolerant, because a
/// wellness app that refuses to open is worse than one missing a reminder:
///
///  1. Open + migrate SQLite. This one **is** fatal if it fails: every screen
///     reads from it, and opening a half-initialised database would show empty
///     states that look like data loss.
///  2. Initialise notifications and timezone data.
///  3. Seed first-run data (profile, settings, the 16 water slots, messages).
///  4. Replay notification actions that arrived while the app was dead.
///  5. Reconcile yesterday (missed doses, expired snoozes, history pruning).
///  6. Try Firebase — never block on it, never fail because of it.
///  7. Re-materialise the reminder horizon.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final database = AppDatabase.instance;
  await database.open();

  final container = ProviderContainer();
  final notifications = container.read(notificationServiceProvider);

  // ── 1. Notifications ────────────────────────────────────────────────────
  try {
    await notifications.initialize();
  } catch (e) {
    debugPrint('AKASHA: notifications unavailable, app continues: $e');
  }

  // ── 2. First-run data ───────────────────────────────────────────────────
  try {
    await container.read(seedServiceProvider).ensureFirstRunData();
  } catch (e) {
    debugPrint('AKASHA: seeding failed, app continues: $e');
  }

  // ── 3. Replay anything the device queued while we were dead ─────────────
  // This is the half of repair R2 that recovers actions taken during the window
  // where the headless isolate chose to queue rather than write.
  try {
    await container.read(notificationActionControllerProvider).attach();
    await container.read(notificationActionControllerProvider).drainPending();
  } catch (e) {
    debugPrint('AKASHA: action replay failed, app continues: $e');
  }

  // ── 4. Reconcile the past ───────────────────────────────────────────────
  try {
    final profile = await container.read(profileRepositoryProvider).currentProfile();
    if (profile != null) {
      await container.read(medicineRepositoryProvider).reconcileMissedDoses(profile.id);
      await container.read(waterRepositoryProvider).clearExpiredSnoozes(profile.id);
      await container.read(notificationHistoryProvider).prune();
      await pruneActionLedger(database);
    }
  } catch (e) {
    debugPrint('AKASHA: reconciliation failed, app continues: $e');
  }

  // ── 5. Optional cloud ───────────────────────────────────────────────────
  final backend = await _tryFirebase();
  if (backend != null) {
    try {
      container.read(syncServiceProvider).backend = backend;
    } catch (e) {
      debugPrint('AKASHA: cloud backend not attached: $e');
    }
  }

  // ── 6. Rebuild the alarm horizon ────────────────────────────────────────
  try {
    await container.read(reminderSchedulerProvider).rescheduleAll();
  } catch (e) {
    debugPrint('AKASHA: initial reschedule failed, app continues: $e');
  }

  // ── 7. Clear the native clock/timezone marker ───────────────────────────
  // Step 6 already applied the current clock and zone, so consuming the marker
  // keeps "exactly one rebuild per change" instead of rebuilding forever.
  try {
    await container.read(systemChannelProvider).consumeRescheduleRequest();
  } catch (e) {
    debugPrint('AKASHA: could not read native reschedule marker ($e)');
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AkashaApp(),
    ),
  );
}

Future<CloudBackend?> _tryFirebase() async {
  try {
    return await FirestoreBackend.tryCreate();
  } catch (e) {
    debugPrint('AKASHA: continuing without Firebase ($e)');
    return null;
  }
}
