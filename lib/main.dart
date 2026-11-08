import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/providers.dart';
import 'core/services/system_channel.dart';
import 'core/notifications/action_controller.dart';
import 'features/sync/cloud_backend.dart';
import 'features/sync/firebase_backend.dart';

/// AKASHA entry point.
///
/// Startup order matters here:
///   1. Open SQLite (and migrate) BEFORE anything renders — every screen reads
///      from it, and a half-open database causes flicker.
///   2. Initialise notifications + timezone data, because the app must be able
///      to schedule even if the user immediately backgrounds it.
///   3. Try Firebase, but never block on it. If it is not configured the app
///      runs exactly as well, fully offline.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final database = AppDatabase.instance;
  await database.open();

  // A container that lives for the whole app so bootstrap services can be
  // resolved before runApp.
  final container = ProviderContainer();
  try {
    // 1. Notifications (channels, tap callbacks, exact-alarm capability).
    final notifications = container.read(notificationServiceProvider);
    await notifications.initialize();

    // 2. First-run data: profile, settings, 16 water slots, message library.
    final seed = container.read(seedServiceProvider);
    await seed.ensureFirstRunData();

    // 3. Reconcile anything the device did while we were closed.
    final profile = await container.read(profileRepositoryProvider).currentProfile();
    if (profile != null) {
      await container.read(medicineRepositoryProvider).reconcileMissedDoses(profile.id);
      await container.read(waterRepositoryProvider).clearExpiredSnoozes(profile.id);
      await container.read(notificationHistoryProvider).prune();
    }

    // 4. Optional cloud backend. Absence is a supported configuration.
    final backend = await _tryFirebase();
    if (backend != null) {
      final sync = container.read(syncServiceProvider);
      // ignore: invalid_use_of_protected_member
      sync.backend = backend;
    }

    // 5. Wire notification actions and replay anything captured while dead.
    final controller = NotificationActionController(
      notifications: notifications,
      water: container.read(waterRepositoryProvider),
      medicine: container.read(medicineRepositoryProvider),
      profiles: container.read(profileRepositoryProvider),
      history: container.read(notificationHistoryProvider),
      scheduler: container.read(reminderSchedulerProvider),
      onDataChanged: () =>
          container.read(dataRevisionProvider.notifier).state++,
    );
    await controller.attach();
    await controller.drainPending();

    // 6. Re-materialise the reminder horizon (idempotent, deterministic ids).
    final exact = await notifications.canScheduleExactAlarms();
    await container.read(reminderSchedulerProvider).rescheduleAll(exact: exact);

    // 7. A full rebuild above already covers any clock/timezone change that
    //    happened while the app was closed, so simply clear the pending native
    //    marker — otherwise the next resume would rebuild a second time for
    //    nothing.
    await _handleNativeRescheduleRequest(container);
  } catch (e, st) {
    // Never let bootstrap prevent the app from opening.
    debugPrint('AKASHA bootstrap warning: $e\n$st');
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AkashaApp(),
    ),
  );
}

Future<CloudBackend?> _tryFirebase() async {
  // Only attempt when the app was built with Firebase config present.
  try {
    return await FirestoreBackend.tryCreate();
  } catch (e) {
    debugPrint('AKASHA: continuing without Firebase ($e)');
    return null;
  }
}

Future<void> _handleNativeRescheduleRequest(ProviderContainer container) async {
  // TimeChangeReceiver.kt cannot reach Dart (no FlutterEngine is spun up), so it
  // leaves a timestamp marker in SharedPreferences. The full rebuild in step 6
  // has just applied the current clock/timezone, so consuming (and discarding)
  // the marker here keeps "exactly one rebuild per change".
  try {
    final channel = container.read(systemChannelProvider);
    await channel.consumeRescheduleRequest();
  } catch (e) {
    debugPrint('AKASHA: could not read native reschedule marker ($e)');
  }
}
