import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/medicine_models.dart';
import '../../../data/models/mind_models.dart';
import '../../../shared/widgets/soft_card.dart';

/// Small labelled stat used in the dashboard strip.
class MiniStat extends StatelessWidget {
  const MiniStat({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              fontSize: 17,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: AppColors.darkText,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's medicine list with inline taken/skip actions.
class MedicineTodayCard extends StatelessWidget {
  const MedicineTodayCard({
    super.key,
    required this.doses,
    required this.onOpen,
    required this.onRespond,
  });

  final List<DoseView> doses;
  final VoidCallback onOpen;
  final Future<void> Function(DoseView dose, DoseStatus status) onRespond;

  @override
  Widget build(BuildContext context) {
    final sorted = [...doses]..sort((a, b) => a.log.scheduledMinute.compareTo(b.log.scheduledMinute));
    final next = sorted.firstWhere(
      (d) => d.log.status == DoseStatus.scheduled || d.log.status == DoseStatus.snoozed,
      orElse: () => sorted.isEmpty
          ? DoseView(
              log: MedicineLog(
                id: '',
                userId: '',
                medicineId: '',
                dayKey: '',
                scheduledMinute: 0,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
              medicine: Medicine(
                id: '',
                userId: '',
                name: '',
                startDay: '',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            )
          : sorted.first,
    );
    final hasDoses = sorted.isNotEmpty;
    final takenCount = sorted.where((d) => d.log.status == DoseStatus.taken).length;

    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      accent: AppColors.primaryPink,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.softPink,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.medication_rounded,
                    size: 18, color: AppColors.rose),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Medicine',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 15,
                          ),
                    ),
                    Text(
                      hasDoses
                          ? '$takenCount of ${sorted.length} taken today'
                          : 'Nothing scheduled yet',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                          ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onOpen,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Open', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (!hasDoses) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.cardMuted,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add your medicines once, and reminders will follow your own schedule.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: onOpen,
                    child: const Row(
                      children: [
                        Icon(Icons.add_circle_outline_rounded,
                            size: 15, color: AppColors.purple),
                        SizedBox(width: 5),
                        Text(
                          'Add a medicine',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.purple,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            ...sorted.take(3).map((dose) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _DoseRow(dose: dose, onRespond: onRespond),
                )),
            if (sorted.length > 3)
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '+ ${sorted.length - 3} more today',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
            if (next.log.id.isNotEmpty &&
                (next.log.status == DoseStatus.scheduled))
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.softPeach,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 13, color: AppColors.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Next: ${next.medicine.name} at ${AkashaDates.minutesToLabel(next.log.scheduledMinute)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warmBrown,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _DoseRow extends StatelessWidget {
  const _DoseRow({required this.dose, required this.onRespond});

  final DoseView dose;
  final Future<void> Function(DoseView dose, DoseStatus status) onRespond;

  Color get _statusColor => switch (dose.log.status) {
        DoseStatus.taken => AppColors.success,
        DoseStatus.skipped => AppColors.warning,
        DoseStatus.missed => AppColors.danger,
        DoseStatus.snoozed => AppColors.info,
        DoseStatus.scheduled => AppColors.secondaryText,
      };

  @override
  Widget build(BuildContext context) {
    final answered = dose.log.isAnswered;
    return Row(
      children: [
        Container(
          width: 4,
          height: 30,
          decoration: BoxDecoration(
            color: _statusColor.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dose.medicine.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkText,
                ),
              ),
              Text(
                '${AkashaDates.minutesToLabel(dose.log.scheduledMinute)}'
                '${dose.medicine.dosage != null && dose.medicine.dosage!.isNotEmpty ? ' · ${dose.medicine.dosage}' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: AppColors.secondaryText),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        if (answered)
          StatusPill(
            label: dose.log.status.label,
            color: _statusColor,
            compact: true,
          )
        else
          Row(
            children: [
              _QuickAction(
                icon: Icons.check_rounded,
                color: AppColors.success,
                onTap: () => onRespond(dose, DoseStatus.taken),
              ),
              const SizedBox(width: 6),
              _QuickAction(
                icon: Icons.close_rounded,
                color: AppColors.secondaryText,
                onTap: () => onRespond(dose, DoseStatus.skipped),
              ),
            ],
          ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({required this.icon, required this.color, required this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }
}

/// Mood check-in card. Shows the latest mood or invites a first check-in.
class MoodCard extends StatelessWidget {
  const MoodCard({super.key, required this.latest, required this.onOpen});

  final MoodEntry? latest;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final mood = latest?.mood;
    return SoftCard(
      onTap: onOpen,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
      accent: AppColors.lavender,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: moodColor(mood).withValues(alpha: .9) ==
                      AppColors.darkText
                  ? AppColors.lavenderBlue
                  : [
                      moodColor(mood).withValues(alpha: .8),
                      AppColors.lavender.withValues(alpha: .8),
                    ]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              moodIcon(mood),
              size: 21,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Today\'s mood',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  mood == null
                      ? 'How is your heart today?'
                      : '${mood.label}${latest?.note?.isNotEmpty == true ? ' · ${latest!.note}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.softPink,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              mood == null ? 'Check in' : 'Update',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.purple,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color moodColor(MoodType? mood) => switch (mood) {
      MoodType.happy => AppColors.gold,
      MoodType.calm => AppColors.mint,
      MoodType.excited => AppColors.primaryPink,
      MoodType.sad => AppColors.info,
      MoodType.stressed => AppColors.peach,
      MoodType.overwhelmed => AppColors.lavender,
      MoodType.tired => AppColors.secondaryText,
      MoodType.anxious => AppColors.rose,
      null => AppColors.lavender,
    };

IconData moodIcon(MoodType? mood) => switch (mood) {
      MoodType.happy => Icons.sentiment_very_satisfied_rounded,
      MoodType.calm => Icons.spa_rounded,
      MoodType.excited => Icons.auto_awesome_rounded,
      MoodType.sad => Icons.sentiment_dissatisfied_rounded,
      MoodType.stressed => Icons.bolt_rounded,
      MoodType.overwhelmed => Icons.waves_rounded,
      MoodType.tired => Icons.nightlight_round,
      MoodType.anxious => Icons.blur_on_rounded,
      null => Icons.favorite_border_rounded,
    };

/// Daily self-care nudge with two gentle actions.
class SelfCareCard extends StatelessWidget {
  const SelfCareCard({
    super.key,
    required this.prompt,
    required this.doneToday,
    required this.onWrite,
    required this.onJournal,
  });

  final String prompt;
  final bool doneToday;
  final VoidCallback onWrite;
  final VoidCallback onJournal;

  @override
  Widget build(BuildContext context) {
    return GradientCard(
      gradient: AppColors.selfCareGradient,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      radius: AppRadius.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.self_improvement_rounded, size: 17, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                'Today\'s self-care',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontSize: 12.5,
                      letterSpacing: .2,
                    ),
              ),
              const Spacer(),
              if (doneToday)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .25),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'done today',
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            prompt,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.45,
              fontWeight: FontWeight.w500,
              color: Colors.white,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _WhitePill(
                icon: Icons.edit_note_rounded,
                label: 'Gratitude',
                onTap: onWrite,
              ),
              const SizedBox(width: 8),
              _WhitePill(
                icon: Icons.book_outlined,
                label: 'Write it down',
                onTap: onJournal,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WhitePill extends StatelessWidget {
  const _WhitePill({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: AppColors.purple),
            const SizedBox(width: 5),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.purple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The daily motivational message.
class MotivationCard extends StatelessWidget {
  const MotivationCard({
    super.key,
    required this.message,
    required this.onOpen,
    required this.onHeart,
  });

  final MotivationalMessage? message;
  final VoidCallback onOpen;
  final VoidCallback onHeart;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      accent: AppColors.lavender,
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.format_quote_rounded, size: 17, color: AppColors.lavender),
              const SizedBox(width: 6),
              Text(
                'A note for today',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontSize: 11,
                      letterSpacing: .4,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondaryText,
                    ),
              ),
              const Spacer(),
              IconButton(
                onPressed: onHeart,
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  message?.isFavorite == true
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: message?.isFavorite == true
                      ? AppColors.rose
                      : AppColors.secondaryText.withValues(alpha: .6),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6, top: 2),
            child: Text(
              message?.text ??
                  'You are doing better than you think, Akasha.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontSize: 14.5,
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                    color: AppColors.darkText,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message != null
                ? '${message!.category.label} · tap for more'
                : 'tap for more',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Grid of shortcuts into Mind & Soul and the report screens.
class ShortcutGrid extends StatelessWidget {
  const ShortcutGrid({
    super.key,
    required this.onJournal,
    required this.onBreathing,
    required this.onReflection,
    required this.onLoveNotes,
    required this.onCalendar,
    required this.onReports,
    required this.onCompanion,
    required this.onWaterSettings,
    this.aiEnabled = false,
  });

  final VoidCallback onJournal;
  final VoidCallback onBreathing;
  final VoidCallback onReflection;
  final VoidCallback onLoveNotes;
  final VoidCallback onCalendar;
  final VoidCallback onReports;
  final VoidCallback onCompanion;
  final VoidCallback onWaterSettings;
  final bool aiEnabled;

  @override
  Widget build(BuildContext context) {
    final items = <_Shortcut>[
      _Shortcut('Journal', Icons.auto_stories_rounded, AppColors.journalGradient, onJournal),
      _Shortcut('Breathe', Icons.air_rounded, AppColors.breatheGradient, onBreathing),
      _Shortcut('Reflect', Icons.psychology_alt_rounded, AppColors.reflectGradient, onReflection),
      _Shortcut('Love notes', Icons.mark_email_unread_rounded, AppColors.loveNoteGradient, onLoveNotes),
      _Shortcut('Calendar', Icons.calendar_month_rounded, AppColors.calendarGradient, onCalendar),
      _Shortcut('Reports', Icons.insights_rounded, AppColors.reportsGradient, onReports),
      if (aiEnabled)
        _Shortcut('Companion', Icons.chat_bubble_outline_rounded, AppColors.pinkLavender, onCompanion),
      _Shortcut('Reminders', Icons.alarm_rounded, AppColors.reminderGradient, onWaterSettings),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 10),
          child: Text(
            'Little corners of your space',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.darkText,
              letterSpacing: -0.2,
            ),
          ),
        ),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 10,
          childAspectRatio: .82,
          children: items
              .map((s) => _ShortcutTile(
                    label: s.label,
                    icon: s.icon,
                    gradient: s.gradient,
                    onTap: s.onTap,
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _Shortcut {
  const _Shortcut(this.label, this.icon, this.gradient, this.onTap);
  final String label;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;
}

class _ShortcutTile extends StatelessWidget {
  const _ShortcutTile({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Container(
            height: 46,
            width: 46,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradient,
              ),
              borderRadius: BorderRadius.circular(16),
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
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: const TextStyle(
              fontSize: 9.5,
              height: 1.2,
              fontWeight: FontWeight.w500,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Date + weekday header used inside reports and history screens.
String prettyDay(DateTime d) => DateFormat('EEEE').format(d);
