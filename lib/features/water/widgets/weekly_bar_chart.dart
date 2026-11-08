import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/water_models.dart';

/// Water intake bar chart with a dashed goal line.
///
/// Built from real [WaterTrendPoint]s — never placeholder values. Used by the
/// water statistics screen, weekly report and monthly report.
class WeeklyWaterChart extends StatelessWidget {
  const WeeklyWaterChart({
    super.key,
    required this.points,
    required this.targetMl,
    this.height = 190,
    this.showEveryNthLabel,
  });

  final List<WaterTrendPoint> points;
  final int targetMl;
  final double height;
  final int? showEveryNthLabel;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text(
            'No records yet for this range',
            style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
          ),
        ),
      );
    }

    final maxValue = [
      targetMl.toDouble(),
      ...points.map((p) => p.totalMl.toDouble()),
      100,
    ].reduce((a, b) => a > b ? a : b);
    final maxY = (maxValue * 1.18).ceilToDouble();
    final step = showEveryNthLabel ?? (points.length > 14 ? 5 : 1);

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxY,
          minY: 0,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.darkText,
              tooltipRoundedRadius: 10,
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final point = points[group.x.toInt()];
                return BarTooltipItem(
                  '${DateFormat('d MMM').format(point.date)}\n${point.totalMl} ml',
                  const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                );
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: maxY / 4,
            getDrawingHorizontalLine: (value) => FlLine(
              color: AppColors.hairline,
              strokeWidth: 1,
              dashArray: [4, 6],
            ),
          ),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y: targetMl.toDouble(),
                color: AppColors.primaryPink.withValues(alpha: .65),
                strokeWidth: 1.4,
                dashArray: const [5, 5],
                label: HorizontalLineLabel(
                  show: true,
                  alignment: Alignment.topRight,
                  padding: const EdgeInsets.only(right: 2, bottom: 2),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryPink.withValues(alpha: .95),
                  ),
                  labelResolver: (_) => 'goal',
                ),
              ),
            ],
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 34,
                interval: maxY / 4,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const SizedBox.shrink();
                  return Text(
                    '${(value / 1000).toStringAsFixed(1)}L',
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.secondaryText,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= points.length) {
                    return const SizedBox.shrink();
                  }
                  // Always label the last (today) and respect the step.
                  final isLast = index == points.length - 1;
                  if (index % step != 0 && !isLast) {
                    return const SizedBox.shrink();
                  }
                  final date = points[index].date;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat('E').format(date).substring(0, 1),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                        color: isLast ? AppColors.purple : AppColors.secondaryText,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: points[i].totalMl.toDouble(),
                    width: points.length > 14 ? 6 : 16,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: points[i].totalMl >= targetMl
                          ? const [AppColors.skyBlue, AppColors.skyDeep]
                          : const [
                              AppColors.trackSoft,
                              AppColors.skyBlue,
                            ],
                    ),
                    backDrawRodData: BackgroundBarChartRodData(
                      show: true,
                      toY: maxY,
                      color: AppColors.cardMuted,
                    ),
                  ),
                ],
              ),
          ],
        ),
        duration: const Duration(milliseconds: 500),
      ),
    );
  }
}
