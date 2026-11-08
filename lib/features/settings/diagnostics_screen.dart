import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// Permissions & diagnostics: the honest answer to "why did (or didn't) that
/// reminder reach me?".
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(schedulingStatusProvider);

    return GradientScaffold(
      body: Column(
        children: [
          AkashaHeader(
            title: 'Diagnostics',
            subtitle: 'Check that reminders can reach you',
            trailing: HeaderAction(
              icon: Icons.refresh_rounded,
              onTap: () {
                ref.invalidate(schedulingStatusProvider);
                ref.invalidate(waterRemindersProvider);
              },
            ),
          ),
          Expanded(
            child: statusAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (e, __) => ErrorStateView(
                message: 'Could not read the device status.',
                onRetry: () => ref.invalidate(schedulingStatusProvider),
              ),
              data: (status) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                children: [
                  SoftCard(
                    accent: status.pendingTotal > 0
                        ? AppColors.lavender
                        : AppColors.peach,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              status.pendingTotal > 0
                                  ? Icons.check_circle_rounded
                                  : Icons.error_outline_rounded,
                              size: 20,
                              color: status.pendingTotal > 0
                                  ? AppColors.success
                                  : AppColors.warning,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                status.pendingTotal > 0
                                    ? '${status.pendingTotal} reminders scheduled'
                                    : 'No reminders are scheduled right now',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontSize: 14.5),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${status.pendingWater} water · '
                          '${status.pendingMedicine} medicine · '
                          '${AppConstants.scheduleHorizonDays}-day horizon',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionHeader(
                      title: 'Permissions', icon: Icons.verified_user_outlined),
                  SoftCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        _Check(
                          title: 'Notifications allowed',
                          ok: status.notificationsEnabled,
                          detail: status.notificationsEnabled
                              ? 'Android will show AKASHA reminders.'
                              : 'Reminders cannot appear until notifications are allowed.',
                          actionLabel: status.notificationsEnabled ? null : 'Open settings',
                          onAction: () async =>
                              ref.read(notificationServiceProvider).requestPermission(),
                        ),
                        _Check(
                          title: 'Exact alarms allowed',
                          ok: status.exactAlarms,
                          detail: status.exactAlarms
                              ? 'Reminders land at the exact minute.'
                              : 'Android will deliver reminders a little late '
                                  '(inexact). Granting "Alarms & reminders" fixes it.',
                          actionLabel: status.exactAlarms ? null : 'Grant',
                          onAction: () async {
                            await ref.read(systemChannelProvider).openExactAlarmSettings();
                            await Future.delayed(const Duration(seconds: 2));
                            ref.invalidate(schedulingStatusProvider);
                          },
                        ),
                        _Check(
                          title: 'Full-screen reminders',
                          ok: status.fullScreenAllowed,
                          detail: status.fullScreenAllowed
                              ? 'Android allows an alarm-style reminder over the lock screen.'
                              : 'Not permitted, so reminders show as heads-up notifications. '
                                  'This is a normal, policy-compliant fallback.',
                          actionLabel: null,
                        ),
                        _Check(
                          title: 'Battery optimisation',
                          ok: !status.batteryOptimised,
                          detail: status.batteryOptimised
                              ? 'Android may delay background reminders to save power. '
                                  'Exempting AKASHA makes timing more reliable.'
                              : 'AKASHA is exempt from battery optimisation.',
                          actionLabel:
                              status.batteryOptimised ? 'Fix' : null,
                          onAction: () async {
                            await ref
                                .read(systemChannelProvider)
                                .openBatteryOptimizationSettings();
                            await Future.delayed(const Duration(seconds: 2));
                            ref.invalidate(schedulingStatusProvider);
                          },
                        ),
                        _Check(
                          title: 'Do Not Disturb',
                          ok: !status.dndActive,
                          okWhenFalseOnly: true,
                          detail: status.dndActive
                              ? 'Do Not Disturb is currently on. Reminders are delivered '
                                  'but may stay silent — that is Android respecting your '
                                  'choice, not a bug.'
                              : 'Do Not Disturb is off.',
                          actionLabel: null,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionHeader(
                      title: 'Test it yourself', icon: Icons.science_outlined),
                  SoftCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        SectionTile(
                          icon: Icons.notifications_active_rounded,
                          title: 'Send a test water reminder',
                          subtitle: 'Arrives in 5 seconds',
                          iconColor: AppColors.info,
                          onTap: () async {
                            final notifications = ref.read(notificationServiceProvider);
                            await notifications.showNow(
                              id: 99001,
                              title: 'Time for water, Akasha ♡',
                              body:
                                  'This is a test. If you can see this, reminders work.',
                            );
                            await ref
                                .read(voiceServiceProvider)
                                .speak("Hey Akasha! It's time to drink some water.");
                            if (context.mounted) {
                              showAkashaToast(
                                context,
                                'Test reminder sent. Check your notification shade.',
                                icon: Icons.notifications_active_rounded,
                                color: AppColors.info,
                              );
                            }
                          },
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        SectionTile(
                          icon: Icons.restart_alt_rounded,
                          title: 'Rebuild the whole schedule',
                          subtitle: 'Safe and idempotent — never duplicates',
                          iconColor: AppColors.purple,
                          onTap: () async {
                            final exact = await ref
                                .read(notificationServiceProvider)
                                .canScheduleExactAlarms();
                            await ref
                                .read(reminderSchedulerProvider)
                                .rescheduleAll(exact: exact);
                            ref.invalidate(schedulingStatusProvider);
                            if (context.mounted) {
                              showAkashaToast(
                                context,
                                'Schedule rebuilt.',
                                icon: Icons.check_circle_rounded,
                                color: AppColors.success,
                              );
                            }
                          },
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        SectionTile(
                          icon: Icons.volume_up_rounded,
                          title: 'Test the voice',
                          subtitle: 'Uses your selected voice style',
                          iconColor: AppColors.rose,
                          onTap: () async {
                            final settings =
                                ref.read(settingsControllerProvider).valueOrNull;
                            await ref.read(voiceServiceProvider).speak(
                                  "Hey Akasha! It's time to drink some water.",
                                  profile: settings?.voiceProfile,
                                );
                          },
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        SectionTile(
                          icon: Icons.settings_applications_rounded,
                          title: 'Open Android app settings',
                          subtitle: 'Notifications, battery, permissions',
                          iconColor: AppColors.warning,
                          onTap: () => ref.read(systemChannelProvider).openAppSettings(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionHeader(
                      title: 'Honest limitations', icon: Icons.info_outline_rounded),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _Limit(
                          text:
                              'If Android force-stops the app, alarms are cancelled by the '
                              'system until you open the app again. No app can override that.',
                        ),
                        _Limit(
                          text:
                              'Some manufacturers (Xiaomi, Oppo, Vivo, Samsung, Huawei) apply '
                              'extra background restrictions. Exempting AKASHA from battery '
                              'optimisation usually helps.',
                        ),
                        const _Limit(
                          text:
                              'Do Not Disturb, silent mode and notification channel settings '
                              'control whether a reminder is loud, silent or blocked. AKASHA '
                              'never tries to bypass them.',
                        ),
                        _Limit(
                          text:
                              'Device time is ${AkashaDates.minutesToLabel(AkashaDates.nowMinutes())} '
                              'local time, Android API level ${status.sdkInt}. Reminders are '
                              'built from this local clock.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.title,
    required this.ok,
    required this.detail,
    this.actionLabel,
    this.onAction,
    this.okWhenFalseOnly = false,
  });

  final String title;
  final bool ok;
  final String detail;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool okWhenFalseOnly;

  @override
  Widget build(BuildContext context) {
    final good = okWhenFalseOnly ? !ok : ok;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              good ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              size: 17,
              color: good ? AppColors.success : AppColors.warning,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.45,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(actionLabel!, style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

class _Limit extends StatelessWidget {
  const _Limit({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 5, right: 8),
            child: Icon(Icons.circle, size: 4, color: AppColors.lavender),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11,
                height: 1.55,
                color: AppColors.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
