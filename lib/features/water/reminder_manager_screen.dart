import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/water_schedule_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/models/user_settings.dart';
import '../../data/models/water_models.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/app_dialog.dart';

/// Manage the 16 default slots plus any custom ones.
class ReminderManagerScreen extends ConsumerWidget {
  const ReminderManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(waterRemindersProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;

    return GradientScaffold(
      body: Column(
        children: [
          AkashaHeader(
            title: 'Water reminders',
            subtitle: settings?.waterRemindersPaused == true
                ? 'Paused — your slots are saved'
                : '${remindersAsync.valueOrNull?.where((r) => r.enabled).length ?? 0} active reminders',
            trailing: HeaderAction(
              icon: Icons.add_rounded,
              onTap: () => context.push(Routes.waterReminderAdd),
            ),
          ),
          Expanded(
            child: remindersAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => ErrorStateView(
                onRetry: () => ref.invalidate(waterRemindersProvider),
              ),
              data: (reminders) {
                if (settings == null) return const Center(child: LoadingDots());
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  children: [
                    FadeSlideIn(
                      child: _PauseCard(
                        paused: settings.waterRemindersPaused,
                        count: reminders.where((r) => r.enabled).length,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FadeSlideIn(
                      delay: const Duration(milliseconds: 60),
                      child: _WindowCard(settings: settings),
                    ),
                    const SizedBox(height: 18),
                    SectionHeader(
                      title: 'Your slots',
                      actionLabel: 'Restore default',
                      onAction: () => _restoreDefault(context, ref),
                    ),
                    if (reminders.isEmpty)
                      const EmptyState(
                        icon: Icons.alarm_off_rounded,
                        title: 'No reminder slots',
                        message:
                            'Add a time, or restore the gentle default of 16 hourly reminders.',
                        compact: true,
                      )
                    else
                      ...reminders.map((reminder) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _SlotTile(reminder: reminder),
                          )),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => context.push(Routes.waterReminderAdd),
                        icon: const Icon(Icons.add_rounded, size: 17),
                        label: const Text('Add a custom reminder'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Reminders run from ${WaterScheduleEngine.describeWindow(settings.waterStartMin, settings.waterEndMin)} '
                      'every ${settings.waterIntervalMin} minutes. The end time is inclusive, '
                      'which is why 12:00 AM is included in the default schedule.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.55,
                            fontSize: 11.5,
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

  Future<void> _restoreDefault(BuildContext context, WidgetRef ref) async {
    final ok = await showAkashaConfirm(
      context,
      title: 'Restore the default schedule?',
      message:
          'This recreates the 16 hourly reminders from 09:00 AM to 12:00 AM. '
          'Custom slots you added are kept.',
      confirmLabel: 'Restore',
      icon: Icons.restart_alt_rounded,
    );
    if (!ok) return;
    final profile = await ref.read(profileProvider.future);
    final seed = ref.read(seedServiceProvider);
    final settings = await ref.read(settingsProvider.future);
    final count = await seed.restoreDefaultWaterSchedule(profile.id, settings);
    await _reschedule(ref);
    ref.invalidate(waterRemindersProvider);
    ref.invalidate(dataRevisionProvider);
    if (context.mounted) {
      showAkashaToast(
        context,
        '$count gentle reminders restored ♡',
        icon: Icons.alarm_on_rounded,
        color: AppColors.info,
      );
    }
  }

  static Future<void> _reschedule(WidgetRef ref) async {
    final notifications = ref.read(notificationServiceProvider);
    final exact = await notifications.canScheduleExactAlarms();
    await ref.read(reminderSchedulerProvider).rescheduleAll(exact: exact);
    ref.invalidate(schedulingStatusProvider);
    final count = await notifications.pendingCount();
    debugPendings(count);
  }
}

void debugPendings(int count) {
  debugPrint('AKASHA: $count notifications pending after reschedule');
}

class _PauseCard extends ConsumerWidget {
  const _PauseCard({required this.paused, required this.count});

  final bool paused;
  final int count;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SoftCard(
      accent: paused ? AppColors.peach : AppColors.lavender,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: paused ? AppColors.softPeach : AppColors.lightLavender,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              paused ? Icons.pause_circle_outline_rounded : Icons.notifications_active_rounded,
              size: 20,
              color: paused ? AppColors.warning : AppColors.purple,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paused ? 'Reminders paused' : 'Reminders active',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14),
                ),
                Text(
                  paused
                      ? 'Nothing will buzz until you resume.'
                      : '$count gentle nudges through your day.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: !paused,
            activeTrackColor: AppColors.primaryPink,
            onChanged: (value) async {
              await ref.read(settingsControllerProvider.notifier).updateAndReschedule(
                    (s) => s.copyWith(waterRemindersPaused: !value),
                  );
              ref.invalidate(waterRemindersProvider);
              if (value) {
                await _ReminderManagerRescheduler.run(ref);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Small helper so widget code can trigger a reschedule without ceremony.
abstract final class _ReminderManagerRescheduler {
  static Future<void> run(WidgetRef ref) async {
    final exact = await ref.read(notificationServiceProvider).canScheduleExactAlarms();
    await ref.read(reminderSchedulerProvider).rescheduleAll(exact: exact);
    ref.invalidate(schedulingStatusProvider);
  }
}

class _WindowCard extends ConsumerWidget {
  const _WindowCard({required this.settings});

  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = WaterScheduleEngine.estimateSlotsPerDay(
      startMinute: settings.waterStartMin,
      endMinute: settings.waterEndMin,
      intervalMinutes: settings.waterIntervalMin,
    );
    return SoftCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 16, color: AppColors.purple),
              const SizedBox(width: 7),
              Text('Reminder window', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text(
                '$slots / day',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TimeCell(
                  label: 'Starts',
                  value: WaterScheduleEngine.formatLabel(settings.waterStartMin),
                  onPick: (m) async {
                    await ref.read(settingsControllerProvider.notifier).updateAndReschedule(
                          (s) => s.copyWith(waterStartMin: m),
                        );
                    final profile = await ref.read(profileProvider.future);
                    await ref.read(waterRepositoryProvider).generateDefaultSchedule(
                          userId: profile.id,
                          startMinute: m,
                          endMinute: settings.waterEndMin,
                          intervalMinutes: settings.waterIntervalMin,
                          amountMl: settings.glassSizeMl,
                        );
                    await _ReminderManagerRescheduler.run(ref);
                    ref.invalidate(waterRemindersProvider);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeCell(
                  label: 'Ends (inclusive)',
                  value: WaterScheduleEngine.formatLabel(settings.waterEndMin),
                  onPick: (m) async {
                    await ref.read(settingsControllerProvider.notifier).updateAndReschedule(
                          (s) => s.copyWith(waterEndMin: m),
                        );
                    final profile = await ref.read(profileProvider.future);
                    await ref.read(waterRepositoryProvider).generateDefaultSchedule(
                          userId: profile.id,
                          startMinute: settings.waterStartMin,
                          endMinute: m,
                          intervalMinutes: settings.waterIntervalMin,
                          amountMl: settings.glassSizeMl,
                        );
                    await _ReminderManagerRescheduler.run(ref);
                    ref.invalidate(waterRemindersProvider);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Every', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [30, 45, 60, 90, 120, 180].map((m) {
              final selected = settings.waterIntervalMin == m;
              return GestureDetector(
                onTap: () async {
                  await ref.read(settingsControllerProvider.notifier).updateAndReschedule(
                        (s) => s.copyWith(waterIntervalMin: m),
                      );
                  final profile = await ref.read(profileProvider.future);
                  await ref.read(waterRepositoryProvider).generateDefaultSchedule(
                        userId: profile.id,
                        startMinute: settings.waterStartMin,
                        endMinute: settings.waterEndMin,
                        intervalMinutes: m,
                        amountMl: settings.glassSizeMl,
                      );
                  await _ReminderManagerRescheduler.run(ref);
                  ref.invalidate(waterRemindersProvider);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.purple : AppColors.cardMuted,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: selected ? AppColors.purple : AppColors.hairline,
                    ),
                  ),
                  child: Text(
                    m < 60 ? '$m min' : '${m ~/ 60} h',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? AppColors.white : AppColors.darkText,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text(
            'Changing these rebuilds the default slots. Custom times you added are '
            'kept, and duplicates are never created.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _TimeCell extends StatelessWidget {
  const _TimeCell({required this.label, required this.value, required this.onPick});

  final String label;
  final String value;
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
            final minutes = WaterScheduleEngine.parseTime(value) ?? 540;
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
            );
            if (picked != null) onPick(picked.hour * 60 + picked.minute);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  value,
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

class _SlotTile extends ConsumerWidget {
  const _SlotTile({required this.reminder});

  final WaterReminder reminder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 62,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: reminder.enabled ? AppColors.softBlue : AppColors.cardMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              reminder.timeLabel,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: reminder.enabled ? AppColors.info : AppColors.secondaryText,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reminder.isDefaultSlot ? 'Hourly reminder' : 'Custom reminder',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
                Text(
                  '${reminder.amountMl} ml suggested',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.secondaryText),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: reminder.enabled,
            activeTrackColor: AppColors.primaryPink,
            onChanged: (value) async {
              await ref.read(waterRepositoryProvider).setReminderEnabled(reminder.id, value);
              await _ReminderManagerRescheduler.run(ref);
              ref.invalidate(waterRemindersProvider);
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline_rounded,
                size: 17, color: AppColors.secondaryText),
            onPressed: () async {
              final ok = await showAkashaConfirm(
                context,
                title: 'Delete this reminder?',
                message:
                    '${reminder.timeLabel} will no longer remind you. You can add it back any time.',
                confirmLabel: 'Delete',
                destructive: true,
                icon: Icons.alarm_off_rounded,
              );
              if (!ok) return;
              await ref.read(waterRepositoryProvider).softDeleteReminder(reminder.id);
              await _ReminderManagerRescheduler.run(ref);
              ref.invalidate(waterRemindersProvider);
            },
          ),
        ],
      ),
    );
  }
}

/// Kept for future reuse by the settings screen.
String reminderSummary(UserSettings settings) =>
    '${AkashaConstantsSummary.slots(settings)} reminders a day';

abstract final class AkashaConstantsSummary {
  static int slots(UserSettings settings) => WaterScheduleEngine.estimateSlotsPerDay(
        startMinute: settings.waterStartMin,
        endMinute: settings.waterEndMin,
        intervalMinutes: settings.waterIntervalMin,
      );
}
