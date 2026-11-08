import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/user_settings.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// Notification behaviour, quiet hours, and the encouragement schedule.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);

    return GradientScaffold(
      body: Column(
        children: [
          const AkashaHeader(
            title: 'Notifications',
            subtitle: 'Calm by default',
          ),
          Expanded(
            child: settingsAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => const ErrorStateView(),
              data: (settings) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                children: [
                  SoftCard(
                    child: Column(
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: settings.soundEnabled,
                          activeTrackColor: AppColors.primaryPink,
                          onChanged: (v) => ref
                              .read(settingsControllerProvider.notifier)
                              .updateAndReschedule((s) => s.copyWith(soundEnabled: v)),
                          title: const Text('Sounds',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: const Text(
                            'Uses your device notification sound',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                        const Divider(height: 1),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: settings.vibrationEnabled,
                          activeTrackColor: AppColors.primaryPink,
                          onChanged: (v) => ref
                              .read(settingsControllerProvider.notifier)
                              .updateAndReschedule(
                                  (s) => s.copyWith(vibrationEnabled: v)),
                          title: const Text('Vibration',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: const Text(
                            'Respects silent mode and Do Not Disturb — Android decides '
                            'whether a vibration is allowed.',
                            style: TextStyle(fontSize: 11, height: 1.4),
                          ),
                        ),
                        const Divider(height: 1),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: settings.alarmStyle,
                          activeTrackColor: AppColors.primaryPink,
                          onChanged: (v) => ref
                              .read(settingsControllerProvider.notifier)
                              .updateAndReschedule(
                                  (s) => s.copyWith(alarmStyle: v)),
                          title: const Text('Alarm-style reminder',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: const Text(
                            'Asks Android to show the reminder over the lock screen where '
                            'the OS allows it. Declining simply falls back to a heads-up '
                            'notification.',
                            style: TextStyle(fontSize: 11, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionHeader(
                      title: 'Quiet hours', icon: Icons.bedtime_outlined),
                  SoftCard(
                    accent: AppColors.lavender,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: settings.quietModeEnabled,
                          activeTrackColor: AppColors.primaryPink,
                          onChanged: (v) => ref
                              .read(settingsControllerProvider.notifier)
                              .updateAndReschedule(
                                  (s) => s.copyWith(quietModeEnabled: v)),
                          title: const Text('Quiet at night',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${AkashaDates.minutesToLabel(settings.quietStartMin)} – '
                            '${AkashaDates.minutesToLabel(settings.quietEndMin)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                        if (settings.quietModeEnabled) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: _QuietTime(
                                  label: 'Sleep',
                                  minute: settings.quietStartMin,
                                  onPick: (m) => ref
                                      .read(settingsControllerProvider.notifier)
                                      .updateAndReschedule(
                                          (s) => s.copyWith(quietStartMin: m)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _QuietTime(
                                  label: 'Wake',
                                  minute: settings.quietEndMin,
                                  onPick: (m) => ref
                                      .read(settingsControllerProvider.notifier)
                                      .updateAndReschedule(
                                          (s) => s.copyWith(quietEndMin: m)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _QuietToggle(
                            label: 'Pause water reminders',
                            value: settings.quietPauseWater,
                            onChanged: (v) => ref
                                .read(settingsControllerProvider.notifier)
                                .updateAndReschedule(
                                    (s) => s.copyWith(quietPauseWater: v)),
                          ),
                          _QuietToggle(
                            label: 'Pause encouragement',
                            value: settings.quietPauseMotivation,
                            onChanged: (v) => ref
                                .read(settingsControllerProvider.notifier)
                                .updateAndReschedule(
                                    (s) => s.copyWith(quietPauseMotivation: v)),
                          ),
                          _QuietToggle(
                            label: 'Pause medicine reminders',
                            value: settings.quietPauseMedicine,
                            onChanged: (v) => ref
                                .read(settingsControllerProvider.notifier)
                                .updateAndReschedule(
                                    (s) => s.copyWith(quietPauseMedicine: v)),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.softPeach,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 14, color: AppColors.warning),
                                SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    'Medicine reminders are NOT silenced during quiet hours '
                                    'unless you switch this on yourself. You should never '
                                    'miss a prescribed dose because of an app setting.',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      height: 1.45,
                                      color: AppColors.warmBrown,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionHeader(
                      title: 'Encouragement', icon: Icons.auto_awesome_rounded),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${settings.motivationPerDay} messages a day',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Spread gently across your waking hours, never during quiet time.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 11),
                        ),
                        Slider(
                          value: settings.motivationPerDay.toDouble().clamp(0, 6),
                          min: 0,
                          max: 6,
                          divisions: 6,
                          activeColor: AppColors.primaryPink,
                          label: '${settings.motivationPerDay}',
                          onChanged: (v) async {
                            await ref
                                .read(settingsControllerProvider.notifier)
                                .update((s) => s.copyWith(
                                      motivationPerDay: v.round(),
                                      motivationEnabled: v.round() > 0,
                                    ));
                          },
                          onChangeEnd: (v) async {
                            final profile = await ref.read(profileProvider.future);
                            await ref
                                .read(motivationRepositoryProvider)
                                .regenerateSchedule(
                                  userId: profile.id,
                                  count: v.round(),
                                  wakeMinute: settings.quietEndMin,
                                  sleepMinute: settings.quietStartMin,
                                );
                            await ref
                                .read(settingsControllerProvider.notifier)
                                .updateAndReschedule((s) => s.copyWith());
                          },
                        ),
                        const SizedBox(height: 4),
                        Text('Categories',
                            style: Theme.of(context).textTheme.labelSmall),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            for (final category in _categories)
                              _CategoryChip(
                                label: category.$2,
                                selected: settings.motivationCategories.isEmpty ||
                                    settings.motivationCategories.contains(category.$1),
                                onTap: () async {
                                  final current = settings.motivationCategories.isEmpty
                                      ? _categories.map((c) => c.$1).toList()
                                      : [...settings.motivationCategories];
                                  if (current.contains(category.$1)) {
                                    if (current.length > 1) {
                                      current.remove(category.$1);
                                    }
                                  } else {
                                    current.add(category.$1);
                                  }
                                  await ref
                                      .read(settingsControllerProvider.notifier)
                                      .updateAndReschedule((s) => s.copyWith(
                                            motivationCategories: current,
                                          ));
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Leave all off to receive a balanced mix from every category.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Android controls whether an app may override Do Not Disturb, silent '
                    'mode or the lock screen. AKASHA follows those rules. If a reminder '
                    'does not reach you, check Settings → Permissions & diagnostics.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          height: 1.55,
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

  static const List<(String, String)> _categories = [
    ('confidence', 'Confidence'),
    ('self_love', 'Self-love'),
    ('overthinking', 'Overthinking'),
    ('productivity', 'Productivity'),
    ('calmness', 'Calmness'),
    ('gratitude', 'Gratitude'),
    ('courage', 'Courage'),
    ('growth', 'Personal growth'),
  ];
}

class _QuietToggle extends StatelessWidget {
  const _QuietToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: AppColors.darkText),
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: AppColors.primaryPink,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _QuietTime extends StatelessWidget {
  const _QuietTime({
    required this.label,
    required this.minute,
    required this.onPick,
  });

  final String label;
  final int minute;
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
              initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
            );
            if (picked != null) onPick(picked.hour * 60 + picked.minute);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                const Icon(Icons.bedtime_outlined, size: 14, color: AppColors.lavender),
                const SizedBox(width: 6),
                Text(
                  AkashaDates.minutesToLabel(minute),
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

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.softPink : AppColors.cardMuted,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primaryPink : AppColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.purple : AppColors.secondaryText,
          ),
        ),
      ),
    );
  }
}
