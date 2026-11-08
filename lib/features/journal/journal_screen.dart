import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
import '../../shared/widgets/app_dialog.dart';

/// Private journal list with search and mood filtering.
final _journalQueryProvider = StateProvider<String>((ref) => '');
final _journalMoodProvider = StateProvider<MoodType?>((ref) => null);

final journalEntriesProvider = FutureProvider<List<JournalEntry>>((ref) async {
  ref.watch(dataRevisionProvider);
  final query = ref.watch(_journalQueryProvider);
  final mood = ref.watch(_journalMoodProvider);
  final profile = await ref.watch(profileProvider.future);
  return ref.read(mindRepositoryProvider).journalEntries(
        profile.id,
        query: query.isEmpty ? null : query,
        mood: mood,
      );
});

class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(journalEntriesProvider);
    final moodFilter = ref.watch(_journalMoodProvider);

    return GradientScaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: FloatingActionButton.extended(
          onPressed: () => context.push(Routes.journalEditor),
          backgroundColor: AppColors.purple,
          foregroundColor: AppColors.white,
          icon: const Icon(Icons.edit_rounded, size: 18),
          label: const Text(
            'Write',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      body: Column(
        children: [
          AkashaHeader(
            title: 'Private journal',
            subtitle: 'Only you can read this',
            trailing: HeaderAction(
              icon: _searching ? Icons.close_rounded : Icons.search_rounded,
              onTap: () => setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _search.clear();
                  ref.read(_journalQueryProvider.notifier).state = '';
                }
              }),
            ),
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: AkashaTextField(
                controller: _search,
                hint: 'Search your entries',
                icon: Icons.search_rounded,
                autofocus: true,
                onChanged: (v) =>
                    ref.read(_journalQueryProvider.notifier).state = v,
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _moodChip('All', null, moodFilter),
                ...MoodType.values.map((m) => _moodChip(m.label, m, moodFilter)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: entriesAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => ErrorStateView(
                onRetry: () => ref.invalidate(journalEntriesProvider),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return EmptyState(
                    icon: Icons.auto_stories_outlined,
                    title: _search.text.isEmpty
                        ? 'A blank page, waiting for you'
                        : 'Nothing matched',
                    message: _search.text.isEmpty
                        ? 'Write what happened today, what you are thinking, or just '
                            'how the light looked. It does not need to be tidy.'
                        : 'Try a different word, or clear the filter.',
                    actionLabel: _search.text.isEmpty ? 'Write something' : null,
                    onAction: _search.text.isEmpty
                        ? () => context.push(Routes.journalEditor)
                        : null,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 110),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _JournalCard(
                        entry: entry,
                        onTap: () => context.push(
                          Routes.journalEditor,
                          extra: JournalEditorArg(entry.id),
                        ),
                        onDelete: () async {
                          final ok = await showAkashaConfirm(
                            context,
                            title: 'Delete this entry?',
                            message: 'This cannot be undone.',
                            confirmLabel: 'Delete',
                            destructive: true,
                          );
                          if (!ok) return;
                          await ref
                              .read(mindRepositoryProvider)
                              .deleteJournal(entry.id);
                          ref.invalidate(dataRevisionProvider);
                          ref.invalidate(journalEntriesProvider);
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _moodChip(String label, MoodType? mood, MoodType? selected) {
    final isSelected = selected == mood;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: GestureDetector(
        onTap: () => ref.read(_journalMoodProvider.notifier).state = mood,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.purple : AppColors.white.withValues(alpha: .7),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected ? AppColors.purple : AppColors.hairline,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppColors.white : AppColors.darkText,
            ),
          ),
        ),
      ),
    );
  }
}

class _JournalCard extends StatelessWidget {
  const _JournalCard({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  final JournalEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final preview = entry.body.length > 140
        ? '${entry.body.substring(0, 140).trim()}…'
        : entry.body;
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(15, 13, 6, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 3,
            height: 46,
            decoration: BoxDecoration(
              color: moodColor(entry.mood).withValues(alpha: .6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.title?.isNotEmpty == true
                            ? entry.title!
                            : AkashaDates.prettyDate(
                                AkashaDates.parseKey(entry.dayKey),
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.darkText,
                        ),
                      ),
                    ),
                    if (entry.isPinned)
                      const Icon(Icons.push_pin_rounded,
                          size: 12, color: AppColors.warning),
                    Text(
                      DateFormat('h:mm a').format(entry.createdLocal),
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppColors.secondaryText,
                  ),
                ),
                if (entry.mood != null) ...[
                  const SizedBox(height: 6),
                  StatusPill(
                    label: entry.mood!.label,
                    color: moodColor(entry.mood),
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded,
                size: 16, color: AppColors.secondaryText),
            onSelected: (value) {
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete entry')),
            ],
          ),
        ],
      ),
    );
  }
}
