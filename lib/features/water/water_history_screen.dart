import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/water_models.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/date_strip.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// Day-by-day hydration log with the ability to correct or delete entries.
class WaterHistoryScreen extends ConsumerStatefulWidget {
  const WaterHistoryScreen({super.key});

  @override
  ConsumerState<WaterHistoryScreen> createState() => _WaterHistoryScreenState();
}

class _WaterHistoryScreenState extends ConsumerState<WaterHistoryScreen> {
  DateTime _day = AkashaDates.today();

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final profileAsync = ref.watch(profileProvider);
    final revision = ref.watch(dataRevisionProvider);

    return GradientScaffold(
      body: Column(
        children: [
          AkashaHeader(
            title: 'Water log',
            subtitle: AkashaDates.prettyDate(_day),
            trailing: DatePill(
              date: _day,
              onPick: (d) => setState(() => _day = d),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: DateStrip(
              selected: _day,
              days: 21,
              onSelect: (d) => setState(() => _day = d),
            ),
          ),
          Expanded(
            child: settingsAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => const ErrorStateView(),
              data: (settings) => profileAsync.when(
                loading: () => const Center(child: LoadingDots()),
                error: (_, __) => const ErrorStateView(),
                data: (profile) => FutureBuilder<DailyWaterSummary>(
                  key: ValueKey('$revision-${AkashaDates.key(_day)}'),
                  future: ref.read(waterRepositoryProvider).summaryForDay(
                        profile.id,
                        _day,
                        targetMl: settings.waterTargetMl,
                        glassSizeMl: settings.glassSizeMl,
                      ),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: LoadingDots());
                    }
                    final summary = snapshot.data!;
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
                      children: [
                        SoftCard(
                          accent: AppColors.skyBlue,
                          child: Row(
                            children: [
                              ProgressRing(
                                progress: settings.waterTargetMl == 0
                                    ? 0
                                    : summary.totalMl / settings.waterTargetMl,
                                size: 92,
                                strokeWidth: 9,
                                waterLevel: settings.waterTargetMl == 0
                                    ? 0
                                    : summary.totalMl / settings.waterTargetMl,
                                gradient: AppColors.waterFill,
                                child: Text(
                                  '${summary.totalMl}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.darkText,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${
                                        (summary.totalMl / 1000).toStringAsFixed(2)
                                      } of ${(settings.waterTargetMl / 1000).toStringAsFixed(1)} L',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(fontSize: 15),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${summary.entries.length} entries · ${summary.glassCount} glasses',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(fontSize: 11.5),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      summary.totalMl >= settings.waterTargetMl
                                          ? 'Goal met on this day ♡'
                                          : 'A partial day is still a real day.',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: AppColors.secondaryText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (summary.entries.isEmpty)
                          const EmptyState(
                            icon: Icons.water_drop_outlined,
                            title: 'Nothing logged on this day',
                            message: 'Days without records are simply quiet, not failed.',
                            compact: true,
                          )
                        else ...[
                          const SectionHeader(title: 'Entries', icon: Icons.toc_rounded),
                          ...summary.entries.map((log) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _HistoryTile(
                                  log: log,
                                  onDelete: () async {
                                    await ref
                                        .read(waterRepositoryProvider)
                                        .deleteLog(log.id);
                                    ref.invalidate(dataRevisionProvider);
                                  },
                                  onEdit: (amount) async {
                                    await ref
                                        .read(waterRepositoryProvider)
                                        .updateLogAmount(log.id, amount);
                                    ref.invalidate(dataRevisionProvider);
                                  },
                                ),
                              )),
                        ],
                        const SizedBox(height: 16),
                        if (AkashaDates.isSameDay(_day, DateTime.now()))
                          OutlinedButton.icon(
                            onPressed: () async {
                              final profile =
                                  await ref.read(profileProvider.future);
                              final settings =
                                  await ref.read(settingsProvider.future);
                              await ref.read(waterRepositoryProvider).addLog(
                                    userId: profile.id,
                                    amountMl: settings.glassSizeMl,
                                    source: WaterLogSource.manual,
                                    glassSize: 'medium',
                                  );
                              ref.invalidate(dataRevisionProvider);
                              if (context.mounted) {
                                showAkashaToast(
                                  context,
                                  '+${settings.glassSizeMl} ml added',
                                  icon: Icons.water_drop_rounded,
                                  color: AppColors.info,
                                );
                              }
                            },
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Add a glass now'),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.log,
    required this.onDelete,
    required this.onEdit,
  });

  final WaterLog log;
  final VoidCallback onDelete;
  final ValueChanged<int> onEdit;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.softBlue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              DateFormat('H').format(log.loggedAt),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.info,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${log.amountMl} ml',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
                Text(
                  DateFormat('h:mm a').format(log.loggedAt),
                  style: const TextStyle(fontSize: 10.5, color: AppColors.secondaryText),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz_rounded,
                size: 18, color: AppColors.secondaryText),
            onSelected: (value) async {
              if (value == 'delete') {
                onDelete();
              } else if (value == 'edit') {
                final controller = TextEditingController(text: '${log.amountMl}');
                final result = await showDialog<int>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Correct amount'),
                    content: TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      decoration: const InputDecoration(suffixText: 'ml'),
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
                if (result != null) onEdit(result);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Correct amount')),
              PopupMenuItem(value: 'delete', child: Text('Remove entry')),
            ],
          ),
        ],
      ),
    );
  }
}
