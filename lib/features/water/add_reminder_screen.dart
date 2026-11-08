import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/services/water_schedule_engine.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/id.dart';
import '../../data/models/water_models.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/app_dialog.dart';

/// Add or edit a single custom water reminder.
class AddReminderScreen extends ConsumerStatefulWidget {
  const AddReminderScreen({super.key, this.editing});

  final WaterReminder? editing;

  @override
  ConsumerState<AddReminderScreen> createState() => _AddReminderScreenState();
}

class _AddReminderScreenState extends ConsumerState<AddReminderScreen> {
  late TimeOfDay _time;
  late int _amount;
  late bool _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final editing = widget.editing;
    final minutes = editing?.minuteOfDay ?? 15 * 60;
    _time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    _amount = editing?.amountMl ?? 250;
    _enabled = editing?.enabled ?? true;
  }

  bool get _isEditing => widget.editing != null;

  @override
  Widget build(BuildContext context) {
    final existing = ref.watch(waterRemindersProvider).valueOrNull ?? const <WaterReminder>[];
    final minute = _time.hour * 60 + _time.minute;
    final clash = existing.any(
      (r) => r.minuteOfDay == minute && r.id != widget.editing?.id,
    );

    return GradientScaffold(
      body: Column(
        children: [
          AkashaHeader(
            title: _isEditing ? 'Edit reminder' : 'New reminder',
            subtitle: 'A single gentle nudge',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
              children: [
                SoftCard(
                  accent: AppColors.skyBlue,
                  child: Column(
                    children: [
                      Text(
                        'Reminder time',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: _pickTime,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.softBlue,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            WaterScheduleEngine.formatLabel(minute),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -1,
                              color: AppColors.darkText,
                            ),
                          ),
                        ),
                      ),
                      if (clash) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.softPeach,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  size: 14, color: AppColors.warning),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'There is already a reminder at this time. Saving will replace it.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.35,
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
                ),
                const SizedBox(height: 14),
                SoftCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Suggested amount',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [150, 200, 250, 300, 350, 500].map((ml) {
                          final selected = _amount == ml;
                          return GestureDetector(
                            onTap: () => setState(() => _amount = ml),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(
                                color: selected ? AppColors.purple : AppColors.cardMuted,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: selected ? AppColors.purple : AppColors.hairline,
                                ),
                              ),
                              child: Text(
                                '$ml ml',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selected ? Colors.white : AppColors.darkText,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _enabled,
                        activeTrackColor: AppColors.primaryPink,
                        onChanged: (v) => setState(() => _enabled = v),
                        title: const Text(
                          'Reminder active',
                          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'You can switch it off without deleting it.',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(_isEditing ? 'Save changes' : 'Add reminder'),
                ),
                if (_isEditing) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _delete,
                    icon: const Icon(Icons.delete_outline_rounded,
                        size: 17, color: AppColors.danger),
                    label: const Text(
                      'Delete reminder',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Tip: the default schedule already covers 09:00 AM to 12:00 AM hourly. '
                  'Custom slots are for extra moments — like right after a walk.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        height: 1.5,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
      helpText: 'Reminder time',
    );
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final profile = await ref.read(profileProvider.future);
      final minute = _time.hour * 60 + _time.minute;
      final reminder = WaterReminder(
        id: widget.editing?.id ??
            Ids.slotId('watercustom', '${profile.id}:$minute:${DateTime.now().millisecondsSinceEpoch}'),
        userId: profile.id,
        minuteOfDay: minute,
        label: WaterScheduleEngine.formatLabel(minute),
        amountMl: _amount,
        enabled: _enabled,
        isDefaultSlot: false,
        sortOrder: minute,
        createdAt: widget.editing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await ref.read(waterRepositoryProvider).upsertReminder(reminder);
      final notifications = ref.read(notificationServiceProvider);
      final exact = await notifications.canScheduleExactAlarms();
      await ref.read(reminderSchedulerProvider).rescheduleAll(exact: exact);
      ref.invalidate(waterRemindersProvider);
      ref.invalidate(dataRevisionProvider);
      ref.invalidate(schedulingStatusProvider);
      if (!mounted) return;
      context.pop();
      showAkashaToast(
        context,
        _isEditing ? 'Reminder updated' : 'Reminder added for ${reminder.timeLabel}',
        icon: Icons.alarm_on_rounded,
        color: AppColors.info,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAkashaToast(
        context,
        'Could not save the reminder. Please try again.',
        icon: Icons.error_outline_rounded,
        color: AppColors.danger,
      );
    }
  }

  Future<void> _delete() async {
    final id = widget.editing?.id;
    if (id == null) return;
    final ok = await showAkashaConfirm(
      context,
      title: 'Delete this reminder?',
      message: 'This reminder will stop. Your water history stays untouched.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(waterRepositoryProvider).softDeleteReminder(id);
    final exact = await ref.read(notificationServiceProvider).canScheduleExactAlarms();
    await ref.read(reminderSchedulerProvider).rescheduleAll(exact: exact);
    ref.invalidate(waterRemindersProvider);
    ref.invalidate(dataRevisionProvider);
    if (!mounted) return;
    context.pop();
  }
}
