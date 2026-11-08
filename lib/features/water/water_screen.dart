import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/water_schedule_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/user_settings.dart';
import '../../data/models/water_models.dart';
import '../../shared/widgets/akasha_text_field.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/water_drop.dart';
import '../dashboard/widgets/quick_water_sheet.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/date_strip.dart';
import '../../shared/widgets/app_dialog.dart';

/// The Water tab: today's progress, the timeline of real entries, and one-tap
/// access to reminders, history and statistics.
class WaterScreen extends ConsumerWidget {
  const WaterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waterAsync = ref.watch(todayWaterProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final remindersAsync = ref.watch(waterRemindersProvider);

    return GradientScaffold(
      body: waterAsync.when(
        loading: () => const Center(child: LoadingDots()),
        error: (_, __) => ErrorStateView(
          onRetry: () => ref.invalidate(todayWaterProvider),
        ),
        data: (summary) {
          final settings = settingsAsync.valueOrNull;
          if (settings == null) return const Center(child: LoadingDots());
          final reminders = remindersAsync.valueOrNull ?? const <WaterReminder>[];
          return _WaterBody(
            summary: summary,
            settings: settings,
            reminders: reminders,
          );
        },
      ),
    );
  }
}

class _WaterBody extends ConsumerWidget {
  const _WaterBody({
    required this.summary,
    required this.settings,
    required this.reminders,
  });

  final DailyWaterSummary summary;
  final UserSettings settings;
  final List<WaterReminder> reminders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = WaterScheduleEngine.nextSlot(
      reminders.where((r) => r.enabled).map((r) => ScheduleSlot(
            minuteOfDay: r.minuteOfDay,
            label: r.timeLabel,
          )).toList(),
      DateTime.now(),
    );
    final progress = settings.waterTargetMl == 0
        ? 0.0
        : summary.totalMl / settings.waterTargetMl;

    return RefreshIndicator(
      color: AppColors.primaryPink,
      backgroundColor: AppColors.white,
      onRefresh: () async {
        ref.invalidate(todayWaterProvider);
        ref.invalidate(waterRemindersProvider);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          const AkashaHeader(
            title: 'Water',
            subtitle: 'Your hydration, honestly tracked',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                FadeSlideIn(
                  child: SoftCard(
                    accent: AppColors.skyBlue,
                    padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              height: 210,
                              child: Align(
                                alignment: Alignment.center,
                                child: _BigWaterRing(
                                  progress: progress,
                                  total: summary.totalMl,
                                  target: settings.waterTargetMl,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _Metric(
                              value: '${summary.glassCount}',
                              label: 'glasses',
                            ),
                            _divider(),
                            _Metric(
                              value: '${summary.remainingMl}',
                              label: 'ml to go',
                            ),
                            _divider(),
                            _Metric(
                              value: '${(progress * 100).clamp(0, 999).round()}%',
                              label: 'of goal',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => showQuickWaterSheet(context, ref),
                                icon: const Icon(Icons.add_rounded, size: 19),
                                label: const Text('Add water'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.info,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  minimumSize: const Size.fromHeight(48),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 100,
                              child: OutlinedButton(
                                onPressed: () async {
                                  final undo = summary.entries.isNotEmpty
                                      ? summary.entries.last
                                      : null;
                                  if (undo == null) return;
                                  await ref
                                      .read(waterRepositoryProvider)
                                      .deleteLog(undo.id);
                                  ref.invalidate(todayWaterProvider);
                                  ref.invalidate(dataRevisionProvider);
                                  if (context.mounted) {
                                    showAkashaToast(
                                      context,
                                      'Removed the last entry. No worries.',
                                      icon: Icons.undo_rounded,
                                      color: AppColors.warning,
                                    );
                                  }
                                },
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                                child: const Text('Undo', style: TextStyle(fontSize: 13)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _GentleLine(progress: progress),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Next reminder + reminder manager
                FadeSlideIn(
                  delay: const Duration(milliseconds: 80),
                  child: SoftCard(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Column(
                      children: [
                        SectionTile(
                          icon: Icons.alarm_rounded,
                          title: next == null
                              ? 'No reminders set'
                              : 'Next reminder · ${next.label}',
                          subtitle: settings.waterRemindersPaused
                              ? 'Reminders are paused right now'
                              : '${reminders.where((r) => r.enabled).length} gentle reminders a day',
                          iconColor: AppColors.info,
                          onTap: () => context.push(Routes.waterReminders),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        SectionTile(
                          icon: Icons.show_chart_rounded,
                          title: 'History & statistics',
                          subtitle: 'Weekly and monthly patterns',
                          iconColor: AppColors.purple,
                          onTap: () => context.push(Routes.waterStats),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        SectionTile(
                          icon: Icons.toc_rounded,
                          title: 'Daily log',
                          subtitle: 'Every glass, with times',
                          iconColor: AppColors.rose,
                          onTap: () => context.push(Routes.waterHistory),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 140),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: const SectionHeader(
                      title: 'Today\'s timeline',
                      icon: Icons.timeline_rounded,
                    ),
                  ),
                ),
                if (summary.entries.isEmpty)
                  const EmptyState(
                    icon: Icons.water_drop_outlined,
                    title: 'No water logged yet',
                    message: 'Your first glass of the day is a lovely place to start.',
                    compact: true,
                  )
                else
                  ...summary.entries.reversed.map((log) => _LogTile(log: log)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        height: 26,
        width: 1,
        color: AppColors.hairline,
      );
}

class _BigWaterRing extends StatelessWidget {
  const _BigWaterRing({
    required this.progress,
    required this.total,
    required this.target,
  });

  final double progress;
  final int total;
  final int target;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 196,
          height: 196,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.softBlue.withValues(alpha: .9),
                AppColors.softBlue.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: ProgressRing(
            progress: progress,
            size: 196,
            strokeWidth: 16,
            waterLevel: progress.clamp(0.0, 1.0),
            gradient: AppColors.waterFill,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$total',
                      style: const TextStyle(
                        fontSize: 36,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.6,
                        color: AppColors.darkText,
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 5, left: 2),
                      child: Text(
                        'ml',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  'of $target ml',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: AppColors.secondaryText,
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

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: AppColors.darkText,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: AppColors.secondaryText,
          ),
        ),
      ],
    );
  }
}

/// A kind sentence instead of a score. Never shaming.
class _GentleLine extends StatelessWidget {
  const _GentleLine({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final text = progress >= 1
        ? 'You reached your goal today. Your body noticed.'
        : progress >= .6
            ? 'You\'re making progress, Akasha!'
            : progress > 0
                ? 'Every little step counts.'
                : 'Whenever you are ready, start with one small glass.';
    return Row(
      children: [
        const Icon(Icons.favorite_rounded, size: 12, color: AppColors.rose),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.4,
              fontStyle: FontStyle.italic,
              color: AppColors.secondaryText,
            ),
          ),
        ),
      ],
    );
  }
}

class _LogTile extends ConsumerWidget {
  const _LogTile({required this.log});

  final WaterLog log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.water_drop_rounded, size: 16, color: AppColors.skyBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${log.amountMl} ml',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkText,
                    ),
                  ),
                  Text(
                    '${DateFormat('h:mm a').format(log.loggedAt)} · ${_sourceLabel(log.source)}',
                    style: const TextStyle(fontSize: 10.5, color: AppColors.secondaryText),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz_rounded,
                  size: 18, color: AppColors.secondaryText),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR()),
              onSelected: (value) async {
                if (value == 'delete') {
                  final ok = await showAkashaConfirm(
                    context,
                    title: 'Remove this entry?',
                    message: 'This only deletes this one glass from your log.',
                    confirmLabel: 'Remove',
                    destructive: true,
                  );
                    if (!ok) return;
                    await ref.read(waterRepositoryProvider).deleteLog(log.id);
                    ref.invalidate(todayWaterProvider);
                    ref.invalidate(dataRevisionProvider);
                } else if (value == 'edit') {
                  final controller =
                      TextEditingController(text: log.amountMl.toString());
                  final newValue = await showDialog<int>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Correct the amount'),
                      content: AkashaTextField(
                        controller: controller,
                        hint: 'Amount in ml',
                        keyboardType: TextInputType.number,
                        autofocus: true,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            final parsed = int.tryParse(controller.text.trim());
                            if (parsed != null && parsed > 0) {
                              Navigator.pop(context, parsed);
                            }
                          },
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  );
                  if (newValue != null) {
                    await ref
                        .read(waterRepositoryProvider)
                        .updateLogAmount(log.id, newValue);
                    ref.invalidate(todayWaterProvider);
                    ref.invalidate(dataRevisionProvider);
                  }
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'edit', child: Text('Correct amount')),
                PopupMenuItem(value: 'delete', child: Text('Remove entry')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _sourceLabel(WaterLogSource source) => switch (source) {
        WaterLogSource.manual => 'added by you',
        WaterLogSource.notification => 'from a reminder',
        WaterLogSource.snooze => 'after snooze',
        WaterLogSource.quickAdd => 'quick add',
        WaterLogSource.undoRestore => 'restored',
      };
}

/// Shared helper for the "date pill" pattern used on history/statistics pages.
Widget buildDatePill(BuildContext context, DateTime date, ValueChanged<DateTime> onPick) {
  return Align(
    alignment: Alignment.centerRight,
    child: DatePill(date: date, onPick: onPick),
  );
}

/// Formats a minute count as a friendly label; kept here for reuse.
String minuteLabel(int minute) => AkashaDates.minutesToLabel(minute);
