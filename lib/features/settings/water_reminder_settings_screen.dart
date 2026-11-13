import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/water_schedule_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/app_dialog.dart';

/// Full water-reminder configuration: window, interval, pause, restore.
class WaterReminderSettingsScreen extends ConsumerWidget {
  const WaterReminderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);

    return GradientScaffold(
      body: Column(
        children: [
          const AkashaHeader(
            title: 'Water reminders',
            subtitle: 'Your gentle schedule',
          ),
          Expanded(
            child: settingsAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => const ErrorStateView(),
              data: (settings) {
                final slots = WaterScheduleEngine.estimateSlotsPerDay(
                  startMinute: settings.waterStartMin,
                  endMinute: settings.waterEndMin,
                  intervalMinutes: settings.waterIntervalMin,
                );
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  children: [
                    SoftCard(
                      accent: AppColors.skyBlue,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.water_drop_rounded,
                                  size: 18, color: AppColors.info),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$slots reminders a day',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontSize: 15),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${WaterScheduleEngine.describeWindow(settings.waterStartMin, settings.waterEndMin)} '
                              '· every ${settings.waterIntervalMin} min',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: !settings.waterRemindersPaused,
                            activeTrackColor: AppColors.primaryPink,
                            onChanged: (value) async {
                              await ref
                                  .read(settingsControllerProvider.notifier)
                                  .updateAndReschedule(
                                    (s) => s.copyWith(waterRemindersPaused: !value),
                                  );
                              ref.invalidate(waterRemindersProvider);
                            },
                            title: const Text(
                              'Reminders active',
                              style: TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              settings.waterRemindersPaused
                                  ? 'Paused — your slots are safely stored'
                                  : 'You can pause any time without losing your slots',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Reminder window',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            'The end time is inclusive, so 12:00 AM can be a reminder.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontSize: 11),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _TimeRow(
                                  label: 'Start',
                                  value: settings.waterStartMin,
                                  onPick: (minute) async {
                                    await ref
                                        .read(settingsControllerProvider.notifier)
                                        .updateAndReschedule(
                                          (s) => s.copyWith(waterStartMin: minute),
                                        );
                                    await _regenerate(ref);
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _TimeRow(
                                  label: 'End',
                                  value: settings.waterEndMin,
                                  onPick: (minute) async {
                                    await ref
                                        .read(settingsControllerProvider.notifier)
                                        .updateAndReschedule(
                                          (s) => s.copyWith(waterEndMin: minute),
                                        );
                                    await _regenerate(ref);
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text('Interval', style: Theme.of(context).textTheme.labelSmall),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [30, 45, 60, 90, 120, 180].map((m) {
                              final selected = settings.waterIntervalMin == m;
                              return GestureDetector(
                                onTap: () async {
                                  await ref
                                      .read(settingsControllerProvider.notifier)
                                      .updateAndReschedule(
                                        (s) => s.copyWith(waterIntervalMin: m),
                                      );
                                  await _regenerate(ref);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 13, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.purple
                                        : AppColors.cardMuted,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.purple
                                          : AppColors.hairline,
                                    ),
                                  ),
                                  child: Text(
                                    m < 60 ? '$m min' : '${m ~/ 60} h',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? AppColors.white
                                          : AppColors.darkText,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SoftCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          SectionTile(
                            icon: Icons.tune_rounded,
                            title: 'Manage individual slots',
                            subtitle: 'Add, edit, delete or disable a single time',
                            iconColor: AppColors.info,
                            onTap: () => context.push(Routes.waterReminders),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          SectionTile(
                            icon: Icons.timer_outlined,
                            title: 'Snooze length',
                            subtitle: '${settings.snoozeMinutes} minutes',
                            iconColor: AppColors.purple,
                            onTap: () async {
                              final minutes = await _pickSnooze(context);
                              if (minutes == null) return;
                              await ref
                                  .read(settingsControllerProvider.notifier)
                                  .update((s) => s.copyWith(snoozeMinutes: minutes));
                            },
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          SectionTile(
                            icon: Icons.water_drop_outlined,
                            title: 'Daily goal',
                            subtitle: '${settings.waterTargetMl} ml',
                            iconColor: AppColors.skyBlue,
                            onTap: () async {
                              final target = await _pickTarget(context);
                              if (target == null) return;
                              await ref
                                  .read(settingsControllerProvider.notifier)
                                  .update((s) => s.copyWith(waterTargetMl: target));
                              ref.invalidate(todayWaterProvider);
                            },
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          SectionTile(
                            icon: Icons.restart_alt_rounded,
                            title: 'Restore default schedule',
                            subtitle: '09:00 AM → 12:00 AM, hourly (16 reminders)',
                            iconColor: AppColors.warning,
                            showChevron: true,
                            onTap: () async {
                              final ok = await showAkashaConfirm(
                                context,
                                title: 'Restore the default schedule?',
                                message:
                                    'This recreates the 16 hourly reminders from 09:00 AM '
                                    'to 12:00 AM. Custom slots you added are kept.',
                                confirmLabel: 'Restore',
                                icon: Icons.restart_alt_rounded,
                              );
                              if (!ok) return;
                              final profile =
                                  await ref.read(profileProvider.future);
                              final seed = ref.read(seedServiceProvider);
                              final count = await seed.restoreDefaultWaterSchedule(
                                profile.id,
                                settings,
                              );
                              await ref
                                  .read(settingsControllerProvider.notifier)
                                  .updateAndReschedule(
                                    (s) => s.copyWith(
                                      waterStartMin:
                                          AppConstants.defaultWaterStartMinute,
                                      waterEndMin: AppConstants.defaultWaterEndMinute,
                                      waterIntervalMin:
                                          AppConstants.defaultWaterIntervalMinutes,
                                    ),
                                  );
                              ref.invalidate(waterRemindersProvider);
                              if (context.mounted) {
                                showAkashaToast(
                                  context,
                                  '$count reminders restored ♡',
                                  icon: Icons.alarm_on_rounded,
                                  color: AppColors.info,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Reminders use your device\'s local time. If you travel or change '
                      'timezone, the schedule rebuilds automatically the next time you '
                      'open the app.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            height: 1.55,
                          ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> _regenerate(WidgetRef ref) async {
    final profile = await ref.read(profileProvider.future);
    final settings = await ref.read(settingsProvider.future);
    await ref.read(waterRepositoryProvider).generateDefaultSchedule(
          userId: profile.id,
          startMinute: settings.waterStartMin,
          endMinute: settings.waterEndMin,
          intervalMinutes: settings.waterIntervalMin,
          amountMl: settings.glassSizeMl,
        );
    ref.invalidate(waterRemindersProvider);
  }

  Future<int?> _pickSnooze(BuildContext context) async {
    return showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
        title: const Text('Snooze length'),
        children: [5, 10, 15, 20, 30, 45]
            .map((m) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, m),
                  child: Text('$m minutes'),
                ))
            .toList(),
      ),
    );
  }

  Future<int?> _pickTarget(BuildContext context) async {
    return showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
        title: const Text('Daily water goal'),
        children: [1200, 1500, 1800, 2000, 2200, 2500, 3000, 3500]
            .map((m) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, m),
                  child: Text('$m ml'),
                ))
            .toList(),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.label, required this.value, required this.onPick});

  final String label;
  final int value;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
            );
            if (picked != null) onPick(picked.hour * 60 + picked.minute);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.cardMuted,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time_rounded,
                    size: 14, color: AppColors.lavender),
                const SizedBox(width: 6),
                Text(
                  AkashaDates.minutesToLabel(value),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
