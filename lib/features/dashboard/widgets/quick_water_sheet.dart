import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/water_models.dart';
import '../../../shared/widgets/soft_card.dart';
import '../../../shared/widgets/states.dart';

/// The single place water gets logged by hand.
///
/// Bottom sheet with the three glass sizes, an arbitrary amount, and a "just
/// added" undo. Keeping this in one widget means the dashboard, the water tab
/// and the reminder screen all behave identically.
Future<void> showQuickWaterSheet(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    builder: (_) => const _QuickWaterSheet(),
  );
}

class _QuickWaterSheet extends ConsumerStatefulWidget {
  const _QuickWaterSheet();

  @override
  ConsumerState<_QuickWaterSheet> createState() => _QuickWaterSheetState();
}

class _QuickWaterSheetState extends ConsumerState<_QuickWaterSheet> {
  int? _customAmount;
  bool _saving = false;

  Future<void> _log(int amount, {String? glassLabel}) async {
    if (_saving) return;
    setState(() => _saving = true);
    final profile = await ref.read(profileProvider.future);
    try {
      await ref.read(waterRepositoryProvider).addLog(
            userId: profile.id,
            amountMl: amount,
            source: _customAmount == null
                ? WaterLogSource.quickAdd
                : WaterLogSource.manual,
            glassSize: glassLabel,
          );
      ref.invalidate(todayWaterProvider);
      ref.invalidate(todayReportProvider);
      ref.invalidate(dataRevisionProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      showAkashaToast(
        context,
        '$amount ml added. You are taking care of yourself ♡',
        icon: Icons.water_drop_rounded,
        color: AppColors.info,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAkashaToast(
        context,
        'Could not save that. Please try again.',
        icon: Icons.error_outline_rounded,
        color: AppColors.danger,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.valueOrNull;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add water',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap the size you just drank. Nothing here is judged later.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            if (settings != null)
              Row(
                children: [
                  Expanded(
                    child: _GlassOption(
                      label: 'Small',
                      amount: settings.smallGlassMl,
                      color: AppColors.skyBlue,
                      onTap: () => _log(settings.smallGlassMl, glassLabel: 'small'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _GlassOption(
                      label: 'Usual',
                      amount: settings.glassSizeMl,
                      color: AppColors.primaryPink,
                      highlighted: true,
                      onTap: () => _log(settings.glassSizeMl, glassLabel: 'medium'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _GlassOption(
                      label: 'Large',
                      amount: settings.largeGlassMl,
                      color: AppColors.lavender,
                      onTap: () => _log(settings.largeGlassMl, glassLabel: 'large'),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            SoftCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Something else?',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [100, 200, 300, 400, 500, 750]
                        .map((ml) => _AmountChip(
                              amount: ml,
                              selected: _customAmount == ml,
                              onTap: () => setState(() => _customAmount = ml),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _customAmount == null || _saving
                          ? null
                          : () => _log(_customAmount!),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.purple,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        _customAmount == null
                            ? 'Choose an amount'
                            : 'Add $_customAmount ml',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Not now'),
                style: TextButton.styleFrom(foregroundColor: AppColors.secondaryText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassOption extends StatelessWidget {
  const _GlassOption({
    required this.label,
    required this.amount,
    required this.color,
    required this.onTap,
    this.highlighted = false,
  });

  final String label;
  final int amount;
  final Color color;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: Color.alphaBlend(color.withValues(alpha: .12), AppColors.white),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: highlighted ? color : color.withValues(alpha: .35),
            width: highlighted ? 1.6 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(Icons.local_drink_rounded, size: 26, color: color),
            const SizedBox(height: 8),
            Text(
              '$amount',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.darkText,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              'ml',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: AppColors.secondaryText.withValues(alpha: .9),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final int amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.softPink : AppColors.cardMuted,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primaryPink : AppColors.hairline,
          ),
        ),
        child: Text(
          '$amount ml',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.purple : AppColors.darkText,
          ),
        ),
      ),
    );
  }
}
