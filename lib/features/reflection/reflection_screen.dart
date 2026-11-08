import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/models/mind_models.dart';
import '../../shared/widgets/akasha_text_field.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/app_dialog.dart';

/// The overthinking assistant: six compassionate questions, one at a time.
///
/// Deliberately not framed as CBT or therapy — it is a structured pause, and
/// the copy says so.
class ReflectionScreen extends ConsumerStatefulWidget {
  const ReflectionScreen({super.key});

  @override
  ConsumerState<ReflectionScreen> createState() => _ReflectionScreenState();
}

class _ReflectionScreenState extends ConsumerState<ReflectionScreen> {
  final _pageController = PageController();
  int _step = 0;
  bool _saving = false;

  final _situation = TextEditingController();
  final _assumption = TextEditingController();
  final _evidence = TextEditingController();
  final _alternative = TextEditingController();
  final _action = TextEditingController();
  MoodType? _moodAfter;

  static const List<_Prompt> _prompts = [
    _Prompt(
      question: 'What actually happened?',
      helper:
          'Just the facts you could film — no interpretations yet. Who said what? '
          'What did you actually see or hear?',
      hint: 'On Tuesday she replied with "ok". That is all that happened.',
    ),
    _Prompt(
      question: 'What am I assuming?',
      helper:
          'Often there is a hidden sentence under the facts, like "this means she '
          'is annoyed with me". You can write it out and look at it.',
      hint: 'I am assuming it meant something more.',
    ),
    _Prompt(
      question: 'What evidence supports my thought?',
      helper:
          'Look for real evidence, not feelings. If it is mostly feeling, that is '
          'useful information too.',
      hint: 'She has been quiet lately — that is one thing.',
    ),
    _Prompt(
      question: 'What other explanation could exist?',
      helper:
          'There is usually at least one kinder or more ordinary explanation. Can '
          'you find one that is plausible?',
      hint: 'She might have been busy, tired, or having a hard day.',
    ),
    _Prompt(
      question: 'Is there anything useful I can do right now?',
      helper:
          'A small, concrete step — or an honest "not right now". Both are valid '
          'answers.',
      hint: 'I could ask her how she is, once, without over-explaining.',
    ),
    _Prompt(
      question: 'Can I let this thought rest for now?',
      helper:
          'Not solving it is an option. You can come back to it tomorrow with a '
          'clearer head.',
      hint: 'I will leave this here until tomorrow morning.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    _situation.dispose();
    _assumption.dispose();
    _evidence.dispose();
    _alternative.dispose();
    _action.dispose();
    super.dispose();
  }

  TextEditingController _controllerFor(int step) => switch (step) {
        0 => _situation,
        1 => _assumption,
        2 => _evidence,
        3 => _alternative,
        4 => _action,
        _ => _action,
      };

  @override
  Widget build(BuildContext context) {
    final isLast = _step == _prompts.length - 1;
    return GradientScaffold(
      body: Column(
        children: [
          AkashaHeader(
            title: 'Untangle a thought',
            subtitle: 'Step ${_step + 1} of ${_prompts.length}',
            onBack: _step == 0
                ? null
                : () {
                    setState(() => _step--);
                    _pageController.previousPage(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                    );
                  },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (_step + 1) / _prompts.length,
                minHeight: 4,
                backgroundColor: AppColors.hairline,
                valueColor: const AlwaysStoppedAnimation(AppColors.primaryPink),
              ),
            ),
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(_prompts.length, (index) {
                final prompt = _prompts[index];
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: AppColors.lavenderBlue),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      prompt.question,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontSize: 21,
                            height: 1.3,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      prompt.helper,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 12.5,
                            height: 1.6,
                          ),
                    ),
                    const SizedBox(height: 18),
                    if (index < 5)
                      AkashaTextField(
                        controller: _controllerFor(index),
                        hint: prompt.hint,
                        maxLines: 6,
                        minLines: 4,
                      )
                    else
                      _FinalStep(
                        controller: _action,
                        hint: prompt.hint,
                        moodAfter: _moodAfter,
                        onMood: (m) => setState(() => _moodAfter = m),
                      ),
                    const SizedBox(height: 20),
                    Text(
                      'This is a reflective exercise, not therapy. If these thoughts '
                      'feel constant or frightening, please talk to someone you trust '
                      'or a healthcare professional.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10.5,
                            height: 1.55,
                          ),
                    ),
                  ],
                );
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 22),
            child: Row(
              children: [
                if (_step > 0)
                  Expanded(
                    flex: 1,
                    child: SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() => _step--);
                          _pageController.previousPage(
                            duration: const Duration(milliseconds: 260),
                            curve: Curves.easeOutCubic,
                          );
                        },
                        child: const Text('Back'),
                      ),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _saving ? null : () => isLast ? _save() : _next(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.purple,
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: AppColors.white),
                            )
                          : Text(isLast ? 'Save reflection' : 'Next'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextButton(
              onPressed: () async {
                final ok = await showAkashaConfirm(
                  context,
                  title: 'Close for now?',
                  message:
                      'Unfinished reflections are not saved. You can begin again any time.',
                  confirmLabel: 'Close',
                );
                if (ok && context.mounted) Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(foregroundColor: AppColors.secondaryText),
              child: const Text('Close', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  void _next() {
    setState(() => _step++);
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final profile = await ref.read(profileProvider.future);
      await ref.read(mindRepositoryProvider).saveReflection(
            userId: profile.id,
            situation: _situation.text.trim(),
            assumption: _assumption.text.trim(),
            evidenceFor: _evidence.text.trim(),
            alternative: _alternative.text.trim(),
            actionStep: _action.text.trim(),
            completed: true,
            moodAfter: _moodAfter,
          );
      ref.invalidate(dataRevisionProvider);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: AppColors.lavenderBlue),
                ),
                child: const Icon(Icons.spa_rounded, color: AppColors.white, size: 26),
              ),
              const SizedBox(height: 16),
              const Text(
                'You gave that thought somewhere to rest.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR()),
                  ),
                  child: const Text('Thank you'),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAkashaToast(
        context,
        'Could not save the reflection.',
        icon: Icons.error_outline_rounded,
        color: AppColors.danger,
      );
    }
  }
}

class _Prompt {
  const _Prompt({required this.question, required this.helper, required this.hint});
  final String question;
  final String helper;
  final String hint;
}

class _FinalStep extends StatelessWidget {
  const _FinalStep({
    required this.controller,
    required this.hint,
    required this.moodAfter,
    required this.onMood,
  });

  final TextEditingController controller;
  final String hint;
  final MoodType? moodAfter;
  final ValueChanged<MoodType?> onMood;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AkashaTextField(
          controller: controller,
          hint: hint,
          maxLines: 4,
          minLines: 3,
        ),
        const SizedBox(height: 18),
        Text(
          'How do you feel now?',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: MoodType.values.map((mood) {
            final selected = moodAfter == mood;
            return GestureDetector(
              onTap: () => onMood(selected ? null : mood),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.softPink
                      : AppColors.white.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected ? AppColors.primaryPink : AppColors.hairline,
                  ),
                ),
                child: Text(
                  mood.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.darkText,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
