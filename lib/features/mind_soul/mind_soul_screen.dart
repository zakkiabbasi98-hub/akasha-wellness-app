import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/mind_models.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';
import '../dashboard/widgets/dashboard_cards.dart';

/// "MIND & SOUL" — the emotional wellness home.
class MindSoulScreen extends ConsumerWidget {
  const MindSoulScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final moodAsync = ref.watch(latestMoodProvider);
    final messageAsync = ref.watch(messageOfDayProvider);
    final gratitudeAsync = ref.watch(todayGratitudeProvider);
    final journalAsync = ref.watch(todayJournalCountProvider);
    final breathingAsync = ref.watch(todayBreathingProvider);

    return GradientScaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          const AkashaHeader(
            title: 'Mind & Soul',
            subtitle: 'A quiet room that belongs only to you',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Today's gentle summary
                FadeSlideIn(
                  child: SoftCard(
                    accent: AppColors.lavender,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.auto_awesome_rounded,
                                size: 16, color: AppColors.purple),
                            const SizedBox(width: 7),
                            Text(
                              'Today, gently',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontSize: 14.5),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _Mini(
                              icon: moodIcon(moodAsync.valueOrNull?.mood),
                              label: moodAsync.valueOrNull == null
                                  ? 'Mood'
                                  : moodAsync.valueOrNull!.mood.label,
                              color: AppColors.rose,
                            ),
                            _Mini(
                              icon: Icons.menu_book_rounded,
                              label: '${journalAsync.valueOrNull ?? 0} notes',
                              color: AppColors.purple,
                            ),
                            _Mini(
                              icon: Icons.air_rounded,
                              label: '${breathingAsync.valueOrNull?.length ?? 0} breaths',
                              color: AppColors.info,
                            ),
                            _Mini(
                              icon: Icons.favorite_rounded,
                              label: gratitudeAsync.valueOrNull == null
                                  ? 'Gratitude'
                                  : '${gratitudeAsync.valueOrNull!.items.length} thanks',
                              color: AppColors.gold,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 60),
                  child: _FeatureTile(
                    title: 'Mood check-in',
                    subtitle: 'How is your heart right now?',
                    icon: Icons.self_improvement_rounded,
                    gradient: AppColors.journalGradient,
                    onTap: () => context.push('${Routes.mind}/mood'),
                  ),
                ),
                const SizedBox(height: 10),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 100),
                  child: _FeatureTile(
                    title: 'Private journal',
                    subtitle: 'Somewhere to put the day',
                    icon: Icons.auto_stories_rounded,
                    gradient: AppColors.reflectGradient,
                    onTap: () => context.push('${Routes.mind}/journal'),
                  ),
                ),
                const SizedBox(height: 10),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 140),
                  child: _FeatureTile(
                    title: 'Overthinking helper',
                    subtitle: 'Untangle a thought, step by step',
                    icon: Icons.psychology_alt_rounded,
                    gradient: AppColors.breatheGradient,
                    onTap: () => context.push('${Routes.mind}/reflection'),
                  ),
                ),
                const SizedBox(height: 10),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 180),
                  child: _FeatureTile(
                    title: 'Breathe',
                    subtitle: 'Guided breathing, 1 to 5 minutes',
                    icon: Icons.air_rounded,
                    gradient: const [AppColors.mint, AppColors.skyBlue],
                    onTap: () => context.push('${Routes.mind}/breathing'),
                  ),
                ),
                const SizedBox(height: 10),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 220),
                  child: _FeatureTile(
                    title: 'Gratitude',
                    subtitle: 'Three small good things',
                    icon: Icons.volunteer_activism_rounded,
                    gradient: AppColors.warmPeachPink,
                    onTap: () => context.push('${Routes.mind}/gratitude'),
                  ),
                ),
                const SizedBox(height: 10),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 260),
                  child: _FeatureTile(
                    title: 'Little love notes',
                    subtitle: 'Warm words to keep',
                    icon: Icons.mark_email_unread_rounded,
                    gradient: AppColors.gentleBlush,
                    onTap: () => context.push('${Routes.mind}/love-notes'),
                  ),
                ),
                if (settings?.aiEnabled == true) ...[
                  const SizedBox(height: 10),
                  FadeSlideIn(
                    delay: const Duration(milliseconds: 300),
                    child: _FeatureTile(
                      title: 'Wellness companion',
                      subtitle: 'An optional, warm conversation',
                      icon: Icons.chat_bubble_outline_rounded,
                      gradient: const [AppColors.lavender, AppColors.primaryPink],
                      onTap: () => context.push('${Routes.mind}/companion'),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const SectionHeader(
                  title: 'Messages for you',
                  icon: Icons.format_quote_rounded,
                ),
                FadeSlideIn(
                  delay: const Duration(milliseconds: 300),
                  child: MotivationCard(
                    message: messageAsync.valueOrNull,
                    onOpen: () => context.push('${Routes.mind}/motivation'),
                    onHeart: () async {
                      final message = messageAsync.valueOrNull;
                      if (message == null) return;
                      await ref
                          .read(motivationRepositoryProvider)
                          .toggleFavorite(message.id, !message.isFavorite);
                      ref.invalidate(messageOfDayProvider);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Everything in this section stays on your phone unless you turn '
                    'on cloud sync yourself.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10.5,
                          height: 1.5,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: gradient.last.withValues(alpha: .28),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              size: 19, color: AppColors.secondaryText),
        ],
      ),
    );
  }
}

/// Small reusable header for section pages with today's date.
String todayLabel() => AkashaDates.isToday(DateTime.now())
    ? 'Today'
    : AkashaDates.shortDate(DateTime.now());
