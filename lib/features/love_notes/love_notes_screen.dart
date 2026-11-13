import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notifications/notification_service.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/mind_models.dart';
import '../../shared/widgets/akasha_text_field.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// LITTLE LOVE NOTES — warm messages, entirely local by default.
class LoveNotesScreen extends ConsumerStatefulWidget {
  const LoveNotesScreen({super.key});

  @override
  ConsumerState<LoveNotesScreen> createState() => _LoveNotesScreenState();
}

class _LoveNotesScreenState extends ConsumerState<LoveNotesScreen> {
  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(loveNotesProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;

    return GradientScaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: FloatingActionButton.extended(
          onPressed: () => _openEditor(),
          backgroundColor: AppColors.rose,
          foregroundColor: AppColors.white,
          icon: const Icon(Icons.edit_rounded, size: 17),
          label: const Text(
            'Write a note',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      body: Column(
        children: [
          const AkashaHeader(
            title: 'Little love notes',
            subtitle: 'Warm words to find at the right moment',
          ),
          Expanded(
            child: notesAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => ErrorStateView(
                onRetry: () => ref.invalidate(loveNotesProvider),
              ),
              data: (notes) {
                if (notes.isEmpty) {
                  return EmptyState(
                    icon: Icons.mark_email_unread_outlined,
                    title: 'No notes yet',
                    message:
                        'Write something kind that Akasha should find later. She can '
                        'read it whenever she opens this screen.',
                    actionLabel: 'Write the first one',
                    onAction: () => _openEditor(),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
                  children: [
                    if (settings != null)
                      SoftCard(
                        accent: AppColors.peach,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.lock_outline_rounded,
                                size: 15, color: AppColors.warning),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Notes are stored on this phone only. Nothing is sent '
                                'to anyone unless you turn on cloud sync yourself.',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  height: 1.5,
                                  color: AppColors.warmBrown,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    ...notes.map((note) => Padding(
                          padding: const EdgeInsets.only(bottom: 11),
                          child: _NoteCard(
                            note: note,
                            onToggle: (value) async {
                              await ref
                                  .read(loveNoteRepositoryProvider)
                                  .setEnabled(note.id, value);
                              ref.invalidate(loveNotesProvider);
                              await _reschedule(ref);
                            },
                            onFavorite: () async {
                              await ref
                                  .read(loveNoteRepositoryProvider)
                                  .toggleFavorite(note.id, !note.isFavorite);
                              ref.invalidate(loveNotesProvider);
                            },
                            onEdit: () => _openEditor(note: note),
                            onDelete: () async {
                              final ok = await showAkashaConfirm(
                                context,
                                title: 'Delete this note?',
                                message: 'It will no longer be delivered.',
                                confirmLabel: 'Delete',
                                destructive: true,
                              );
                              if (!ok) return;
                              await ref
                                  .read(loveNoteRepositoryProvider)
                                  .softDelete(note.id);
                              ref.invalidate(loveNotesProvider);
                              await _reschedule(ref);
                            },
                          ),
                        )),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor({LoveNote? note}) async {
    final textController = TextEditingController(text: note?.text ?? '');
    final authorController = TextEditingController(
      text: note?.author ?? 'Someone who cares',
    );
    int minute = note?.minuteOfDay ?? 21 * 60;
    bool enabled = note?.enabled ?? true;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note == null ? 'A new note' : 'Edit note',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontSize: 19),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Write it the way you would say it out loud.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  AkashaTextField(
                    controller: textController,
                    hint: 'Keep smiling, Akasha. Your happiness matters.',
                    maxLines: 4,
                    minLines: 3,
                    maxLength: 280,
                  ),
                  const SizedBox(height: 12),
                  AkashaTextField(
                    controller: authorController,
                    hint: 'From (shown under the note)',
                    icon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 15, color: AppColors.lavender),
                      const SizedBox(width: 7),
                      Text(
                        'Deliver at ${AkashaDates.minutesToLabel(minute)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.darkText,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay(
                              hour: minute ~/ 60,
                              minute: minute % 60,
                            ),
                          );
                          if (picked != null) {
                            setSheetState(() {
                              minute = picked.hour * 60 + picked.minute;
                            });
                          }
                        },
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: const Text('Change', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: enabled,
                    activeTrackColor: AppColors.primaryPink,
                    onChanged: (v) => setSheetState(() => enabled = v),
                    title: const Text(
                      'Deliver this note',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (textController.text.trim().isEmpty) return;
                        final profile = await ref.read(profileProvider.future);
                        await ref.read(loveNoteRepositoryProvider).save(
                              id: note?.id,
                              userId: profile.id,
                              text: textController.text,
                              author: authorController.text,
                              minuteOfDay: minute,
                              enabled: enabled,
                            );
                        await _reschedule(ref);
                        ref.invalidate(loveNotesProvider);
                        ref.invalidate(dataRevisionProvider);
                        if (context.mounted) Navigator.pop(context, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.rose,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(note == null ? 'Save note' : 'Save changes'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    // The sheet is closed at this point; its controllers are local and must be
    // disposed by hand (nothing in the widget tree owns them).
    textController.dispose();
    authorController.dispose();

    if (saved == true && mounted) {
      showAkashaToast(
        context,
        'Note saved ♡',
        icon: Icons.favorite_rounded,
        color: AppColors.rose,
      );
    }
  }

  static Future<void> _reschedule(WidgetRef ref) async {
    final exact = await ref.read(notificationServiceProvider).canScheduleExactAlarms();
    await ref.read(reminderSchedulerProvider).rescheduleAll(exact: exact);
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.onToggle,
    required this.onFavorite,
    required this.onEdit,
    required this.onDelete,
  });

  final LoveNote note;
  final ValueChanged<bool> onToggle;
  final VoidCallback onFavorite;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: note.enabled
              ? AppColors.noteCream
              : [AppColors.white, AppColors.white],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: note.enabled
              ? AppColors.primaryPink.withValues(alpha: .35)
              : AppColors.hairline,
        ),
        boxShadow: note.enabled ? AppShadows.soft : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 8),
                child: Icon(Icons.favorite_rounded, size: 13, color: AppColors.rose),
              ),
              Expanded(
                child: Text(
                  note.text,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    fontWeight: FontWeight.w500,
                    color: AppColors.darkText,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '— ${note.author}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  color: AppColors.secondaryText,
                ),
              ),
              const SizedBox(width: 8),
              if (note.minuteOfDay != null)
                Text(
                  '· ${AkashaDates.minutesToLabel(note.minuteOfDay!)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.secondaryText,
                  ),
                ),
              const Spacer(),
              IconButton(
                onPressed: onFavorite,
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                icon: Icon(
                  note.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: note.isFavorite ? AppColors.gold : AppColors.secondaryText,
                ),
              ),
              Switch.adaptive(
                value: note.enabled,
                activeTrackColor: AppColors.primaryPink,
                onChanged: onToggle,
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded,
                    size: 16, color: AppColors.secondaryText),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit note')),
                  PopupMenuItem(value: 'delete', child: Text('Delete note')),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
