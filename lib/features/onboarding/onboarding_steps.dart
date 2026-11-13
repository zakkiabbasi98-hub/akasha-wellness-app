import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Copy + artwork descriptors for the five opening story screens.
class OnboardingStory {
  const OnboardingStory({
    required this.title,
    required this.body,
    required this.icon,
    required this.accent,
    required this.gradient,
    this.showDroplet = false,
  });

  final String title;
  final String body;
  final IconData icon;
  final Color accent;
  final List<Color> gradient;
  final bool showDroplet;
}

const List<OnboardingStory> kOnboardingStories = [
  OnboardingStory(
    title: 'Stay hydrated,\nsoftly reminded',
    body:
        'Sixteen gentle water reminders a day, from morning to midnight. Each one '
        'can be logged with a single tap — no counting, no guilt.',
    icon: Icons.water_drop_rounded,
    accent: AppColors.skyBlue,
    gradient: AppColors.waterFill,
    showDroplet: true,
  ),
  OnboardingStory(
    title: 'Never miss\nyour medicine',
    body:
        'Set your own times exactly as your prescription says. Mark each dose as '
        'taken, skipped or later — and see a clear, honest history.',
    icon: Icons.medication_rounded,
    accent: AppColors.primaryPink,
    gradient: AppColors.pinkLavender,
  ),
  OnboardingStory(
    title: 'Take care\nof your mind',
    body:
        'A private journal, a mood check-in, guided breathing and a gentle '
        'reflection tool for the thoughts that will not settle.',
    icon: Icons.spa_rounded,
    accent: AppColors.purple,
    gradient: AppColors.lavenderBlue,
  ),
  OnboardingStory(
    title: 'See your own\nprogress',
    body:
        'Daily, weekly and monthly views built from your real records. Not a '
        'score to chase — just proof that small things add up.',
    icon: Icons.insights_rounded,
    accent: AppColors.info,
    gradient: AppColors.blueMint,
  ),
  OnboardingStory(
    title: 'Feel encouraged,\nevery day',
    body:
        'Over a hundred supportive messages, plus little love notes you can write '
        'to yourself — quiet proof that you are cared for.',
    icon: Icons.favorite_rounded,
    accent: AppColors.rose,
    gradient: AppColors.pinkPeach,
  ),
];
