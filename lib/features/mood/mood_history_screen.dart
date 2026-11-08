import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/mind_models.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';
import '../dashboard/widgets/dashboard_cards.dart';

/// Mood patterns over the last 30 days.
class MoodHistoryScreen extends ConsumerStatefulWidget {
  const MoodHistoryScreen({super.key});

  @override
  ConsumerState<MoodHistoryScreen> createState() => _MoodHistoryScreenState();
}

class _MoodHistoryScreenState extends ConsumerState<MoodHistoryScreen> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    ref.watch(dataRevisionProvider);

    return GradientScaffold(
      body: Column(
        children: [
          const AkashaHeader(
            title: 'Mood history',
            subtitle: 'Patterns, not verdicts',
          ),
          Expanded(
            child: profileAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => const ErrorStateView(),
              data: (profile) {
                final to = AkashaDates.today();
                final from = to.subtract(Duration(days: _days - 1));
                return FutureBuilder<List<MoodEntry>>(
                  key: ValueKey(_days),
                  future: ref.read(mindRepositoryProvider).moodRange(profile.id, from, to),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: LoadingDots());
                    }
                    final entries = snapshot.data!;
                    final counts = <MoodType, int>{};
                    for (final e in entries) {
                      counts[e.mood] = (counts[e.mood] ?? 0) + 1;
                    }
                    final mostCommon = counts.entries.isEmpty
                        ? null
                        : counts.entries.reduce(
                            (a, b) => a.value >= b.value ? a : b).key;

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
                      children: [
                        Row(
                          children: [
                            _chip('14 days', 14),
                            const SizedBox(width: 8),
                            _chip('30 days', 30),
                            const SizedBox(width: 8),
                            _chip('90 days', 90),
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (entries.isEmpty)
                          const EmptyState(
                            icon: Icons.self_improvement_rounded,
                            title: 'No check-ins yet',
                            message: 'A single check-in is enough to start seeing patterns.',
                          )
                        else ...[
                          SoftCard(
                            accent: AppColors.lavender,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${entries.length} check-ins in this period',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontSize: 14),
                                ),
                                if (mostCommon != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Most often: ${mostCommon.label}. '
                                    'Noticing is the whole point — there is nothing to fix.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(fontSize: 11.5, height: 1.5),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                ...(counts.entries.toList()
                                      ..sort((a, b) => b.value.compareTo(a.value)))
                                    .map((e) => Padding(
                                          padding: const EdgeInsets.only(bottom: 9),
                                          child: Row(
                                            children: [
                                              Icon(moodIcon(e.key),
                                                  size: 15, color: moodColor(e.key)),
                                              const SizedBox(width: 8),
                                              SizedBox(
                                                width: 76,
                                                child: Text(
                                                  e.key.label,
                                                  style: const TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w500,
                                                    color: AppColors.darkText,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(999),
                                                  child: LinearProgressIndicator(
                                                    value: e.value / entries.length,
                                                    minHeight: 7,
                                                    backgroundColor:
                                                        AppColors.hairline,
                                                    valueColor: AlwaysStoppedAnimation(
                                                        moodColor(e.key)),
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
                          const SizedBox(height: 14),
                          const SectionHeader(
                            title: 'All check-ins',
                            icon: Icons.list_alt_rounded,
                          ),
                          ...entries.reversed.map((entry) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: SoftCard(
                                  padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
                                  child: Row(
                                    children: [
                                      Icon(moodIcon(entry.mood),
                                          size: 20, color: moodColor(entry.mood)),
                                      const SizedBox(width: 11),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  entry.mood.label,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.darkText,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  '· ${entry.intensity}/5',
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: AppColors.secondaryText,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (entry.note?.isNotEmpty == true)
                                              Text(
                                                entry.note!,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  height: 1.4,
                                                  color: AppColors.secondaryText,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '${DateFormat('d MMM').format(entry.loggedAt)}\n${DateFormat('h:mm a').format(entry.loggedAt)}',
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          height: 1.35,
                                          color: AppColors.secondaryText,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                          const SizedBox(height: 10),
                          Text(
                            'Mood records are for your own reflection. The app does not '
                            'diagnose anxiety, depression or any other condition.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontSize: 10.5,
                                  height: 1.5,
                                ),
                          ),
                        ],
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

  Widget _chip(String label, int days) {
    final selected = _days == days;
    return GestureDetector(
      onTap: () => setState(() => _days = days),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.purple : Colors.white.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.purple : AppColors.hairline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.darkText,
          ),
        ),
      ),
    );
  }
}
