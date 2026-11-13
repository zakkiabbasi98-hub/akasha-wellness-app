import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';

/// A horizontal, scrollable week strip with today highlighted.
/// Used by dashboard, water history and reports.
class DateStrip extends StatelessWidget {
  const DateStrip({
    super.key,
    required this.selected,
    required this.onSelect,
    this.days = 14,
    this.anchor,
    this.markers = const {},
  });

  final DateTime selected;
  final ValueChanged<DateTime> onSelect;
  final int days;
  final DateTime? anchor;

  /// Dates (day-only) that should show a tiny dot beneath the number.
  final Set<DateTime> markers;

  @override
  Widget build(BuildContext context) {
    final base = AkashaDates.dayOnly(anchor ?? DateTime.now());
    final start = base.subtract(Duration(days: days - 1));
    return SizedBox(
      height: 74,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        reverse: true,
        itemCount: days,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final date = start.add(Duration(days: days - 1 - i));
          final isSelected = AkashaDates.isSameDay(date, selected);
          final isToday = AkashaDates.isSameDay(date, base);
          final hasMarker = markers.contains(date);
          return _DayChip(
            date: date,
            selected: isSelected,
            isToday: isToday,
            hasMarker: hasMarker,
            onTap: () => onSelect(date),
          );
        },
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.date,
    required this.selected,
    required this.isToday,
    required this.hasMarker,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool isToday;
  final bool hasMarker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 52,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: AppColors.pinkLavender,
                )
              : null,
          color: selected ? null : AppColors.white.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? Colors.transparent : AppColors.hairline,
          ),
          boxShadow: selected ? AppShadows.tinted(AppColors.primaryPink) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              DateFormat.E().format(date).substring(0, 2).toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: .6,
                color: selected ? Colors.white70 : AppColors.secondaryText,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 17,
                height: 1,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? AppColors.white : AppColors.darkText,
              ),
            ),
            const SizedBox(height: 5),
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hasMarker
                    ? (selected ? AppColors.white : AppColors.primaryPink)
                    : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill that shows the selected date and opens a date picker.
class DatePill extends StatelessWidget {
  const DatePill({super.key, required this.date, required this.onPick});

  final DateTime date;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2023),
          lastDate: DateTime.now().add(const Duration(days: 1)),
          builder: (context, child) => Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                    primary: AppColors.purple,
                    onPrimary: AppColors.white,
                    surface: AppColors.white,
                    onSurface: AppColors.darkText,
                  ),
            ),
            child: child!,
          ),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.white.withValues(alpha: .85),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_rounded,
                size: 13, color: AppColors.purple),
            const SizedBox(width: 6),
            Text(
              AkashaDates.isSameDay(date, DateTime.now())
                  ? 'Today'
                  : DateFormat('d MMM').format(date),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.darkText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
