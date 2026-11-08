import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/mind_models.dart';
import '../../shared/widgets/akasha_text_field.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// Three things to be grateful for, saved per day.
class GratitudeScreen extends ConsumerStatefulWidget {
  const GratitudeScreen({super.key});

  @override
  ConsumerState<GratitudeScreen> createState() => _GratitudeScreenState();
}

class _GratitudeScreenState extends ConsumerState<GratitudeScreen> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  final _third = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  List<GratitudeEntry> _history = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final profile = await ref.read(profileProvider.future);
    final today = await ref
        .read(mindRepositoryProvider)
        .gratitudeForDay(profile.id, DateTime.now());
    final history = await ref.read(mindRepositoryProvider).gratitudeHistory(profile.id);
    if (!mounted) return;
    setState(() {
      if (today != null) {
        _first.text = today.first;
        _second.text = today.second ?? '';
        _third.text = today.third ?? '';
      }
      _history = history
          .where((h) => h.dayKey != AkashaDates.key(DateTime.now()))
          .toList();
      _loading = false;
    });
  }

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    _third.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const GradientScaffold(body: Center(child: LoadingDots()));
    }
    return GradientScaffold(
      body: Column(
        children: [
          const AkashaHeader(
            title: 'Gratitude',
            subtitle: 'Three small good things',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
              children: [
                SoftCard(
                  accent: AppColors.peach,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AkashaDates.prettyDate(DateTime.now()),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .4,
                          color: AppColors.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'What went gently right today?',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 16,
                            ),
                      ),
                      const SizedBox(height: 14),
                      _GratitudeField(
                        index: 1,
                        controller: _first,
                        hint: 'Something small that helped',
                      ),
                      const SizedBox(height: 10),
                      _GratitudeField(
                        index: 2,
                        controller: _second,
                        hint: 'A person, a moment, a taste',
                      ),
                      const SizedBox(height: 10),
                      _GratitudeField(
                        index: 3,
                        controller: _third,
                        hint: 'Even something very ordinary',
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _saving ? null : _save,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.purple,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Save for today'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_history.isNotEmpty) ...[
                  const SectionHeader(
                    title: 'Earlier days',
                    icon: Icons.history_rounded,
                  ),
                  ..._history.map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: SoftCard(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AkashaDates.shortDate(
                                  AkashaDates.parseKey(entry.dayKey),
                                ),
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: .3,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                              const SizedBox(height: 7),
                              ...entry.items.map((item) => Padding(
                                    padding: const EdgeInsets.only(bottom: 5),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.only(top: 3),
                                          child: Icon(Icons.favorite_rounded,
                                              size: 9, color: AppColors.rose),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            item,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              height: 1.5,
                                              color: AppColors.darkText,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),
                            ],
                          ),
                        ),
                      )),
                ] else
                  const EmptyState(
                    icon: Icons.volunteer_activism_outlined,
                    title: 'Your history will live here',
                    message: 'Each day you save becomes a small record of good things.',
                    compact: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final items = [_first.text, _second.text, _third.text]
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (items.isEmpty) {
      showAkashaToast(
        context,
        'Even one small thing is enough ♡',
        icon: Icons.favorite_rounded,
        color: AppColors.rose,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final profile = await ref.read(profileProvider.future);
      await ref.read(mindRepositoryProvider).saveGratitude(
            userId: profile.id,
            items: items,
          );
      ref.invalidate(todayGratitudeProvider);
      ref.invalidate(dataRevisionProvider);
      await _load();
      if (!mounted) return;
      setState(() => _saving = false);
      showAkashaToast(
        context,
        'Saved. Noticing is a quiet kind of strength.',
        icon: Icons.check_circle_rounded,
        color: AppColors.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAkashaToast(
        context,
        'Could not save that.',
        icon: Icons.error_outline_rounded,
        color: AppColors.danger,
      );
    }
  }
}

class _GratitudeField extends StatelessWidget {
  const _GratitudeField({
    required this.index,
    required this.controller,
    required this.hint,
  });

  final int index;
  final TextEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.softPeach,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$index',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.warning,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: AkashaTextField(
            controller: controller,
            hint: hint,
            maxLines: 2,
            minLines: 1,
          ),
        ),
      ],
    );
  }
}
