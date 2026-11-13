import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/notification_service.dart';
import 'core/providers.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/lock/app_lock_gate.dart';

/// Root widget: theme, router, and app-level lifecycle duties.
class AkashaApp extends ConsumerStatefulWidget {
  const AkashaApp({super.key});

  @override
  ConsumerState<AkashaApp> createState() => _AkashaAppState();
}

class _AkashaAppState extends ConsumerState<AkashaApp>
    with WidgetsBindingObserver {
  DateTime? _pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // React to notification taps that arrive while the app is running.
    final notifications = ref.read(notificationServiceProvider);
    notifications.onForegroundTap = (payload) {
      ref.read(dataRevisionProvider.notifier).state++;
    };
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _onResume();
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _pausedAt = DateTime.now();
        ref.read(lockServiceProvider).markUnlocked();
      case AppLifecycleState.detached:
        ref.read(lockServiceProvider).clearGrace();
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _onResume() async {
    // 1. Drain anything the device queued while the app was dead. This is the
    //    recovery path for headless-isolate actions that could not write
    //    immediately; replaying is idempotent, so draining often is free.
    try {
      await ref.read(notificationActionControllerProvider).drainPending();
    } catch (e) {
      debugPrint('AKASHA: resume drain failed: $e');
    }

    // 2. Reconcile the day boundary.
    final profile = await ref.read(profileRepositoryProvider).currentProfile();
    if (profile != null) {
      await ref.read(medicineRepositoryProvider).reconcileMissedDoses(profile.id);
    }
    // 3. Refresh the UI with whatever those actions changed.
    ref.read(dataRevisionProvider.notifier).state++;

    // 3. If we were away across a reminder boundary, re-materialise the
    //    horizon. This is cheap (deterministic ids replace, never duplicate)
    //    and makes DST / timezone changes self-healing without a plugin.
    final paused = _pausedAt;
    if (paused == null || DateTime.now().difference(paused).inMinutes >= 15) {
      await _rebuildSchedule();
      return;
    }

    // 4. Even after a short absence, honour a clock/timezone change that the
    //    native receiver recorded while we were away.
    final changeAtMillis =
        await ref.read(systemChannelProvider).consumeRescheduleRequest();
    final last = _lastScheduledAt;
    if (changeAtMillis != null) {
      final changeAt =
          DateTime.fromMillisecondsSinceEpoch(changeAtMillis);
      if (last == null || !changeAt.isBefore(last)) {
        await _rebuildSchedule();
      }
    }
  }

  /// The instant of the last successful full rebuild, used to decide whether a
  /// pending native clock-change marker is newer than our alarm set.
  static DateTime? _lastScheduledAt;

  Future<void> _rebuildSchedule() async {
    try {
      await ref.read(reminderSchedulerProvider).rescheduleAll();
      _lastScheduledAt = DateTime.now();
    } catch (_) {
      // Not fatal: reminders already scheduled stay scheduled.
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'AKASHA',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Lock the text scale to a sensible band: this design is carefully
        // proportioned, and extreme system scaling would break cards rather
        // than help.
        final media = MediaQuery.of(context);
        final scale = media.textScaler.clamp(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.25,
        );
        return MediaQuery(
          data: media.copyWith(textScaler: scale),
          child: AppLockGate(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

/// Exposed for tests that need a bare notification service reference.
typedef AppNotificationService = NotificationService;
