import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/services/water_schedule_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/medicine_models.dart';
import '../../data/models/user_settings.dart';
import '../../shared/widgets/akasha_text_field.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/water_drop.dart';
import 'onboarding_steps.dart';

/// Five story screens, then a short, honest setup. Skippable at any point —
/// defaults are sensible and everything can be changed later in Settings.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  // Setup state
  final _nameController = TextEditingController(text: 'Akasha');
  int _targetMl = AppConstants.defaultWaterTargetMl;
  int _glassMl = AppConstants.defaultGlassMl;
  int _startMinute = AppConstants.defaultWaterStartMinute;
  int _endMinute = AppConstants.defaultWaterEndMinute;
  int _interval = AppConstants.defaultWaterIntervalMinutes;
  bool _voiceEnabled = true;
  bool _motivationEnabled = true;
  bool _quietEnabled = true;
  bool _requestPerms = true;
  bool _saving = false;
  bool _addExampleMedicine = false;
  final List<int> _medicineTimes = [AppConstants.exampleMorningMinute];

  static const int _storyCount = 5;

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  int get _totalPages => _storyCount + 2; // + setup + permissions

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          _TopBar(
            page: _page,
            total: _totalPages,
            onSkip: _page < _storyCount ? _finish : null,
          ),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const ClampingScrollPhysics(),
              onPageChanged: (i) => setState(() => _page = i),
              children: [
                ...kOnboardingStories.map((s) => _StoryPage(story: s)),
                _buildSetupPage(),
                _buildPermissionsPage(),
              ],
            ),
          ),
          _BottomBar(
            page: _page,
            total: _totalPages,
            saving: _saving,
            onNext: _next,
            onBack: _page == 0 ? null : _back,
          ),
        ],
      ),
    );
  }

  // ── Page 1: personal + hydration ────────────────────────────────────────
  Widget _buildSetupPage() {
    final slots = WaterScheduleEngine.estimateSlotsPerDay(
      startMinute: _startMinute,
      endMinute: _endMinute,
      intervalMinutes: _interval,
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageTitle(
            title: 'Let us make this yours',
            subtitle: 'Only what helps. Nothing you would not want to share.',
          ),
          const SizedBox(height: 18),
          AkashaTextField(
            controller: _nameController,
            label: 'What should I call you?',
            icon: Icons.favorite_rounded,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
          ),
          const SizedBox(height: 20),
          _FieldLabel('Daily water goal'),
          const SizedBox(height: 8),
          _ChoiceRow(
            options: const [1500, 2000, 2500, 3000],
            selected: _targetMl,
            labelFor: (v) => '${v ~/ 1000 == 0 ? '' : '${v ~/ 1000}.'}${(v % 1000) ~/ 100} L',
            onSelect: (v) => setState(() => _targetMl = v),
          ),
          const SizedBox(height: 20),
          _FieldLabel('How big is your usual glass?'),
          const SizedBox(height: 8),
          _ChoiceRow(
            options: const [
              AppConstants.smallGlassMl,
              AppConstants.defaultGlassMl,
              AppConstants.largeGlassMl,
            ],
            selected: _glassMl,
            labelFor: (v) => '$v ml',
            onSelect: (v) => setState(() => _glassMl = v),
          ),
          const SizedBox(height: 20),
          SoftCard(
            padding: const EdgeInsets.all(16),
            accent: AppColors.skyBlue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.water_drop_outlined,
                        size: 18, color: AppColors.info),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your reminder window',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      '$slots a day',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.purple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _TimeButton(
                        label: 'From',
                        value: WaterScheduleEngine.formatLabel(_startMinute),
                        onPick: (m) => setState(() => _startMinute = m),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TimeButton(
                        label: 'Until (inclusive)',
                        value: WaterScheduleEngine.formatLabel(_endMinute),
                        onPick: (m) => setState(() => _endMinute = m),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [30, 45, 60, 90, 120]
                      .map((m) => _MiniChip(
                            label: m < 60 ? '$m min' : '${m ~/ 60} h',
                            selected: _interval == m,
                            onTap: () => setState(() => _interval = m),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 10),
                Text(
                  'Default: 09:00 AM to 12:00 AM, every hour — that is 16 gentle '
                  'reminders, including midnight.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _FieldLabel('Medicines'),
          const SizedBox(height: 6),
          Text(
            'You can add your own medicines and exact prescribed times in the '
            'Medicine tab. The times below are only examples.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          SoftCard(
            padding: const EdgeInsets.all(6),
            child: SwitchListTile.adaptive(
              value: _addExampleMedicine,
              onChanged: (v) => setState(() => _addExampleMedicine = v),
              activeThumbColor: AppColors.white,
              activeTrackColor: AppColors.primaryPink,
              title: const Text(
                'Set up a medicine reminder now',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Optional. You will edit the real details yourself.',
                style: TextStyle(fontSize: 11.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Page 2: preferences + permissions ───────────────────────────────────
  Widget _buildPermissionsPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageTitle(
            title: 'A few gentle preferences',
            subtitle: 'Everything here can be changed later. Nothing is permanent.',
          ),
          const SizedBox(height: 16),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                SwitchListTile.adaptive(
                  value: _voiceEnabled,
                  onChanged: (v) => setState(() => _voiceEnabled = v),
                  activeTrackColor: AppColors.primaryPink,
                  title: const Text('Speak my reminders',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                    'Uses the voice already installed on your phone.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  value: _motivationEnabled,
                  onChanged: (v) => setState(() => _motivationEnabled = v),
                  activeTrackColor: AppColors.primaryPink,
                  title: const Text('Encouragement during the day',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                    'A few small supportive messages, never more than you want.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile.adaptive(
                  value: _quietEnabled,
                  onChanged: (v) => setState(() => _quietEnabled = v),
                  activeTrackColor: AppColors.primaryPink,
                  title: const Text('Quiet hours at night',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                    'Water and encouragement pause between 10:30 PM and 7:00 AM. '
                    'Medicine reminders keep their own switch.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SoftCard(
            accent: AppColors.lavender,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.notifications_active_outlined,
                        size: 18, color: AppColors.purple),
                    const SizedBox(width: 8),
                    Text('Notifications',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Akasha needs notification permission to remind you. Android may '
                  'also ask about exact alarms — granting it makes reminders land at '
                  'the right minute rather than "sometime around then".',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _requestPerms,
                  onChanged: (v) => setState(() => _requestPerms = v),
                  activeTrackColor: AppColors.primaryPink,
                  title: const Text('Ask for permission when I finish',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Privacy: everything you write stays on this phone. Cloud sync is '
            'optional and off by default. There is no advertising and no tracking.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5),
          ),
        ],
      ),
    );
  }

  // ── Navigation ──────────────────────────────────────────────────────────

  void _next() {
    if (_page < _totalPages - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_page > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final name = _nameController.text.trim().isEmpty
          ? 'Akasha'
          : _nameController.text.trim();

      final profiles = ref.read(profileRepositoryProvider);
      final water = ref.read(waterRepositoryProvider);
      final medicine = ref.read(medicineRepositoryProvider);
      final motivations = ref.read(motivationRepositoryProvider);
      final database = ref.read(databaseProvider);

      // Everything that makes an account "set up" is one unit of work: the
      // profile, its settings, the chosen water schedule, the optional example
      // medicine and the motivation slots. One transaction means a failure
      // anywhere leaves the app exactly as it was — never an onboarded profile
      // with no reminders, and never a half-written schedule. Repositories are
      // handed that transaction so none of them opens a nested one (the cause
      // of "cannot start a transaction within a transaction").
      final profile = await database.transaction((txn) async {
        final profile = await profiles.completeOnboarding(name, txn: txn);
        await profiles.mutateSettings(
          (s) => s.copyWith(
            waterTargetMl: _targetMl,
            glassSizeMl: _glassMl,
            waterStartMin: _startMinute,
            waterEndMin: _endMinute,
            waterIntervalMin: _interval,
            voiceEnabled: _voiceEnabled,
            motivationEnabled: _motivationEnabled,
            quietModeEnabled: _quietEnabled,
          ),
          txn: txn,
        );

        await water.generateDefaultSchedule(
          userId: profile.id,
          startMinute: _startMinute,
          endMinute: _endMinute,
          intervalMinutes: _interval,
          amountMl: _glassMl,
          txn: txn,
        );

        if (_addExampleMedicine) {
          final today = AkashaDates.today();
          await medicine.save(
            Medicine(
              id: 'onboarding-example-${DateTime.now().millisecondsSinceEpoch}',
              userId: profile.id,
              name: 'My medicine',
              dosage: 'As written on my prescription',
              category: MedicineCategory.morning,
              startDay: AkashaDates.key(today),
              reminderMinutes: _medicineTimes,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
            txn: txn,
          );
        }

        await motivations.regenerateSchedule(
          userId: profile.id,
          count: 3,
          wakeMinute: 9 * 60,
          sleepMinute: 21 * 60,
          txn: txn,
        );
        return profile;
      });

      // Permissions and alarm materialisation are best-effort *after* the data
      // is committed: a user who denies notifications is still onboarded, and a
      // device that cannot schedule alarms must not block the dashboard.
      if (_requestPerms) {
        try {
          final notifications = ref.read(notificationServiceProvider);
          await notifications.initialize();
          await notifications.requestPermission();
          if (await notifications.canScheduleExactAlarms() == false) {
            await notifications.requestExactAlarmsPermission();
          }
        } catch (e, st) {
          debugPrint('AKASHA: notification permission step failed: $e\n$st');
        }
      }

      try {
        final scheduler = ref.read(reminderSchedulerProvider);
        final exact =
            await ref.read(notificationServiceProvider).canScheduleExactAlarms();
        await scheduler.rescheduleAll(exact: exact);
      } catch (e, st) {
        // Reminders can be re-materialised on the next launch; a failure here
        // must not strand a successfully-created account on the onboarding
        // screen. Logged with its stack trace, never swallowed silently.
        debugPrint('AKASHA: initial reminder scheduling failed: $e\n$st');
      }

      // Only now is the account genuinely usable.
      if (!profile.isOnboarded) {
        throw StateError('Onboarding did not persist: onboarded_at is null');
      }
      ref.invalidate(profileProvider);
      ref.invalidate(settingsProvider);
      ref.invalidate(dataRevisionProvider);
      if (!mounted) return;
      context.go(Routes.home);
    } catch (e, st) {
      // Preserve the original exception and stack trace for development logs.
      // The user sees a plain-language message; the console keeps the cause.
      debugPrint('AKASHA onboarding failed: $e\n$st');
      if (!mounted) return;
      setState(() => _saving = false);
      showAkashaToast(
        context,
        _messageFor(e),
        icon: Icons.error_outline_rounded,
        color: AppColors.danger,
      );
    }
  }

  /// Turns a failure into something a person can act on, without leaking
  /// table names or stack traces into the interface.
  String _messageFor(Object error) {
    if (error is DatabaseException) {
      return 'Your information could not be saved. Please try once more — '
          'nothing has been lost.';
    }
    return 'Something interrupted setup. Please try once more.';
  }
}

// ─── Sub-widgets ───────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.page, required this.total, this.onSkip});

  final int page;
  final int total;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 6),
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                height: 4,
                child: LinearProgressIndicator(
                  value: (page + 1) / total,
                  backgroundColor: AppColors.hairline,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primaryPink),
                  minHeight: 4,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          if (onSkip != null)
            TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                foregroundColor: AppColors.secondaryText,
              ),
              child: const Text('Skip', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.page,
    required this.total,
    required this.saving,
    required this.onNext,
    this.onBack,
  });

  final int page;
  final int total;
  final bool saving;
  final VoidCallback onNext;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final last = page == total - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
      child: Row(
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SizedBox(
                width: 54,
                height: 54,
                child: OutlinedButton(
                  onPressed: onBack,
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.zero,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                    minimumSize: const Size(54, 54),
                  ),
                  child: const Icon(Icons.arrow_back_rounded, size: 20),
                ),
              ),
            ),
          Expanded(
            child: SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: saving ? null : onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
                ),
                child: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: AppColors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(last ? 'Begin my journey' : 'Continue'),
                          const SizedBox(width: 8),
                          Icon(
                            last
                                ? Icons.favorite_rounded
                                : Icons.arrow_forward_rounded,
                            size: 18,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryPage extends StatelessWidget {
  const _StoryPage({required this.story});

  final OnboardingStory story;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _StoryArt(story: story),
                    const SizedBox(height: 34),
                    Text(
                      story.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontSize: 27,
                            height: 1.24,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        story.body,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.secondaryText,
                              height: 1.65,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryArt extends StatelessWidget {
  const _StoryArt({required this.story});

  final OnboardingStory story;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 196,
            height: 196,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  story.accent.withValues(alpha: .30),
                  story.accent.withValues(alpha: .04),
                ],
              ),
            ),
          ),
          Container(
            width: 148,
            height: 148,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.white.withValues(alpha: .72),
              border: Border.all(color: AppColors.white, width: 2),
              boxShadow: AppShadows.soft,
            ),
          ),
          if (story.showDroplet)
            AnimatedWaterDrop(size: 96, gradient: story.gradient)
          else
            Icon(story.icon, size: 62, color: story.accent),
        ],
      ),
    );
  }
}

class _PageTitle extends StatelessWidget {
  const _PageTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 21)),
        const SizedBox(height: 6),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.5)),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.darkText,
        letterSpacing: -0.1,
      ),
    );
  }
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.options,
    required this.selected,
    required this.labelFor,
    required this.onSelect,
  });

  final List<int> options;
  final int selected;
  final String Function(int) labelFor;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: options.map((option) {
        final isSelected = option == selected;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.softPink : AppColors.white.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? AppColors.primaryPink : AppColors.hairline,
                    width: isSelected ? 1.5 : 1,
                  ),
                ),
                child: Text(
                  labelFor(option),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? AppColors.purple : AppColors.darkText,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.purple : AppColors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.purple : AppColors.hairline),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.white : AppColors.darkText,
          ),
        ),
      ),
    );
  }
}

class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final String value;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () async {
            final parts = WaterScheduleEngine.formatLabel(
              WaterScheduleEngine.parseTime(value) ?? 0,
            );
            final initialHour = int.parse(parts.split(':')[0]);
            final isPm = parts.contains('PM');
            final hour24 = isPm
                ? (initialHour == 12 ? 12 : initialHour + 12)
                : (initialHour == 12 ? 0 : initialHour);
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay(
                hour: hour24,
                minute: WaterScheduleEngine.parseTime(value)! % 60,
              ),
              helpText: label,
              builder: (context, child) => Theme(
                data: Theme.of(context).copyWith(
                  timePickerTheme: TimePickerThemeData(
                    backgroundColor: AppColors.white,
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.cardR),
                  ),
                ),
                child: child!,
              ),
            );
            if (picked != null) onPick(picked.hour * 60 + picked.minute);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 15, color: AppColors.lavender),
                const SizedBox(width: 6),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.darkText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
