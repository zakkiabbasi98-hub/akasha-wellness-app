import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/notifications/reminder_scheduler.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/id.dart';
import '../../core/utils/validators.dart';
import '../../data/models/medicine_models.dart';
import '../../shared/widgets/akasha_text_field.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';
import '../../shared/widgets/app_dialog.dart';

/// Add or edit a medicine. All fields are hers to control; nothing is suggested
/// as medical advice.
class AddMedicineScreen extends ConsumerStatefulWidget {
  const AddMedicineScreen({super.key, this.editing});

  final Medicine? editing;

  @override
  ConsumerState<AddMedicineScreen> createState() => _AddMedicineScreenState();
}

class _AddMedicineScreenState extends ConsumerState<AddMedicineScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _dosage;
  late final TextEditingController _notes;
  late final TextEditingController _withFood;
  late MedicineCategory _category;
  late Set<int> _weekdays;
  late List<int> _times;
  DateTime? _endDate;
  late bool _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.editing;
    _name = TextEditingController(text: m?.name ?? '');
    _dosage = TextEditingController(text: m?.dosage ?? '');
    _notes = TextEditingController(text: m?.notes ?? '');
    _withFood = TextEditingController(text: m?.withFood ?? '');
    _category = m?.category ?? MedicineCategory.morning;
    _weekdays = {...(m?.weekdays ?? [1, 2, 3, 4, 5, 6, 7])};
    _times = [...(m?.reminderMinutes ?? [AppConstants.exampleMorningMinute])];
    _endDate = m?.endDay != null ? AkashaDates.parseKey(m!.endDay!) : null;
    _enabled = m?.enabled ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _dosage.dispose();
    _notes.dispose();
    _withFood.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      body: Column(
        children: [
          AkashaHeader(
            title: widget.editing == null ? 'Add medicine' : 'Edit medicine',
            subtitle: 'Exactly as your prescription says',
          ),
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 30),
                children: [
                  SoftCard(
                    child: Column(
                      children: [
                        AkashaTextField(
                          controller: _name,
                          label: 'Medicine name',
                          hint: 'e.g. the name on the box',
                          icon: Icons.medication_rounded,
                          textCapitalization: TextCapitalization.words,
                          validator: Validators.medicineName,
                        ),
                        const SizedBox(height: 12),
                        AkashaTextField(
                          controller: _dosage,
                          label: 'Dosage instructions (optional)',
                          hint: 'Copy what your prescription says',
                          icon: Icons.description_outlined,
                          validator: Validators.dosage,
                        ),
                        const SizedBox(height: 12),
                        AkashaTextField(
                          controller: _withFood,
                          label: 'With food? (optional)',
                          hint: 'e.g. after breakfast',
                          icon: Icons.restaurant_outlined,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Reminder times',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'These are examples you can change. Akasha does not decide '
                          'when a medicine should be taken.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontSize: 11.5, height: 1.45),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _times.map((minute) => _TimeChip(
                                minute: minute,
                                onRemove: _times.length > 1
                                    ? () => setState(() => _times.remove(minute))
                                    : null,
                                onTap: () => _editTime(minute),
                              )).toList(),
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: _addTime,
                          icon: const Icon(Icons.add_alarm_rounded, size: 17),
                          label: const Text('Add another time'),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _QuickTime(
                              label: 'Morning 8:00 AM',
                              minute: AppConstants.exampleMorningMinute,
                              existing: _times,
                              onAdd: (m) => setState(() => _times = [..._times, m]..sort()),
                            ),
                            _QuickTime(
                              label: 'Afternoon 2:00 PM',
                              minute: AppConstants.exampleAfternoonMinute,
                              existing: _times,
                              onAdd: (m) => setState(() => _times = [..._times, m]..sort()),
                            ),
                            _QuickTime(
                              label: 'Night 9:00 PM',
                              minute: AppConstants.exampleNightMinute,
                              existing: _times,
                              onAdd: (m) => setState(() => _times = [..._times, m]..sort()),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Repeats on',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          children: List.generate(7, (i) {
                            final day = i + 1;
                            final selected = _weekdays.contains(day);
                            return GestureDetector(
                              onTap: () => setState(() {
                                if (selected) {
                                  if (_weekdays.length > 1) _weekdays.remove(day);
                                } else {
                                  _weekdays.add(day);
                                }
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: selected ? AppColors.purple : AppColors.cardMuted,
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.purple
                                        : AppColors.hairline,
                                  ),
                                ),
                                child: Text(
                                  AppConstants.weekdaysShort[i],
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? AppColors.white
                                        : AppColors.secondaryText,
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _DateField(
                                label: 'Ends',
                                value: _endDate == null
                                    ? 'Ongoing'
                                    : AkashaDates.shortDate(_endDate!),
                                onTap: _pickEndDate,
                              ),
                            ),
                            if (_endDate != null) ...[
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => setState(() => _endDate = null),
                                child: const Text('Clear', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Notes for yourself',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        AkashaTextField(
                          controller: _notes,
                          hint: 'Anything you want to remember',
                          maxLines: 3,
                          minLines: 2,
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _enabled,
                          activeTrackColor: AppColors.primaryPink,
                          onChanged: (v) => setState(() => _enabled = v),
                          title: const Text(
                            'Reminders active',
                            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
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
                                strokeWidth: 2, color: AppColors.white),
                          )
                        : Text(widget.editing == null ? 'Save medicine' : 'Save changes'),
                  ),
                  if (widget.editing != null) ...[
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _delete,
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 17, color: AppColors.danger),
                      label: const Text('Delete medicine',
                          style: TextStyle(color: AppColors.danger)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'If you miss a dose, follow your own prescription or ask your '
                    'pharmacist. Akasha will never advise you to double a dose.',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontSize: 11, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
    );
    if (!mounted || picked == null) return;
    final minute = picked.hour * 60 + picked.minute;
    if (_times.contains(minute)) return;
    setState(() => _times = [..._times, minute]..sort());
  }

  Future<void> _editTime(int minute) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
    );
    if (!mounted || picked == null) return;
    final next = picked.hour * 60 + picked.minute;
    setState(() {
      _times = _times.where((t) => t != minute).toList();
      if (!_times.contains(next)) _times.add(next);
      _times.sort();
    });
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: AkashaDates.today(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (!mounted || picked == null) return;
    setState(() => _endDate = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_times.isEmpty) {
      showAkashaToast(
        context,
        'Please add at least one reminder time.',
        icon: Icons.error_outline_rounded,
        color: AppColors.danger,
      );
      return;
    }
    if (Validators.hasDuplicateMinutes(_times)) {
      showAkashaToast(
        context,
        'Two reminder times are the same. Please adjust them.',
        icon: Icons.error_outline_rounded,
        color: AppColors.danger,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final profile = await ref.read(profileProvider.future);
      final existing = widget.editing;
      final medicine = Medicine(
        id: existing?.id ?? Ids.newId(),
        userId: profile.id,
        name: _name.text.trim(),
        dosage: _dosage.text.trim().isEmpty ? null : _dosage.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        category: _category,
        startDay: existing?.startDay ?? AkashaDates.key(AkashaDates.today()),
        endDay: _endDate == null ? null : AkashaDates.key(_endDate!),
        weekdays: _weekdays.toList()..sort(),
        enabled: _enabled,
        withFood: _withFood.text.trim().isEmpty ? null : _withFood.text.trim(),
        reminderMinutes: _times..sort(),
        createdAt: existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await ref.read(medicineRepositoryProvider).save(medicine);
      final exact = await ref.read(notificationServiceProvider).canScheduleExactAlarms();
      await ref.read(reminderSchedulerProvider).rescheduleAll(exact: exact);
      ref.invalidate(medicinesProvider);
      ref.invalidate(todayDosesProvider);
      ref.invalidate(dataRevisionProvider);
      ref.invalidate(schedulingStatusProvider);
      if (!mounted) return;
      context.pop();
      showAkashaToast(
        context,
        widget.editing == null ? 'Medicine saved ♡' : 'Changes saved',
        icon: Icons.check_circle_rounded,
        color: AppColors.success,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAkashaToast(
        context,
        'Could not save. Please try again.',
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
      title: 'Delete this medicine?',
      message:
          'Future reminders stop. Your past dose history stays in your records.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(medicineRepositoryProvider).softDelete(id);
    final exact = await ref.read(notificationServiceProvider).canScheduleExactAlarms();
    await ref.read(reminderSchedulerProvider).rescheduleAll(exact: exact);
    ref.invalidate(medicinesProvider);
    ref.invalidate(todayDosesProvider);
    ref.invalidate(dataRevisionProvider);
    if (!mounted) return;
    context.pop();
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.minute, required this.onTap, this.onRemove});

  final int minute;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.softPink,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.primaryPink.withValues(alpha: .5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.schedule_rounded, size: 13, color: AppColors.rose),
            const SizedBox(width: 5),
            Text(
              AkashaDates.minutesToLabel(minute),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.darkText,
              ),
            ),
            if (onRemove != null) ...[
              const SizedBox(width: 5),
              GestureDetector(
                onTap: onRemove,
                child: const Icon(Icons.close_rounded,
                    size: 13, color: AppColors.secondaryText),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickTime extends StatelessWidget {
  const _QuickTime({
    required this.label,
    required this.minute,
    required this.existing,
    required this.onAdd,
  });

  final String label;
  final int minute;
  final List<int> existing;
  final ValueChanged<int> onAdd;

  @override
  Widget build(BuildContext context) {
    if (existing.contains(minute)) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () => onAdd(minute),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.cardMuted,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Text(
          '+ $label',
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: AppColors.secondaryText,
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.cardMuted,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_outlined, size: 15, color: AppColors.lavender),
            const SizedBox(width: 7),
            Text(
              '$label: ',
              style: const TextStyle(fontSize: 11.5, color: AppColors.secondaryText),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.darkText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
