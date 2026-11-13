import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../content/motivation_content.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/medicine_models.dart';
import '../../data/models/mind_models.dart';
import '../../data/models/user_settings.dart';
import '../../data/models/water_models.dart';
import '../../shared/widgets/fade_slide_in.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/progress_ring.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/water_drop.dart';
import '../dashboard/widgets/quick_water_sheet.dart';
import 'widgets/dashboard_cards.dart';

/// The home screen.
///
/// Every number on this page is read from SQLite through providers — there is
/// no sample data anywhere. Cards appear with a short stagger so the page feels
/// like a journal opening rather than a dashboard loading.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final settingsAsync = ref.watch(settingsProvider);

    return GradientScaffold(
      body: profileAsync.when(
        loading: () => const Center(child: LoadingDots()),
        error: (e, _) => ErrorStateView(onRetry: () => ref.invalidate(profileProvider)),
        data: (profile) => settingsAsync.when(
          loading: () => const Center(child: LoadingDots()),
          error: (e, _) => ErrorStateView(onRetry: () => ref.invalidate(settingsProvider)),
          data: (settings) => _DashboardBody(
            displayName: profile.displayName,
            settings: settings,
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.displayName, required this.settings});

  final String displayName;
  final UserSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waterAsync = ref.watch(todayWaterProvider);
    final dosesAsync = ref.watch(todayDosesProvider);
    final moodAsync = ref.watch(latestMoodProvider);
    final messageAsync = ref.watch(messageOfDayProvider);
    final gratitudeAsync = ref.watch(todayGratitudeProvider);
    final journalAsync = ref.watch(todayJournalCountProvider);
    final breathingAsync = ref.watch(todayBreathingProvider);

    final water = waterAsync.valueOrNull;
    final doses = dosesAsync.valueOrNull ?? const <DoseView>[];

    return RefreshIndicator(
      color: AppColors.primaryPink,
      backgroundColor: AppColors.white,
      onRefresh: () async {
        ref.invalidate(todayWaterProvider);
        ref.invalidate(todayDosesProvider);
        ref.invalidate(latestMoodProvider);
        ref.invalidate(todayGratitudeProvider);
        ref.invalidate(todayJournalCountProvider);
        ref.invalidate(todayBreathingProvider);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 118),
        children: [
          // ── Greeting ───────────────────────────────────────────────────
          FadeSlideIn(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${AkashaDates.greeting(DateTime.now())}, $displayName ♡',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontSize: 22,
                                height: 1.3,
                                letterSpacing: -0.4,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'A beautiful day starts with you.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontSize: 13,
                                color: AppColors.secondaryText,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _HeaderIconButton(
                    icon: Icons.notifications_none_rounded,
                    onTap: () => context.push('${Routes.home}/notifications'),
                  ),
                  const SizedBox(width: 8),
                  _HeaderIconButton(
                    icon: Icons.insights_rounded,
                    onTap: () => context.push('${Routes.home}/reports'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ── Water hero card ────────────────────────────────────────────
          FadeSlideIn(
            delay: const Duration(milliseconds: 80),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: WaterHeroCard(
                summary: water,
                settings: settings,
                onAdd: () => showQuickWaterSheet(context, ref),
                onQuickAdd: (amount, label) async {
                  await ref.read(waterRepositoryProvider).addLog(
                        userId: ref.read(currentUserIdProvider),
                        amountMl: amount,
                        source: WaterLogSource.quickAdd,
                        glassSize: label,
                      );
                  ref.invalidate(todayWaterProvider);
                  ref.invalidate(dataRevisionProvider);
                  if (context.mounted) {
                    showAkashaToast(
                      context,
                      '+$amount ml. Well done, Akasha ♡',
                      icon: Icons.water_drop_rounded,
                      color: AppColors.info,
                    );
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Quick stats strip ──────────────────────────────────────────
          FadeSlideIn(
            delay: const Duration(milliseconds: 140),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: MiniStat(
                      icon: Icons.local_drink_rounded,
                      value: '${water?.glassCount ?? 0}',
                      label: 'glasses today',
                      color: AppColors.info,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MiniStat(
                      icon: Icons.medication_liquid_rounded,
                      value:
                          '${doses.where((d) => d.log.status == DoseStatus.taken).length}/${doses.length}',
                      label: 'doses taken',
                      color: AppColors.rose,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MiniStat(
                      icon: Icons.local_fire_department_rounded,
                      value: '${breathingAsync.valueOrNull?.length ?? 0}',
                      label: 'calm breaks',
                      color: AppColors.purple,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),

          // ── Medicine card ──────────────────────────────────────────────
          FadeSlideIn(
            delay: const Duration(milliseconds: 200),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: MedicineTodayCard(
                doses: doses,
                onOpen: () => context.go(Routes.medicine),
                onRespond: (dose, status) async {
                  await ref.read(medicineRepositoryProvider).recordResponse(
                        logId: dose.log.id,
                        status: status,
                      );
                  ref.invalidate(todayDosesProvider);
                  ref.invalidate(dataRevisionProvider);
                },
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ── Mood ───────────────────────────────────────────────────────
          FadeSlideIn(
            delay: const Duration(milliseconds: 250),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: MoodCard(
                latest: moodAsync.valueOrNull,
                onOpen: () => context.push('${Routes.mind}/mood'),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ── Daily self-care ────────────────────────────────────────────
          FadeSlideIn(
            delay: const Duration(milliseconds: 300),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SelfCareCard(
                prompt: kSelfCarePrompts[
                    DateTime.now().difference(DateTime(2024)).inDays %
                        kSelfCarePrompts.length],
                doneToday: (gratitudeAsync.valueOrNull != null) ||
                    (journalAsync.valueOrNull ?? 0) > 0,
                onWrite: () => context.push('${Routes.mind}/gratitude'),
                onJournal: () => context.push('${Routes.mind}/journal/editor'),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ── Motivation ─────────────────────────────────────────────────
          FadeSlideIn(
            delay: const Duration(milliseconds: 340),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
                  if (context.mounted) {
                    showAkashaToast(
                      context,
                      message.isFavorite
                          ? 'Removed from favourites'
                          : 'Saved to favourites ♡',
                      icon: Icons.favorite_rounded,
                      color: AppColors.rose,
                    );
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ── Shortcuts ──────────────────────────────────────────────────
          FadeSlideIn(
            delay: const Duration(milliseconds: 380),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ShortcutGrid(
                onJournal: () => context.push('${Routes.mind}/journal'),
                onBreathing: () => context.push('${Routes.mind}/breathing'),
                onReflection: () => context.push('${Routes.mind}/reflection'),
                onLoveNotes: () => context.push('${Routes.mind}/love-notes'),
                onCalendar: () => context.push('${Routes.home}/calendar'),
                onReports: () => context.push('${Routes.home}/reports'),
                onCompanion: () => context.push('${Routes.mind}/companion'),
                onWaterSettings: () => context.push('${Routes.water}/reminders'),
                aiEnabled: settings.aiEnabled,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white.withValues(alpha: .8),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.hairline),
          ),
          child: Icon(icon, size: 19, color: AppColors.darkText),
        ),
      ),
    );
  }
}

/// The signature hydration card: progress ring, animated water fill, and a
/// one-tap add. Shared by the dashboard and the water tab.
class WaterHeroCard extends StatelessWidget {
  const WaterHeroCard({
    super.key,
    required this.summary,
    required this.settings,
    required this.onAdd,
    this.onQuickAdd,
  });

  final DailyWaterSummary? summary;
  final UserSettings settings;
  final VoidCallback onAdd;

  /// Fired with the exact amount when a size row is tapped, so the card can add
  /// a specific glass without opening the sheet.
  final void Function(int amount, String glassLabel)? onQuickAdd;

  @override
  Widget build(BuildContext context) {
    final data = summary;
    final total = data?.totalMl ?? 0;
    final target = settings.waterTargetMl;
    final progress = target == 0 ? 0.0 : (total / target).clamp(0.0, 1.5);
    final remaining = (target - total).clamp(0, target);

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      accent: AppColors.skyBlue,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Hydration',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontSize: 15.5,
                              ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.softBlue,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${(progress * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.info,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      total == 0
                          ? 'Your first glass is waiting.'
                          : progress >= 1
                              ? 'Goal reached — beautifully done.'
                              : '$remaining ml to go. Every sip counts.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _AddButton(onTap: onAdd),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ProgressRing(
                progress: progress,
                size: 148,
                strokeWidth: 13,
                waterLevel: progress.clamp(0, 1),
                gradient: AppColors.waterFill,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${(total / 1000).toStringAsFixed(total % 1000 == 0 ? 1 : 2)}',
                      style: const TextStyle(
                        fontSize: 27,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1,
                        color: AppColors.darkText,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'of ${(target / 1000).toStringAsFixed(1)} L',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
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
                      'Today\'s glasses',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 8),
                    DropletMeter(
                      filled: data?.glassCount ?? 0,
                      total: settings.glassesTarget,
                      maxVisible: 10,
                      size: 17,
                    ),
                    const SizedBox(height: 14),
                    _GlassRow(
                      label: 'Small',
                      ml: settings.smallGlassMl,
                      onTap: () => onQuickAdd != null
                          ? onQuickAdd!(settings.smallGlassMl, 'small')
                          : onAdd(),
                    ),
                    const SizedBox(height: 6),
                    _GlassRow(
                      label: 'Usual',
                      ml: settings.glassSizeMl,
                      onTap: () => onQuickAdd != null
                          ? onQuickAdd!(settings.glassSizeMl, 'medium')
                          : onAdd(),
                    ),
                    const SizedBox(height: 6),
                    _GlassRow(
                      label: 'Large',
                      ml: settings.largeGlassMl,
                      onTap: () => onQuickAdd != null
                          ? onQuickAdd!(settings.largeGlassMl, 'large')
                          : onAdd(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}

class _GlassRow extends StatelessWidget {
  const _GlassRow({required this.label, required this.ml, required this.onTap});

  final String label;
  final int ml;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            const Icon(Icons.add_rounded, size: 13, color: AppColors.info),
            const SizedBox(width: 4),
            Text(
              '$label · $ml ml',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: AppColors.waterFill),
          shape: BoxShape.circle,
          boxShadow: AppShadows.tinted(AppColors.skyBlue),
        ),
        child: const Icon(Icons.add_rounded, color: AppColors.white, size: 24),
      ),
    );
  }
}
