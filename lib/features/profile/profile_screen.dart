import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// Profile tab: her space, her data, her settings.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final reportAsync = ref.watch(todayReportProvider);

    return GradientScaffold(
      body: profileAsync.when(
        loading: () => const Center(child: LoadingDots()),
        error: (_, __) => ErrorStateView(
          onRetry: () => ref.invalidate(profileProvider),
        ),
        data: (profile) {
          final settings = settingsAsync.valueOrNull;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 120),
            children: [
              FadeSlideIn(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: AppColors.pinkLavender),
                      ),
                      child: Container(
                        width: 86,
                        height: 86,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                        child: Center(
                          child: Text(
                            profile.displayName.isEmpty
                                ? '♡'
                                : profile.displayName.substring(0, 1).toUpperCase(),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w600,
                              color: AppColors.purple,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      profile.displayName,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontSize: 21,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Hydrate · Smile · Shine',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            letterSpacing: 1.2,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              FadeSlideIn(
                delay: const Duration(milliseconds: 80),
                child: SoftCard(
                  accent: AppColors.lavender,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Row(
                    children: [
                      ProgressRing(
                        progress: (reportAsync.valueOrNull?.wellnessPoints ?? 0) / 100,
                        size: 72,
                        strokeWidth: 7,
                        gradient: AppColors.pinkLavender,
                        child: Text(
                          '${reportAsync.valueOrNull?.wellnessPoints ?? 0}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.darkText,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Today\'s care',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontSize: 14),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${reportAsync.valueOrNull?.water.totalMl ?? 0} ml water · '
                              '${reportAsync.valueOrNull?.doses.taken ?? 0} doses taken',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.push('${Routes.home}/reports'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                        ),
                        child: const Text('Report', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const SectionHeader(title: 'Your space', icon: Icons.spa_rounded),
              FadeSlideIn(
                delay: const Duration(milliseconds: 120),
                child: SoftCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      SectionTile(
                        icon: Icons.settings_outlined,
                        title: 'Settings',
                        subtitle: 'Reminders, voice, privacy, data',
                        iconColor: AppColors.purple,
                        onTap: () => context.push(Routes.settings),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SectionTile(
                        icon: Icons.alarm_rounded,
                        title: 'Water reminders',
                        subtitle: settings == null
                            ? ''
                            : '${settings.waterIntervalMin} min intervals · '
                                '${AkashaDates.minutesToLabel(settings.waterStartMin)}',
                        iconColor: AppColors.info,
                        onTap: () => context.push(Routes.waterReminders),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SectionTile(
                        icon: Icons.notifications_active_outlined,
                        title: 'Permissions & diagnostics',
                        subtitle: 'Check that reminders can reach you',
                        iconColor: AppColors.warning,
                        onTap: () => context.push(
                          '${Routes.profile}/settings/diagnostics',
                        ),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SectionTile(
                        icon: Icons.history_rounded,
                        title: 'Reminder history',
                        subtitle: 'What was sent, and what you did',
                        iconColor: AppColors.rose,
                        onTap: () => context.push('${Routes.home}/notifications'),
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 16),
                      SectionTile(
                        icon: Icons.calendar_month_rounded,
                        title: 'History calendar',
                        subtitle: 'Look back at any day',
                        iconColor: AppColors.gold,
                        onTap: () => context.push('${Routes.home}/calendar'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const SectionHeader(title: 'About', icon: Icons.info_outline_rounded),
              SoftCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    SectionTile(
                      icon: Icons.favorite_border_rounded,
                      title: 'About AKASHA',
                      subtitle: 'Why this app exists',
                      onTap: () => context.push('${Routes.profile}/settings/about'),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SectionTile(
                      icon: Icons.shield_outlined,
                      title: 'Privacy',
                      subtitle: 'What is stored, and where',
                      onTap: () => context.push(
                        '${Routes.profile}/settings/privacy',
                      ),
                    ),
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    SectionTile(
                      icon: Icons.cloud_outlined,
                      title: 'Cloud sync',
                      subtitle: 'Optional backup, off by default',
                      onTap: () => context.push('${Routes.profile}/settings/sync'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  'AKASHA v1.0.0 · built with care',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                      ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Helper used by the profile screen and settings to confirm destructive data
/// actions with a consistent voice.
Future<void> confirmAndWipe(BuildContext context, WidgetRef ref) async {
  final ok = await showAkashaConfirm(
    context,
    title: 'Delete all personal data?',
    message:
        'This removes your water logs, medicines, journal, moods and every reminder '
        'from this phone. It cannot be undone.',
    confirmLabel: 'Delete everything',
    destructive: true,
    icon: Icons.delete_forever_rounded,
  );
  if (!ok) return;
  await ref.read(profileRepositoryProvider).wipeAll();
  await ref.read(notificationServiceProvider).cancelAll();
  await ref.read(seedServiceProvider).ensureFirstRunData();
  ref.invalidate(dataRevisionProvider);
  if (context.mounted) {
    showAkashaToast(
      context,
      'Your data has been removed.',
      icon: Icons.check_circle_rounded,
      color: AppColors.success,
    );
  }
}
