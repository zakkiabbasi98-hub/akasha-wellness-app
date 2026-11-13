import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/medicine_models.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// The Medicine tab: today's doses grouped by time of day, with direct
/// taken / skipped / snoozed responses and the full medicine list.
class MedicineScreen extends ConsumerWidget {
  const MedicineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dosesAsync = ref.watch(todayDosesProvider);
    final medicinesAsync = ref.watch(medicinesProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;

    return GradientScaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 86),
        child: FloatingActionButton.extended(
          onPressed: () => context.push(Routes.medicineAdd),
          backgroundColor: AppColors.purple,
          foregroundColor: AppColors.white,
          elevation: 3,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text(
            'Add medicine',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          ),
        ),
      ),
      body: Column(
        children: [
          AkashaHeader(
            title: 'Medicine',
            subtitle: 'Your schedule, exactly as prescribed',
            trailing: HeaderAction(
              icon: Icons.history_rounded,
              onTap: () => context.push(Routes.medicineHistory),
            ),
          ),
          Expanded(
            child: dosesAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => ErrorStateView(
                onRetry: () => ref.invalidate(todayDosesProvider),
              ),
              data: (doses) {
                final medicines = medicinesAsync.valueOrNull ?? const <Medicine>[];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 140),
                  children: [
                    if (settings != null && settings.medicineRemindersPaused)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: const _PausedBanner(),
                      ),
                    FadeSlideIn(
                      child: _TodayHeader(doses: doses),
                    ),
                    const SizedBox(height: 14),
                    if (doses.isEmpty)
                      EmptyState(
                        icon: Icons.medication_outlined,
                        title: 'No doses scheduled today',
                        message: medicines.isEmpty
                            ? 'Add a medicine with your prescribed times, and it will '
                                'appear here every day.'
                            : 'None of your medicines are due today.',
                        actionLabel: 'Add a medicine',
                        onAction: () => context.push(Routes.medicineAdd),
                      )
                    else
                      ..._buildGroups(context, ref, doses),
                    const SizedBox(height: 20),
                    SectionHeader(
                      title: 'My medicines',
                      actionLabel: 'History',
                      onAction: () => context.push(Routes.medicineHistory),
                    ),
                    if (medicines.isEmpty)
                      const EmptyState(
                        icon: Icons.inventory_2_outlined,
                        title: 'Nothing added yet',
                        message: 'You control every name, dose and time here.',
                        compact: true,
                      )
                    else
                      ...medicines.map((medicine) => Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: _MedicineTile(medicine: medicine),
                          )),
                    const SizedBox(height: 12),
                    Text(
                      'Akasha never suggests dosages or changes to your prescription, '
                      'and a dose is only ever marked as taken when you say so.',
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

  List<Widget> _buildGroups(BuildContext context, WidgetRef ref, List<DoseView> doses) {
    final groups = <String, List<DoseView>>{
      'Morning': [],
      'Afternoon': [],
      'Evening': [],
    };
    for (final dose in doses) {
      final minute = dose.log.scheduledMinute;
      if (minute < 12 * 60) {
        groups['Morning']!.add(dose);
      } else if (minute < 17 * 60) {
        groups['Afternoon']!.add(dose);
      } else {
        groups['Evening']!.add(dose);
      }
    }
    final widgets = <Widget>[];
    groups.forEach((label, list) {
      if (list.isEmpty) return;
      list.sort((a, b) => a.log.scheduledMinute.compareTo(b.log.scheduledMinute));
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 8),
          child: Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .3,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 1, color: AppColors.hairline)),
            ],
          ),
        ),
      );
      for (final dose in list) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _DoseCard(dose: dose),
          ),
        );
      }
      widgets.add(const SizedBox(height: 6));
    });
    return widgets;
  }
}

class _PausedBanner extends ConsumerWidget {
  const _PausedBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SoftCard(
      accent: AppColors.peach,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.pause_circle_outline_rounded,
              size: 18, color: AppColors.warning),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'Medicine reminders are paused. Your schedule is still saved.',
              style: TextStyle(fontSize: 11.5, height: 1.4, color: AppColors.warmBrown),
            ),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(settingsControllerProvider.notifier).updateAndReschedule(
                    (s) => s.copyWith(medicineRemindersPaused: false),
                  );
              ref.invalidate(medicinesProvider);
            },
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 30),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Resume', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _TodayHeader extends StatelessWidget {
  const _TodayHeader({required this.doses});

  final List<DoseView> doses;

  @override
  Widget build(BuildContext context) {
    final taken = doses.where((d) => d.log.status == DoseStatus.taken).length;
    final missed = doses.where((d) => d.log.status == DoseStatus.missed).length;
    final pending = doses.where((d) =>
        d.log.status == DoseStatus.scheduled || d.log.status == DoseStatus.snoozed).length;
    final progress = doses.isEmpty ? 0.0 : taken / doses.length;

    return SoftCard(
      accent: AppColors.primaryPink,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                AkashaDates.isToday(DateTime.now())
                    ? 'Today'
                    : AkashaDates.prettyDate(DateTime.now()),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15),
              ),
              const Spacer(),
              Text(
                '$taken / ${doses.length} taken',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.hairline,
              valueColor: const AlwaysStoppedAnimation(AppColors.roseDeep),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              StatusPill(
                label: '$pending upcoming',
                color: AppColors.info,
                icon: Icons.schedule_rounded,
                compact: true,
              ),
              if (missed > 0)
                StatusPill(
                  label: '$missed missed',
                  color: AppColors.danger,
                  icon: Icons.info_outline_rounded,
                  compact: true,
                ),
              if (doses.isNotEmpty && taken == doses.length)
                const StatusPill(
                  label: 'All done today',
                  color: AppColors.success,
                  icon: Icons.check_circle_rounded,
                  compact: true,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DoseCard extends ConsumerWidget {
  const _DoseCard({required this.dose});

  final DoseView dose;

  Color get _statusColor => switch (dose.log.status) {
        DoseStatus.taken => AppColors.success,
        DoseStatus.skipped => AppColors.warning,
        DoseStatus.missed => AppColors.danger,
        DoseStatus.snoozed => AppColors.info,
        DoseStatus.scheduled => AppColors.secondaryText,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = dose.log.status;
    final answered = dose.log.isAnswered;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    _statusColor.withValues(alpha: .13),
                    AppColors.white,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  status == DoseStatus.taken
                      ? Icons.check_rounded
                      : status == DoseStatus.missed
                          ? Icons.error_outline_rounded
                          : Icons.medication_rounded,
                  size: 19,
                  color: _statusColor,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dose.medicine.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.darkText,
                      ),
                    ),
                    Text(
                      [
                        AkashaDates.minutesToLabel(dose.log.scheduledMinute),
                        if (dose.medicine.dosage?.isNotEmpty == true) dose.medicine.dosage!,
                        if (dose.medicine.withFood?.isNotEmpty == true)
                          dose.medicine.withFood!,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(label: status.label, color: _statusColor, compact: true),
            ],
          ),
          if (!answered) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    label: 'I took it',
                    icon: Icons.check_rounded,
                    color: AppColors.success,
                    filled: true,
                    onTap: () => _respond(ref, context, DoseStatus.taken),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _ActionButton(
                    label: 'Skip',
                    icon: Icons.close_rounded,
                    color: AppColors.secondaryText,
                    onTap: () => _respond(ref, context, DoseStatus.skipped),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: _ActionButton(
                    label: 'Later',
                    icon: Icons.schedule_rounded,
                    color: AppColors.info,
                    onTap: () => _respond(ref, context, DoseStatus.snoozed),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _respond(WidgetRef ref, BuildContext context, DoseStatus status) async {
    final repo = ref.read(medicineRepositoryProvider);
    if (status == DoseStatus.snoozed) {
      final settings = await ref.read(settingsProvider.future);
      final when = DateTime.now().add(Duration(minutes: settings.snoozeMinutes));
      await repo.recordResponse(
        logId: dose.log.id,
        status: DoseStatus.snoozed,
        snoozedUntil: when,
      );
      await ref.read(notificationServiceProvider).scheduleSnooze(
            snoozeId: 'medsnooze-${dose.log.id}',
            amountMl: 0,
            when: when,
            originalMinute: dose.log.scheduledMinute,
            isMedicine: true,
            refId: dose.log.id,
          );
    } else {
      await repo.recordResponse(logId: dose.log.id, status: status);
    }
    ref.invalidate(todayDosesProvider);
    ref.invalidate(dataRevisionProvider);
    if (context.mounted) {
      final messages = {
        DoseStatus.taken: 'Marked as taken ✓',
        DoseStatus.skipped: 'Marked as skipped. No judgement here.',
        DoseStatus.snoozed: 'I will remind you again soon.',
      };
      showAkashaToast(
        context,
        messages[status] ?? 'Updated',
        icon: status == DoseStatus.taken
            ? Icons.check_circle_rounded
            : Icons.info_outline_rounded,
        color: status == DoseStatus.taken ? AppColors.success : AppColors.info,
      );
    }
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: filled ? color.withValues(alpha: .13) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: .35)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MedicineTile extends ConsumerWidget {
  const _MedicineTile({required this.medicine});

  final Medicine medicine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final times = medicine.reminderMinutes
        .map(AkashaDates.minutesToLabel)
        .join(' · ');
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: SectionTile(
        icon: Icons.medication_liquid_rounded,
        title: medicine.name,
        subtitle: times.isEmpty
            ? 'No reminder times'
            : '$times${medicine.enabled ? '' : ' · paused'}',
        iconColor: AppColors.rose,
        trailing: Switch.adaptive(
          value: medicine.enabled,
          activeTrackColor: AppColors.primaryPink,
          onChanged: (value) async {
            try {
              await ref
                  .read(medicineRepositoryProvider)
                  .setEnabled(medicine.id, value);
              final exact = await ref
                  .read(notificationServiceProvider)
                  .canScheduleExactAlarms();
              await ref
                  .read(reminderSchedulerProvider)
                  .rescheduleAll(exact: exact);
              ref.invalidate(medicinesProvider);
              ref.invalidate(todayDosesProvider);
              ref.invalidate(schedulingStatusProvider);
            } catch (_) {
              // A failed toggle leaves the switch to re-render from the
              // database on the next read, so the UI cannot claim a state that
              // was never saved.
              if (context.mounted) {
                showAkashaToast(
                  context,
                  'Could not update this medicine. Nothing was changed.',
                  icon: Icons.error_outline_rounded,
                  color: AppColors.warning,
                );
              }
            }
          },
        ),
        onTap: () => context.push(Routes.medicineAdd, extra: MedicineArg(medicine)),
      ),
    );
  }
}
