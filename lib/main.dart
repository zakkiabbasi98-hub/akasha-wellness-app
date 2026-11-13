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
  await _bootstrap();
}

/// Runs the whole start-up sequence and hands the app to `runApp`.
///
/// Split out from [main] so the database-failure screen can retry the *real*
/// sequence (re-open, re-seed, re-schedule) instead of just re-throwing.
Future<void> _bootstrap() async {
  final database = AppDatabase.instance;
  try {
    await database.open();
  } catch (e, st) {
    // Opening (or migrating) SQLite is the one fatal step: every screen reads
    // from it. Never delete the file to recover — that would destroy the user's
    // history — so the failure is shown honestly with a retry.
    debugPrint('AKASHA: database open failed: $e\n$st');
    runApp(StartupFailureApp(
      error: e,
      onRetry: () async {
        await database.close();
        await _bootstrap();
      },
    ));
    return;
  }

  final container = ProviderContainer();
  final notifications = container.read(notificationServiceProvider);

  // ── 1. Notifications ────────────────────────────────────────────────────
  try {
    await notifications.initialize();
  } catch (e, st) {
    debugPrint('AKASHA: notifications unavailable, app continues: $e\n$st');
  }

  // ── 2. First-run data ───────────────────────────────────────────────────
  // Logged with its stack trace and then retried by the profile provider when
  // the splash screen resolves it. Setup is never marked complete unless the
  // writes actually committed.
  try {
    await container.read(seedServiceProvider).ensureFirstRunData();
  } catch (e, st) {
    debugPrint('AKASHA: seeding failed, app continues and will retry: $e\n$st');
  }

  // ── 3. Replay anything the device queued while we were dead ─────────────
  try {
    await container.read(notificationActionControllerProvider).attach();
    await container.read(notificationActionControllerProvider).drainPending();
  } catch (e, st) {
    debugPrint('AKASHA: action replay failed, app continues: $e\n$st');
  }

  // ── 4. Reconcile the past ───────────────────────────────────────────────
  try {
    final profile =
        await container.read(profileRepositoryProvider).currentProfile();
    if (profile != null) {
      await container.read(medicineRepositoryProvider).reconcileMissedDoses(profile.id);
      await container.read(waterRepositoryProvider).clearExpiredSnoozes(profile.id);
      await container.read(notificationHistoryProvider).prune();
      await pruneActionLedger(database);
    }
  } catch (e, st) {
    debugPrint('AKASHA: reconciliation failed, app continues: $e\n$st');
  }

  // ── 5. Optional cloud ───────────────────────────────────────────────────
  final backend = await _tryFirebase();
  if (backend != null) {
    try {
      container.read(syncServiceProvider).backend = backend;
    } catch (e, st) {
      debugPrint('AKASHA: cloud backend not attached: $e\n$st');
    }
  }

  // ── 6. Rebuild the alarm horizon ────────────────────────────────────────
  try {
    await container.read(reminderSchedulerProvider).rescheduleAll();
  } catch (e, st) {
    debugPrint('AKASHA: initial reschedule failed, app continues: $e\n$st');
  }

  // ── 7. Clear the native clock/timezone marker ───────────────────────────
  try {
    await container.read(systemChannelProvider).consumeRescheduleRequest();
  } catch (e, st) {
    debugPrint('AKASHA: could not read native reschedule marker ($e)\n$st');
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
  } catch (e, st) {
    debugPrint('AKASHA: continuing without Firebase ($e)\n$st');
    return null;
  }
}

/// Shown only when SQLite cannot be opened at all.
///
/// Deliberately not a delete-and-reinstall prompt: the database holds the
/// person's own history, and the recovery path is a retry (a transient lock
/// from a previous process is the usual cause). The technical cause is printed
/// to the console, never shown on screen.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFFDF7FA),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.spa_outlined,
                    size: 44, color: Color(0xFF9270C8)),
                const SizedBox(height: 14),
                const Text(
                  'AKASHA could not open its safe space',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3C2E4A),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your saved data is still on this phone. Please try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF7A6B85)),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () async {
                    try {
                      await onRetry();
                    } catch (e, st) {
                      debugPrint('AKASHA: retry failed: $e\n$st');
                    }
                  },
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
