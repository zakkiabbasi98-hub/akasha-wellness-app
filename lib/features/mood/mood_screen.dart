import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/mind_models.dart';
import '../../shared/widgets/akasha_text_field.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';
import '../dashboard/widgets/dashboard_cards.dart';

/// Mood check-in: pick a feeling, add an optional note, save.
class MoodScreen extends ConsumerStatefulWidget {
  const MoodScreen({super.key});

  @override
  ConsumerState<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends ConsumerState<MoodScreen> {
  MoodType? _mood;
  int _intensity = 3;
  final _note = TextEditingController();
  bool _saving = false;

  static const Map<MoodType, String> _kindWords = {
    MoodType.happy: 'That is lovely. Let it stay a moment.',
    MoodType.calm: 'Calm is a good place to be. You earned it.',
    MoodType.excited: 'Your energy is beautiful. Enjoy it.',
    MoodType.sad: 'Sadness is allowed. You do not have to rush past it.',
    MoodType.stressed: 'That sounds like a lot. One breath at a time.',
    MoodType.overwhelmed: 'Feeling overwhelmed is not weakness — it means too much '
        'arrived at once. You can set some of it down.',
    MoodType.tired: 'Rest is not laziness. Be gentle with yourself.',
    MoodType.anxious: 'Anxiety is your body trying to protect you. You are safe here.',
  };

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      body: Column(
        children: [
          AkashaHeader(
            title: 'Mood check-in',
            subtitle: AkashaDates.prettyDate(DateTime.now()),
            trailing: HeaderAction(
              icon: Icons.history_rounded,
              onTap: () => context.push(Routes.moodHistory),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
              children: [
                Text(
                  'How is your heart right now?',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontSize: 20,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  'There is no wrong answer, and nothing here is a diagnosis.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
                ),
                const SizedBox(height: 20),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: .86,
                  children: MoodType.values.map((mood) {
                    final selected = _mood == mood;
                    final color = moodColor(mood);
                    return GestureDetector(
                      onTap: () => setState(() => _mood = mood),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: selected
                              ? Color.alphaBlend(
                                  color.withValues(alpha: .18), AppColors.white)
                              : AppColors.white.withValues(alpha: .72),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? color : AppColors.hairline,
                            width: selected ? 1.6 : 1,
                          ),
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: .22),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(moodIcon(mood), size: 24, color: color),
                            const SizedBox(height: 7),
                            Text(
                              mood.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight:
                                    selected ? FontWeight.w700 : FontWeight.w500,
                                color: AppColors.darkText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (_mood != null) ...[
                  const SizedBox(height: 18),
                  SoftCard(
                    accent: moodColor(_mood),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _kindWords[_mood] ?? '',
                          style: const TextStyle(
                            fontSize: 13,
                            height: 1.6,
                            fontStyle: FontStyle.italic,
                            color: AppColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Text(
                              'How strong is it?',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            const Spacer(),
                            Text(
                              '$_intensity / 5',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.purple,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _intensity.toDouble(),
                          min: 1,
                          max: 5,
                          divisions: 4,
                          activeColor: moodColor(_mood),
                          onChanged: (v) => setState(() => _intensity = v.round()),
                        ),
                        const SizedBox(height: 6),
                        AkashaTextField(
                          controller: _note,
                          hint: 'Want to say more? (optional)',
                          maxLines: 3,
                          minLines: 2,
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _mood == null || _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    disabledBackgroundColor: AppColors.lavender.withValues(alpha: .4),
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.white),
                        )
                      : Text(_mood == null ? 'Choose a feeling' : 'Save check-in'),
                ),
                const SizedBox(height: 12),
                if (_mood != null && (_mood == MoodType.overwhelmed || _mood == MoodType.anxious))
                  OutlinedButton.icon(
                    onPressed: () => context.push(Routes.breathing),
                    icon: const Icon(Icons.air_rounded, size: 17),
                    label: const Text('Try a two-minute breath'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final profile = await ref.read(profileProvider.future);
      await ref.read(mindRepositoryProvider).addMood(
            userId: profile.id,
            mood: _mood!,
            intensity: _intensity,
            note: _note.text,
          );
      ref.invalidate(latestMoodProvider);
      ref.invalidate(dataRevisionProvider);
      if (!mounted) return;
      context.pop();
      showAkashaToast(
        context,
        'Logged. Thank you for noticing yourself ♡',
        icon: Icons.favorite_rounded,
        color: moodColor(_mood),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAkashaToast(
        context,
        'Could not save that check-in.',
        icon: Icons.error_outline_rounded,
        color: AppColors.danger,
      );
    }
  }
}
