import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/medicine_models.dart';
import '../../data/models/mind_models.dart';
import '../../data/repositories/reports_repository.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/date_strip.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';
import '../dashboard/widgets/dashboard_cards.dart';
import '../water/widgets/weekly_bar_chart.dart';

/// Daily / weekly / monthly wellness report. All values come from the
/// database — nothing is mocked.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  int _tab = 0; // 0 = day, 1 = week, 2 = month
  DateTime _selected = AkashaDates.today();

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final profileAsync = ref.watch(profileProvider);
    ref.watch(dataRevisionProvider);

    return GradientScaffold(
      body: Column(
        children: [
          AkashaHeader(
            title: 'Wellness report',
            subtitle: switch (_tab) {
              0 => AkashaDates.prettyDate(_selected),
              1 => 'This week',
              _ => AkashaDates.monthYear(DateTime.now()),
            },
            trailing: HeaderAction(
              icon: Icons.calendar_month_rounded,
              onTap: () => context.push('${Routes.home}/calendar'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _Segmented(
              index: _tab,
              labels: const ['Day', 'Week', 'Month'],
              onChanged: (i) => setState(() => _tab = i),
            ),
          ),
          if (_tab == 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: DateStrip(
                selected: _selected,
                days: 21,
                onSelect: (d) => setState(() => _selected = d),
              ),
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
                  return FutureBuilder<Object>(
                    key: ValueKey('$_tab-${AkashaDates.key(_selected)}-${ref.watch(dataRevisionProvider)}'),
                    future: _tab == 0
                        ? reports.daily(
                            userId: profile.id,
                            day: _selected,
                            targetMl: settings.waterTargetMl,
                            glassSizeMl: settings.glassSizeMl,
                          )
                        : _tab == 1
                            ? reports.weekly(
                                userId: profile.id,
                                targetMl: settings.waterTargetMl,
                                glassSizeMl: settings.glassSizeMl,
                              )
                            : reports.monthly(
                                userId: profile.id,
                                targetMl: settings.waterTargetMl,
                                glassSizeMl: settings.glassSizeMl,
                              ),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: LoadingDots());
                      }
                      if (snapshot.hasError) {
                        return ErrorStateView(
                          onRetry: () => setState(() {}),
                        );
                      }
                      final data = snapshot.data!;
                      if (data is DailyReport) {
                        return _DailyReportView(report: data, settings: settings);
                      }
                      final range = data as RangeReport;
                      return _RangeReportView(report: range);
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

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.index,
    required this.labels,
    required this.onChanged,
  });

  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = i == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: selected
                      ? const LinearGradient(colors: AppColors.pinkLavender)
                      : null,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: selected
                      ? AppShadows.tinted(AppColors.primaryPink)
                      : null,
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.white : AppColors.secondaryText,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DailyReportView extends StatelessWidget {
  const _DailyReportView({required this.report, required this.settings});

  final DailyReport report;
  final dynamic settings;

  @override
  Widget build(BuildContext context) {
    final waterPercent = report.water.targetProgress.clamp(0.0, 1.0);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      children: [
        // Overall ring
        SoftCard(
          accent: AppColors.lavender,
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ProgressRing(
                    progress: report.wellnessPoints / 100,
                    size: 118,
                    strokeWidth: 11,
                    gradient: AppColors.pinkLavender,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${report.wellnessPoints}',
                          style: const TextStyle(
                            fontSize: 24,
                            height: 1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                            color: AppColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'care points',
                          style: TextStyle(
                            fontSize: 8.5,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          report.hasAnyData
                              ? 'Here is your day, gently.'
                              : 'A quiet day',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontSize: 15),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          report.hasAnyData
                              ? 'These points are not a grade. They are just a soft '
                                  'summary of how you looked after yourself.'
                              : 'No records for this day — and that is perfectly okay.',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(fontSize: 11.5, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Row2(
          left: _MetricTile(
            icon: Icons.water_drop_rounded,
            color: AppColors.info,
            title: 'Water',
            value: '${report.water.totalMl} ml',
            subtitle: '${(waterPercent * 100).round()}% of '
                '${report.water.targetMl} ml',
            progress: waterPercent,
          ),
          right: _MetricTile(
            icon: Icons.medication_rounded,
            color: AppColors.rose,
            title: 'Medicines',
            value: '${report.doses.taken}/${report.doses.total}',
            subtitle: report.doses.total == 0
                ? 'none scheduled'
                : '${report.doses.missed} missed · ${report.doses.skipped} skipped',
            progress: report.doses.total == 0
                ? 0
                : report.doses.taken / report.doses.total,
          ),
        ),
        const SizedBox(height: 10),
        _Row2(
          left: _MetricTile(
            icon: Icons.mood_rounded,
            color: AppColors.gold,
            title: 'Mood',
            value: report.moods.isEmpty ? '—' : report.moods.first.mood.label,
            subtitle: report.moods.isEmpty
                ? 'no check-in'
                : '${report.moods.length} check-in${report.moods.length == 1 ? '' : 's'}',
          ),
          right: _MetricTile(
            icon: Icons.auto_stories_rounded,
            color: AppColors.purple,
            title: 'Journal',
            value: '${report.journalCount}',
            subtitle: report.journalCount == 0 ? 'no entries' : 'entries written',
          ),
        ),
        const SizedBox(height: 10),
        _Row2(
          left: _MetricTile(
            icon: Icons.air_rounded,
            color: AppColors.mint,
            title: 'Breathing',
            value: '${report.breathingMinutes} min',
            subtitle: '${report.breathingSessions} session'
                '${report.breathingSessions == 1 ? '' : 's'}',
          ),
          right: _MetricTile(
            icon: Icons.volunteer_activism_rounded,
            color: AppColors.rose,
            title: 'Gratitude',
            value: report.gratitude == null ? '—' : '${report.gratitude!.items.length}',
            subtitle: report.gratitude == null ? 'not written yet' : 'things noticed',
          ),
        ),
        const SizedBox(height: 14),
        if (report.gratitude != null) ...[
          SoftCard(
            accent: AppColors.peach,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'What you were grateful for',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .3,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 8),
                ...report.gratitude!.items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        '♡ $item',
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.5,
                          color: AppColors.darkText,
                        ),
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          'A day with fewer records is not a day you failed. It is simply a day you '
          'were busy living.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                height: 1.55,
                fontStyle: FontStyle.italic,
              ),
        ),
      ],
    );
  }
}

class _RangeReportView extends StatelessWidget {
  const _RangeReportView({required this.report});

  final RangeReport report;

  @override
  Widget build(BuildContext context) {
    final doses = report.doses;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
      children: [
        SoftCard(
          accent: AppColors.skyBlue,
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Row(
                  children: [
                    Text(
                      'Hydration',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    Text(
                      '${report.daysTargetMet}/${report.waterTrend.length} days at goal',
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.info,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'Average ${(report.averageWaterMl / 1000).toStringAsFixed(2)} L '
                  'per day · ${(report.totalWaterMl / 1000).toStringAsFixed(1)} L total',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              WeeklyWaterChart(
                points: report.waterTrend,
                targetMl: report.targetMl,
                height: 180,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Row2(
          left: _MetricTile(
            icon: Icons.medication_rounded,
            color: AppColors.rose,
            title: 'Doses taken',
            value: '${doses.taken}',
            subtitle: '${doses.missed} missed · ${doses.skipped} skipped',
            progress: doses.total == 0 ? 0 : doses.taken / doses.total,
          ),
          right: _MetricTile(
            icon: Icons.auto_stories_rounded,
            color: AppColors.purple,
            title: 'Journal',
            value: '${report.journalCount}',
            subtitle: 'entries this period',
          ),
        ),
        const SizedBox(height: 10),
        _Row2(
          left: _MetricTile(
            icon: Icons.air_rounded,
            color: AppColors.mint,
            title: 'Breathing',
            value: '${report.breathingMinutes} min',
            subtitle: 'of calm',
          ),
          right: _MetricTile(
            icon: Icons.volunteer_activism_rounded,
            color: AppColors.rose,
            title: 'Gratitude',
            value: '${report.gratitudeCount}',
            subtitle: 'days recorded',
          ),
        ),
        const SizedBox(height: 14),
        if (report.moodCounts.isNotEmpty) ...[
          SoftCard(
            accent: AppColors.lavender,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Moods this period',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                ...(report.moodCounts.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value)))
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(moodIcon(e.key), size: 15, color: moodColor(e.key)),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 78,
                                child: Text(
                                  e.key.label,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.darkText,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(999),
                                  child: LinearProgressIndicator(
                                    value: e.value /
                                        report.moodCounts.values
                                            .reduce((a, b) => a + b),
                                    minHeight: 6,
                                    backgroundColor: AppColors.hairline,
                                    valueColor:
                                        AlwaysStoppedAnimation(moodColor(e.key)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${e.value}',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                        )),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Day by day',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 10),
              ...report.days.reversed.take(14).map((day) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 76,
                          child: Text(
                            AkashaDates.isToday(day.day)
                                ? 'Today'
                                : DateFormat('EEE d MMM').format(day.day),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.darkText,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Row(
                            children: [
                              _Dot(active: day.water.totalMl > 0, color: AppColors.info),
                              _Dot(
                                active: day.doses.total == 0 ||
                                    day.doses.taken == day.doses.total,
                                color: AppColors.rose,
                              ),
                              _Dot(active: day.moods.isNotEmpty, color: AppColors.gold),
                              _Dot(active: day.journalCount > 0, color: AppColors.purple),
                              _Dot(
                                active: day.breathingSessions > 0,
                                color: AppColors.mint,
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${day.wellnessPoints}',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 6),
              const Text(
                'Dots: water · medicine · mood · journal · breathing',
                style: TextStyle(fontSize: 9.5, color: AppColors.secondaryText),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active, required this.color});

  final bool active;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.only(right: 5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? color : AppColors.hairline,
      ),
    );
  }
}

class _Row2 extends StatelessWidget {
  const _Row2({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.subtitle,
    this.progress,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String subtitle;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .3,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 17,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: AppColors.darkText,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 2,
            style: const TextStyle(
              fontSize: 9.5,
              height: 1.35,
              color: AppColors.secondaryText,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: AppColors.hairline,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
