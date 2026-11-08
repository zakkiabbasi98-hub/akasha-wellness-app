import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/mind_models.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

final _historyProvider = FutureProvider<List<NotificationRecord>>((ref) async {
  ref.watch(dataRevisionProvider);
  final profile = await ref.watch(profileProvider.future);
  return ref.read(notificationHistoryProvider).recent(profile.id, limit: 150);
});

/// What was raised, when, and what happened next.
class NotificationHistoryScreen extends ConsumerWidget {
  const NotificationHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(_historyProvider);

    return GradientScaffold(
      body: Column(
        children: [
          const AkashaHeader(
            title: 'Reminder history',
            subtitle: 'Everything Akasha gently nudged you about',
          ),
          Expanded(
            child: historyAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => ErrorStateView(
                onRetry: () => ref.invalidate(_historyProvider),
              ),
              data: (records) {
                if (records.isEmpty) {
                  return const EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'Nothing yet',
                    message:
                        'Once reminders start arriving, you will see each one and what '
                        'you did with it here.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SoftCard(
                        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: _colorFor(record.kind).withValues(alpha: .13),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Icon(
                                _iconFor(record.kind),
                                size: 16,
                                color: _colorFor(record.kind),
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    record.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.darkText,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    record.deliveredAt == null
                                        ? '—'
                                        : '${AkashaDates.prettyDate(record.deliveredAt!)} · ${AkashaDates.hhmm(record.deliveredAt!)}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (record.actionTaken != null)
                              StatusPill(
                                label: _actionLabel(record.actionTaken!),
                                color: _actionColor(record.actionTaken!),
                                compact: true,
                              )
                            else
                              const Text(
                                'no action',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                          ],
                        ),
                      ),
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

  IconData _iconFor(String kind) => switch (kind) {
        'water' => Icons.water_drop_rounded,
        'medicine' => Icons.medication_rounded,
        'motivation' => Icons.auto_awesome_rounded,
        'love_note' => Icons.favorite_rounded,
        'daily' => Icons.insights_rounded,
        _ => Icons.notifications_rounded,
      };

  Color _colorFor(String kind) => switch (kind) {
        'water' => AppColors.info,
        'medicine' => AppColors.rose,
        'motivation' => AppColors.purple,
        'love_note' => AppColors.primaryPink,
        _ => AppColors.lavender,
      };

  String _actionLabel(String action) => switch (action) {
        'taken' => 'done',
        'skipped' => 'skipped',
        'snoozed' => 'later',
        'opened' => 'opened',
        _ => action,
      };

  Color _actionColor(String action) => switch (action) {
        'taken' => AppColors.success,
        'skipped' => AppColors.warning,
        'snoozed' => AppColors.info,
        _ => AppColors.secondaryText,
      };
}
