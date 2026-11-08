import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/water_models.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';
import 'widgets/weekly_bar_chart.dart';

/// Water statistics for the last 7 days / 30 days, built only from stored logs.
class WaterStatsScreen extends ConsumerStatefulWidget {
  const WaterStatsScreen({super.key});

  @override
  ConsumerState<WaterStatsScreen> createState() => _WaterStatsScreenState();
}

class _WaterStatsScreenState extends ConsumerState<WaterStatsScreen> {
  int _rangeDays = 7;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final profileAsync = ref.watch(profileProvider);
    ref.watch(dataRevisionProvider);

    return GradientScaffold(
      body: Column(
        children: [
          const AkashaHeader(title: 'Water statistics', subtitle: 'Your real patterns'),
          Expanded(
            child: settingsAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => const ErrorStateView(),
              data: (settings) => profileAsync.when(
                loading: () => const Center(child: LoadingDots()),
                error: (_, __) => const ErrorStateView(),
                data: (profile) {
                  final from = AkashaDates.today()
                      .subtract(Duration(days: _rangeDays - 1));
                  final to = AkashaDates.today();
                  return FutureBuilder<List<WaterTrendPoint>>(
                    future: ref.read(waterRepositoryProvider).trend(
                          profile.id,
                          from,
                          to,
                          targetMl: settings.waterTargetMl,
                        ),
                    builder: (context, snapshot) {
                      final points = snapshot.data ?? const <WaterTrendPoint>[];
                      final loading = !snapshot.hasData;
                      final total = points.fold<int>(0, (s, p) => s + p.totalMl);
                      final daysMet =
                          points.where((p) => p.totalMl >= p.targetMl).length;
                      final average = points.isEmpty ? 0 : total ~/ points.length;
                      final best = points.isEmpty
                          ? 0
                          : points.map((p) => p.totalMl).reduce((a, b) => a > b ? a : b);

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
                        children: [
                          Row(
                            children: [
                              _RangeChip(
                                label: '7 days',
                                selected: _rangeDays == 7,
                                onTap: () => setState(() => _rangeDays = 7),
                              ),
                              const SizedBox(width: 8),
                              _RangeChip(
                                label: '30 days',
                                selected: _rangeDays == 30,
                                onTap: () => setState(() => _rangeDays = 30),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          if (loading)
                            const SizedBox(
                              height: 240,
                              child: Center(child: LoadingDots()),
                            )
                          else
                            SoftCard(
                              padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
                              accent: AppColors.skyBlue,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Text(
                                      _rangeDays == 7 ? 'This week' : 'This month',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  WeeklyWaterChart(
                                    points: points,
                                    targetMl: settings.waterTargetMl,
                                    height: 190,
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  value: '${(total / 1000).toStringAsFixed(2)} L',
                                  label: 'total',
                                  color: AppColors.info,
                                  icon: Icons.water_drop_rounded,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatCard(
                                  value: '${(average / 1000).toStringAsFixed(2)} L',
                                  label: 'daily average',
                                  color: AppColors.purple,
                                  icon: Icons.show_chart_rounded,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  value: '$daysMet/${points.length}',
                                  label: 'goals met',
                                  color: AppColors.success,
                                  icon: Icons.check_circle_outline_rounded,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _StatCard(
                                  value: '${(best / 1000).toStringAsFixed(2)} L',
                                  label: 'best day',
                                  color: AppColors.gold,
                                  icon: Icons.emoji_events_outlined,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          const SectionHeader(title: 'Day by day', icon: Icons.calendar_view_day_rounded),
                          ...points.reversed.map((p) => Padding(
                                padding: const EdgeInsets.only(bottom: 7),
                                child: SoftCard(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 74,
                                        child: Text(
                                          AkashaDates.isToday(p.date)
                                              ? 'Today'
                                              : DateFormat('EEE d MMM').format(p.date),
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.darkText,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(999),
                                          child: LinearProgressIndicator(
                                            value: p.ratio.clamp(0.0, 1.0),
                                            minHeight: 7,
                                            backgroundColor: AppColors.hairline,
                                            valueColor: const AlwaysStoppedAnimation(
                                              AppColors.skyBlue,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      SizedBox(
                                        width: 58,
                                        child: Text(
                                          '${p.totalMl} ml',
                                          textAlign: TextAlign.right,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.secondaryText,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                          const SizedBox(height: 14),
                          Text(
                            'Averages and totals are computed from the glasses you '
                            'logged. Missing days are not counted as zero against you — '
                            'they simply have no record.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontSize: 11.5,
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
          ),
        ],
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
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
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
  });

  final String value;
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Row(
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
