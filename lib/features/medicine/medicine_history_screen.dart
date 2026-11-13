import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/medicine_models.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// Complete dose history: scheduled, taken, skipped, snoozed, missed.
class MedicineHistoryScreen extends ConsumerStatefulWidget {
  const MedicineHistoryScreen({super.key});

  @override
  ConsumerState<MedicineHistoryScreen> createState() =>
      _MedicineHistoryScreenState();
}

class _MedicineHistoryScreenState extends ConsumerState<MedicineHistoryScreen> {
  int _rangeDays = 14;
  String? _statusFilter;

  Color _colorFor(DoseStatus status) => switch (status) {
        DoseStatus.taken => AppColors.success,
        DoseStatus.skipped => AppColors.warning,
        DoseStatus.missed => AppColors.danger,
        DoseStatus.snoozed => AppColors.info,
        DoseStatus.scheduled => AppColors.secondaryText,
      };

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    ref.watch(dataRevisionProvider);

    return GradientScaffold(
      body: Column(
        children: [
          const AkashaHeader(
            title: 'Medicine history',
            subtitle: 'An honest record, without judgement',
          ),
          Expanded(
            child: profileAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => const ErrorStateView(),
              data: (profile) {
                final to = AkashaDates.today();
                final from = to.subtract(Duration(days: _rangeDays - 1));
                return FutureBuilder<List<MedicineLog>>(
                  key: ValueKey('$_rangeDays-$_statusFilter'),
                  future: ref
                      .read(medicineRepositoryProvider)
                      .logsForRange(profile.id, from, to),
                  builder: (context, snapshot) {
                    final all = snapshot.data ?? const <MedicineLog>[];
                    final logs = _statusFilter == null
                        ? all
                        : all.where((l) => l.status.key == _statusFilter).toList();

                    final taken = all.where((l) => l.status == DoseStatus.taken).length;
                    final missed = all.where((l) => l.status == DoseStatus.missed).length;
                    final adherence =
                        all.isEmpty ? 0.0 : taken / all.length;

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
                      children: [
                        Row(
                          children: [
                            _chip('14 days', 14),
                            const SizedBox(width: 8),
                            _chip('30 days', 30),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SoftCard(
                          child: Row(
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${(adherence * 100).round()}%',
                                    style: const TextStyle(
                                      fontSize: 26,
                                      height: 1,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: -1,
                                      color: AppColors.darkText,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'answered',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 18),
                              Container(width: 1, height: 40, color: AppColors.hairline),
                              const SizedBox(width: 18),
                              Expanded(
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 6,
                                  children: [
                                    StatusPill(
                                      label: '$taken taken',
                                      color: AppColors.success,
                                      compact: true,
                                    ),
                                    StatusPill(
                                      label: '${all.length - taken - missed} other',
                                      color: AppColors.secondaryText,
                                      compact: true,
                                    ),
                                    if (missed > 0)
                                      StatusPill(
                                        label: '$missed missed',
                                        color: AppColors.danger,
                                        compact: true,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            _filterChip('All', null),
                            ...DoseStatus.values.map(
                              (s) => _filterChip(s.label, s.key, color: _colorFor(s)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (snapshot.connectionState == ConnectionState.waiting)
                          const SizedBox(
                            height: 200,
                            child: Center(child: LoadingDots()),
                          )
                        else if (logs.isEmpty)
                          EmptyState(
                            icon: Icons.history_toggle_off_rounded,
                            title: 'Nothing in this range',
                            message: _statusFilter == null
                                ? 'Dose records will appear here once you have medicines scheduled.'
                                : 'No doses with this status. That is okay.',
                            compact: true,
                          )
                        else
                          ..._groupByDay(logs).entries.map((entry) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(
                                      top: 8, bottom: 8, left: 2),
                                  child: Text(
                                    AkashaDates.prettyDate(
                                      AkashaDates.parseKey(entry.key),
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.secondaryText,
                                      letterSpacing: .2,
                                    ),
                                  ),
                                ),
                                ...entry.value.map((log) => Padding(
                                      padding: const EdgeInsets.only(bottom: 7),
                                      child: _LogRow(
                                        log: log,
                                        color: _colorFor(log.status),
                                        onTake: () async {
                                          await ref
                                              .read(medicineRepositoryProvider)
                                              .recordResponse(
                                                logId: log.id,
                                                status: DoseStatus.taken,
                                              );
                                          ref.invalidate(dataRevisionProvider);
                                          ref.invalidate(todayDosesProvider);
                                        },
                                      ),
                                    )),
                              ],
                            );
                          }),
                        const SizedBox(height: 16),
                        Text(
                          'A missed dose is not a failure. If you are unsure what to '
                          'do about a missed dose, check your prescription or ask your '
                          'pharmacist.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                height: 1.55,
                              ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Map<String, List<MedicineLog>> _groupByDay(List<MedicineLog> logs) {
    final grouped = <String, List<MedicineLog>>{};
    for (final log in logs) {
      grouped.putIfAbsent(log.dayKey, () => []).add(log);
    }
    return grouped;
  }

  Widget _chip(String label, int days) {
    final selected = _rangeDays == days;
    return GestureDetector(
      onTap: () => setState(() => _rangeDays = days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.purple : AppColors.white.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.purple : AppColors.hairline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.white : AppColors.darkText,
          ),
        ),
      ),
    );
  }

  Widget _filterChip(String label, String? status, {Color? color}) {
    final selected = _statusFilter == status;
    final tint = color ?? AppColors.purple;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? tint.withValues(alpha: .16)
              : AppColors.white.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? tint.withValues(alpha: .5) : AppColors.hairline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? tint : AppColors.secondaryText,
          ),
        ),
      ),
    );
  }
}

class _LogRow extends ConsumerWidget {
  const _LogRow({required this.log, required this.color, required this.onTake});

  final MedicineLog log;
  final Color color;
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(13, 10, 10, 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              log.status == DoseStatus.taken
                  ? Icons.check_rounded
                  : log.status == DoseStatus.missed
                      ? Icons.error_outline_rounded
                      : log.status == DoseStatus.skipped
                          ? Icons.remove_rounded
                          : Icons.schedule_rounded,
              size: 16,
              color: color,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AkashaDates.minutesToLabel(log.scheduledMinute),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
                Text(
                  log.respondedAt == null
                      ? 'No response recorded'
                      : 'Answered at ${DateFormat('h:mm a').format(log.respondedAt!)}',
                  style: const TextStyle(fontSize: 10.5, color: AppColors.secondaryText),
                ),
              ],
            ),
          ),
          if (log.status == DoseStatus.scheduled ||
              log.status == DoseStatus.snoozed ||
              log.status == DoseStatus.missed)
            TextButton(
              onPressed: onTake,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 30),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('Mark taken', style: TextStyle(fontSize: 11)),
            ),
          StatusPill(label: log.status.label, color: color, compact: true),
        ],
      ),
    );
  }
}
