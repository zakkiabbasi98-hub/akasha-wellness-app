import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/ai_companion/ai_companion_screen.dart';
import '../../features/breathing/breathing_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/dashboard/app_shell.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/journal/journal_editor_screen.dart';
import '../../features/journal/journal_screen.dart';
import '../../features/love_notes/love_notes_screen.dart';
import '../../features/medicine/add_medicine_screen.dart';
import '../../features/medicine/medicine_history_screen.dart';
import '../../features/medicine/medicine_screen.dart';
import '../../features/mind_soul/mind_soul_screen.dart';
import '../../features/mind_soul/motivation_screen.dart';
import '../../features/mood/mood_history_screen.dart';
import '../../features/mood/mood_screen.dart';
import '../../features/notification_history/notification_history_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/reflection/reflection_screen.dart';
import '../../features/reports/report_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/water_reminder_settings_screen.dart';
import '../../features/settings/notification_settings_screen.dart';
import '../../features/settings/voice_settings_screen.dart';
import '../../features/settings/privacy_settings_screen.dart';
import '../../features/settings/sync_settings_screen.dart';
import '../../features/settings/diagnostics_screen.dart';
import '../../features/settings/about_screen.dart';
import '../../features/gratitude/gratitude_screen.dart';
import '../../features/water/add_reminder_screen.dart';
import '../../features/water/reminder_manager_screen.dart';
import '../../features/water/water_history_screen.dart';
import '../../features/water/water_screen.dart';
import '../../features/water/water_stats_screen.dart';
import '../../features/lock/lock_screen.dart';
import '../providers.dart';

/// Route names in one place so a typo is a compile error, not a dead button.
abstract final class Routes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const lock = '/lock';

  static const home = '/home';
  static const water = '/water';
  static const medicine = '/medicine';
  static const mind = '/mind';
  static const profile = '/profile';

  static const waterReminders = '/water/reminders';
  static const waterReminderAdd = '/water/reminders/add';
  static const waterHistory = '/water/history';
  static const waterStats = '/water/stats';

  static const medicineAdd = '/medicine/add';
  static const medicineHistory = '/medicine/history';

  static const motivation = '/mind/motivation';
  static const journal = '/mind/journal';
  static const journalEditor = '/mind/journal/editor';
  static const mood = '/mind/mood';
  static const moodHistory = '/mind/mood/history';
  static const breathing = '/mind/breathing';
  static const gratitude = '/mind/gratitude';
  static const reflection = '/mind/reflection';
  static const loveNotes = '/mind/love-notes';
  static const aiCompanion = '/mind/companion';

  static const report = '/reports';
  static const calendar = '/calendar';
  static const notificationHistory = '/notifications';

  static const settings = '/settings';
  static const waterSettings = '/settings/water';
  static const voiceSettings = '/settings/voice';
  static const notificationSettings = '/settings/notifications';
  static const privacySettings = '/settings/privacy';
  static const syncSettings = '/settings/sync';
  static const diagnostics = '/settings/diagnostics';
  static const about = '/settings/about';
}

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.splash,
    debugLogDiagnostics: false,
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashScreen()),
      GoRoute(path: Routes.onboarding, builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: Routes.lock, builder: (_, __) => const LockScreen()),

      // ── Tabs: one persistent branch each ───────────────────────────────
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.home,
                pageBuilder: (context, state) => _fade(const DashboardScreen(), state),
                routes: [
                  GoRoute(
                    path: 'reports',
                    pageBuilder: (context, state) => _slide(const ReportScreen(), state),
                  ),
                  GoRoute(
                    path: 'calendar',
                    pageBuilder: (context, state) => _slide(const CalendarScreen(), state),
                  ),
                  GoRoute(
                    path: 'notifications',
                    pageBuilder: (context, state) =>
                        _slide(const NotificationHistoryScreen(), state),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.water,
                pageBuilder: (context, state) => _fade(const WaterScreen(), state),
                routes: [
                  GoRoute(
                    path: 'reminders',
                    pageBuilder: (context, state) =>
                        _slide(const ReminderManagerScreen(), state),
                  ),
                  GoRoute(
                    path: 'reminders/add',
                    pageBuilder: (context, state) {
                      final extra = state.extra;
                      return _slide(
                        AddReminderScreen(
                          editing: extra is WaterReminderArg ? extra.reminder : null,
                        ),
                        state,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'history',
                    pageBuilder: (context, state) =>
                        _slide(const WaterHistoryScreen(), state),
                  ),
                  GoRoute(
                    path: 'stats',
                    pageBuilder: (context, state) => _slide(const WaterStatsScreen(), state),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.medicine,
                pageBuilder: (context, state) => _fade(const MedicineScreen(), state),
                routes: [
                  GoRoute(
                    path: 'add',
                    pageBuilder: (context, state) {
                      final extra = state.extra;
                      return _slide(
                        AddMedicineScreen(
                          editing: extra is MedicineArg ? extra.medicine : null,
                        ),
                        state,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'history',
                    pageBuilder: (context, state) =>
                        _slide(const MedicineHistoryScreen(), state),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.mind,
                pageBuilder: (context, state) => _fade(const MindSoulScreen(), state),
                routes: [
                  GoRoute(
                    path: 'motivation',
                    pageBuilder: (context, state) => _slide(const MotivationScreen(), state),
                  ),
                  GoRoute(
                    path: 'journal',
                    pageBuilder: (context, state) => _slide(const JournalScreen(), state),
                  ),
                  GoRoute(
                    path: 'journal/editor',
                    pageBuilder: (context, state) {
                      final extra = state.extra;
                      return _slide(
                        JournalEditorScreen(
                          entryId: extra is JournalEditorArg ? extra.entryId : null,
                        ),
                        state,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'mood',
                    pageBuilder: (context, state) => _slide(const MoodScreen(), state),
                  ),
                  GoRoute(
                    path: 'mood/history',
                    pageBuilder: (context, state) => _slide(const MoodHistoryScreen(), state),
                  ),
                  GoRoute(
                    path: 'breathing',
                    pageBuilder: (context, state) => _slide(const BreathingScreen(), state),
                  ),
                  GoRoute(
                    path: 'gratitude',
                    pageBuilder: (context, state) => _slide(const GratitudeScreen(), state),
                  ),
                  GoRoute(
                    path: 'reflection',
                    pageBuilder: (context, state) => _slide(const ReflectionScreen(), state),
                  ),
                  GoRoute(
                    path: 'love-notes',
                    pageBuilder: (context, state) => _slide(const LoveNotesScreen(), state),
                  ),
                  GoRoute(
                    path: 'companion',
                    pageBuilder: (context, state) =>
                        _slide(const AiCompanionScreen(), state),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: Routes.profile,
                pageBuilder: (context, state) => _fade(const ProfileScreen(), state),
                routes: [
                  GoRoute(
                    path: 'settings',
                    pageBuilder: (context, state) => _slide(const SettingsScreen(), state),
                    routes: [
                      GoRoute(
                        path: 'water',
                        pageBuilder: (context, state) =>
                            _slide(const WaterReminderSettingsScreen(), state),
                      ),
                      GoRoute(
                        path: 'voice',
                        pageBuilder: (context, state) =>
                            _slide(const VoiceSettingsScreen(), state),
                      ),
                      GoRoute(
                        path: 'notifications',
                        pageBuilder: (context, state) =>
                            _slide(const NotificationSettingsScreen(), state),
                      ),
                      GoRoute(
                        path: 'privacy',
                        pageBuilder: (context, state) =>
                            _slide(const PrivacySettingsScreen(), state),
                      ),
                      GoRoute(
                        path: 'sync',
                        pageBuilder: (context, state) =>
                            _slide(const SyncSettingsScreen(), state),
                      ),
                      GoRoute(
                        path: 'diagnostics',
                        pageBuilder: (context, state) =>
                            _slide(const DiagnosticsScreen(), state),
                      ),
                      GoRoute(
                        path: 'about',
                        pageBuilder: (context, state) => _slide(const AboutScreen(), state),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // Convenience aliases so deeply-linked screens still work if opened
      // directly (e.g. from a notification tap).
      GoRoute(
        path: '/settings',
        redirect: (_, __) => '/profile/settings',
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.spa_outlined, size: 42, color: Color(0xFFCBB5F5)),
              const SizedBox(height: 12),
              Text('That page drifted away', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              Builder(
                builder: (context) => OutlinedButton(
                  onPressed: () => context.go(Routes.home),
                  child: const Text('Back home'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
});

CustomTransitionPage<void> _fade(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

CustomTransitionPage<void> _slide(Widget child, GoRouterState state) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.06, 0),
          end: Offset.zero,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// Route argument wrappers (kept simple and typed).
class WaterReminderArg {
  const WaterReminderArg(this.reminder);
  final dynamic reminder;
}

class MedicineArg {
  const MedicineArg(this.medicine);
  final dynamic medicine;
}

class JournalEditorArg {
  const JournalEditorArg(this.entryId);
  final String? entryId;
}
