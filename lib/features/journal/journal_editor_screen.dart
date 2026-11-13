import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/mind_models.dart';
import '../../shared/widgets/akasha_text_field.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/states.dart';
import '../dashboard/widgets/dashboard_cards.dart';
import 'journal_screen.dart';

/// Write or edit a journal entry.
///
/// The five prompts from the spec are offered as gentle starters — tapping one
/// inserts the question as a heading so the page never feels like a blank wall.
class JournalEditorScreen extends ConsumerStatefulWidget {
  const JournalEditorScreen({super.key, this.entryId});

  final String? entryId;

  @override
  ConsumerState<JournalEditorScreen> createState() => _JournalEditorScreenState();
}

class _JournalEditorScreenState extends ConsumerState<JournalEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _tag = TextEditingController();
  final _focus = FocusNode();
  MoodType? _mood;
  List<String> _tags = [];
  bool _pinned = false;
  bool _loading = true;
  bool _saving = false;

  static const List<String> _prompts = [
    'What happened today?',
    'What am I thinking?',
    'What am I feeling?',
    'What is worrying me?',
    'What can I do about it?',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.entryId;
    if (id != null) {
      final entry = await ref.read(mindRepositoryProvider).journalById(id);
      if (entry != null) {
        _title.text = entry.title ?? '';
        _body.text = entry.body;
        _mood = entry.mood;
        _tags = [...entry.tags];
        _pinned = entry.isPinned;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _tag.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const GradientScaffold(body: Center(child: LoadingDots()));
    }
    return GradientScaffold(
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          AkashaHeader(
            title: widget.entryId == null ? 'New entry' : 'Edit entry',
            subtitle: AkashaDates.prettyDate(DateTime.now()),
            trailing: TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
              children: [
                TextField(
                  controller: _title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: AppColors.darkText,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'A title, if you want one',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 8),
                Container(height: 1, color: AppColors.hairline),
                const SizedBox(height: 12),
                TextField(
                  controller: _body,
                  focusNode: _focus,
                  maxLines: null,
                  minLines: 12,
                  maxLength: AppConstants.journalMaxLength,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.75,
                    color: AppColors.darkText,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Whatever is on your mind. No one else will read this.',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Need a starting point?',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: _prompts
                      .map((p) => GestureDetector(
                            onTap: () {
                              final existing = _body.text;
                              final text = existing.isEmpty
                                  ? '$p\n'
                                  : '$existing${existing.endsWith('\n') ? '' : '\n\n'}$p\n';
                              _body.text = text;
                              _body.selection = TextSelection.fromPosition(
                                TextPosition(offset: text.length),
                              );
                              _focus.requestFocus();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 11, vertical: 7),
                              decoration: BoxDecoration(
                                color: AppColors.white.withValues(alpha: .8),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppColors.hairline),
                              ),
                              child: Text(
                                p,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 20),
                Text('How did this feel?', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: MoodType.values.map((mood) {
                    final selected = _mood == mood;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _mood = selected ? null : mood),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 11, vertical: 7),
                        decoration: BoxDecoration(
                          color: selected
                              ? moodColor(mood).withValues(alpha: .18)
                              : AppColors.white.withValues(alpha: .7),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: selected
                                ? moodColor(mood)
                                : AppColors.hairline,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(moodIcon(mood), size: 12, color: moodColor(mood)),
                            const SizedBox(width: 4),
                            Text(
                              mood.label,
                              style: TextStyle(
                                fontSize: 11,
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
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: AkashaTextField(
                        controller: _tag,
                        hint: 'Add a tag (optional)',
                        icon: Icons.sell_outlined,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (v) {
                          final value = v.trim();
                          if (value.isEmpty) return;
                          setState(() {
                            _tags = [..._tags, value];
                            _tag.clear();
                          });
                        },
                      ),
                    ),
                  ],
                ),
                if (_tags.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _tags
                        .map((t) => Chip(
                              label: Text(t),
                              onDeleted: () =>
                                  setState(() => _tags.remove(t)),
                              deleteIcon: const Icon(Icons.close_rounded, size: 13),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _pinned,
                  activeTrackColor: AppColors.primaryPink,
                  onChanged: (v) => setState(() => _pinned = v),
                  title: const Text(
                    'Pin to the top',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
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
                      : const Text('Save entry'),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Your journal is stored on this phone. It is never shared, and it '
                    'is not used for advertising.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10.5,
                          height: 1.5,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final body = _body.text.trim();
    if (body.isEmpty) {
      showAkashaToast(
        context,
        'Write a little something first ♡',
        icon: Icons.edit_note_rounded,
        color: AppColors.warning,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final profile = await ref.read(profileProvider.future);
      await ref.read(mindRepositoryProvider).saveJournal(
            id: widget.entryId,
            userId: profile.id,
            title: _title.text.trim().isEmpty ? null : _title.text.trim(),
            body: body,
            mood: _mood,
            tags: _tags,
            isPinned: _pinned,
          );
      ref.invalidate(dataRevisionProvider);
      ref.invalidate(journalEntriesProvider);
      if (!mounted) return;
      context.pop();
      showAkashaToast(
        context,
        'Saved. Thank you for taking this time.',
        icon: Icons.favorite_rounded,
        color: AppColors.rose,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAkashaToast(
        context,
        'Could not save that entry.',
        icon: Icons.error_outline_rounded,
        color: AppColors.danger,
      );
    }
  }
}
