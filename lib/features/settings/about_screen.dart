import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/water_drop.dart';

/// About AKASHA — the story, the promises, and the credits.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messageCount = ref.watch(_countProvider);

    return GradientScaffold(
      body: Column(
        children: [
          const AkashaHeader(title: 'About', subtitle: 'Why AKASHA exists'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              children: [
                Center(
                  child: Column(
                    children: [
                      const AnimatedWaterDrop(size: 92),
                      const SizedBox(height: 16),
                      Text(
                        'AKASHA',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 8,
                          color: AppColors.darkText.withValues(alpha: .9),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Hydrate  •  Smile  •  Shine',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 2,
                          color: AppColors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Version 1.0.0',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SoftCard(
                  accent: AppColors.primaryPink,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'A small companion, not a supervisor',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 15,
                            ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'AKASHA was built for one person, to make her days a little '
                        'gentler. It reminds her to drink water, to take her medicine, '
                        'and to be kind to herself. It never scolds, never counts her '
                        'misses against her, and never shares her private thoughts.\n\n'
                        'Every reminder is written to sound like a friend, not an alarm. '
                        'Every screen is designed to feel calm rather than clinical.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.7,
                          color: AppColors.darkText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const SectionHeader(title: 'What is inside', icon: Icons.list_alt_rounded),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Fact(
                        icon: Icons.water_drop_rounded,
                        label: '16 default water reminders',
                        value: '09:00 AM → 12:00 AM, hourly',
                      ),
                      _Fact(
                        icon: Icons.medication_rounded,
                        label: 'Medicine tracking',
                        value: 'taken · skipped · snoozed · missed',
                      ),
                      _Fact(
                        icon: Icons.format_quote_rounded,
                        label: 'Supportive messages',
                        value: '${messageCount.valueOrNull ?? 100}+ original',
                      ),
                      const _Fact(
                        icon: Icons.lock_outline_rounded,
                        label: 'Offline-first',
                        value: 'all essential features work without internet',
                      ),
                      const _Fact(
                        icon: Icons.shield_outlined,
                        label: 'Private by default',
                        value: 'no ads, no trackers, no data selling',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SoftCard(
                  accent: AppColors.lavender,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.favorite_rounded,
                              size: 15, color: AppColors.rose),
                          const SizedBox(width: 7),
                          Text(
                            'A note to you',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontSize: 12.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'You do not have to be perfect at this. Drink some water when you '
                        'remember. Take your medicine when it is due. Write the hard things '
                        'down. Rest without apologising.\n\n'
                        'The app is only a gentle nudge. You are the one doing the living.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.7,
                          fontStyle: FontStyle.italic,
                          color: AppColors.darkText,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Built with Flutter · SQLite · Riverpod',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                        ),
                  ),
                ),
                const SizedBox(height: 4),
                Center(
                  child: Text(
                    '© ${DateTime.now().year} AKASHA',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                        ),
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

final _countProvider = FutureProvider<int>((ref) async {
  return ref.read(seedServiceProvider).messageCount();
});

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 15, color: AppColors.lavender),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 11,
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
