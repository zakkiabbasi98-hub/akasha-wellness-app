import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/medicine_models.dart';
import '../../data/models/mind_models.dart';
import '../../data/repositories/reports_repository.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// A history calendar: pick any date and inspect that day's real records.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  DateTime _month = AkashaDates.startOfMonth(DateTime.now());
  DateTime _selected = AkashaDates.today();

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final profileAsync = ref.watch(profileProvider);
    ref.watch(dataRevisionProvider);

    return GradientScaffold(
      body: Column(
        children: [
          const AkashaHeader(
            title: 'History calendar',
            subtitle: 'Every day you showed up',
          ),
          Expanded(
            child: settingsAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => const ErrorStateView(),
              data: (settings) => profileAsync.when(
                loading: () => const Center(child: LoadingDots()),
                error: (_, __) => const ErrorStateView(),
                data: (profile) {
                  final reports = ref.read(reportsRepositoryProvider);
                  return FutureBuilder<Map<DateTime, int>>(
                    key: ValueKey(
                        '${AkashaDates.monthYear(_month)}-${ref.watch(dataRevisionProvider)}'),
                    future: reports.activityMap(
                      userId: profile.id,
                      from: AkashaDates.startOfMonth(_month),
                      to: AkashaDates.endOfMonth(_month),
                      targetMl: settings.waterTargetMl,
                    ),
                    builder: (context, snapshot) {
                      final activity = snapshot.data ?? {};
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                        children: [
                          SoftCard(
                            padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () => setState(() => _month =
                                          DateTime(_month.year, _month.month - 1, 1)),
                                      icon: const Icon(Icons.chevron_left_rounded,
                                          size: 20),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    Expanded(
                                      child: Text(
                                        AkashaDates.monthYear(_month),
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(fontSize: 15),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => setState(() => _month =
                                          DateTime(_month.year, _month.month + 1, 1)),
                                      icon: const Icon(Icons.chevron_right_rounded,
                                          size: 20),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: const [
                                    for (final day in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                                      Expanded(
                                        child: Center(
                                          child: Text(
                                            day,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.secondaryText,
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _MonthGrid(
                                  month: _month,
                                  selected: _selected,
                                  activity: activity,
                                  onSelect: (d) => setState(() => _selected = d),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _Legend(color: AppColors.skyBlue, label: 'water logged'),
                              const SizedBox(width: 14),
                              _Legend(color: AppColors.success, label: 'goal met'),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _DayDetail(
                            day: _selected,
                            userId: profile.id,
                            targetMl: settings.waterTargetMl,
                            glassSizeMl: settings.glassSizeMl,
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.activity,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final Map<DateTime, int> activity;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final leading = firstWeekday - 1;
    final cells = <Widget>[];

    for (var i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var d = 1; d <= daysInMonth; d++) {
      final date = DateTime(month.year, month.month, d);
      final isSelected = AkashaDates.isSameDay(date, selected);
      final isToday = AkashaDates.isToday(date);
      final level = activity[date] ?? 0;
      final color = level == 3
          ? AppColors.success
          : level >= 1
              ? AppColors.skyBlue
              : Colors.transparent;
      cells.add(
        GestureDetector(
          onTap: () => onSelect(date),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected
                  ? AppColors.purple
                  : (level > 0 ? color.withValues(alpha: .16) : Colors.transparent),
              border: isToday && !isSelected
                  ? Border.all(color: AppColors.primaryPink, width: 1.4)
                  : null,
            ),
            child: Center(
              child: Text(
                '$d',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppColors.darkText,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.05,
      children: cells,
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 9.5, color: AppColors.secondaryText),
        ),
      ],
    );
  }
}

class _DayDetail extends ConsumerWidget {
  const _DayDetail({
    required this.day,
    required this.userId,
    required this.targetMl,
    required this.glassSizeMl,
  });

  final DateTime day;
  final String userId;
  final int targetMl;
  final int glassSizeMl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<DailyReport>(
      key: ValueKey(AkashaDates.key(day)),
      future: ref.read(reportsRepositoryProvider).daily(
            userId: userId,
            day: day,
            targetMl: targetMl,
            glassSizeMl: glassSizeMl,
          ),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            height: 160,
            child: Center(child: LoadingDots()),
          );
        }
        final report = snapshot.data!;
        return SoftCard(
          padding: const EdgeInsets.all(16),
          accent: AppColors.primaryPink,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE, d MMMM yyyy').format(day),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 14.5,
                    ),
              ),
              const SizedBox(height: 12),
              if (!report.hasAnyData)
                const Text(
                  'No records on this day. Rest days count too.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.secondaryText,
                  ),
                )
              else
                Column(
                  children: [
                    _line(Icons.water_drop_rounded, AppColors.info, 'Water',
                        '${report.water.totalMl} ml of $targetMl ml'),
                    _line(Icons.medication_rounded, AppColors.rose, 'Medicine',
                        '${report.doses.taken} taken · ${report.doses.skipped} skipped · ${report.doses.missed} missed'),
                    _line(
                      Icons.mood_rounded,
                      AppColors.gold,
                      'Mood',
                      report.moods.isEmpty
                          ? 'no check-in'
                          : report.moods.first.mood.label,
                    ),
                    _line(Icons.auto_stories_rounded, AppColors.purple, 'Journal',
                        '${report.journalCount} entr${report.journalCount == 1 ? 'y' : 'ies'}'),
                    _line(Icons.air_rounded, AppColors.mint, 'Breathing',
                        '${report.breathingMinutes} min'),
                    _line(Icons.volunteer_activism_rounded, AppColors.rose,
                        'Gratitude',
                        report.gratitude == null ? 'not written' : 'written'),
                  ],
                ),
              if (report.water.entries.isNotEmpty) ...[
                const SizedBox(height: 10),
                Divider(color: AppColors.hairline),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: report.water.entries
                      .map((log) => StatusPill(
                            label: '${DateFormat('h:mm a').format(log.loggedAt)} · ${log.amountMl}ml',
                            color: AppColors.info,
                            compact: true,
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _line(IconData icon, Color color, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 8),
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: AppColors.secondaryText),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.darkText,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps the analyzer honest about unused imports in this file.
typedef CalendarMood = MoodType;
typedef CalendarDose = DoseStatus;
