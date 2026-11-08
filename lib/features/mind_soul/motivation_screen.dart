import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../data/models/mind_models.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// The message library: browse by category, favourite, shuffle.
final _messagesProvider = FutureProvider<List<MotivationalMessage>>((ref) async {
  ref.watch(dataRevisionProvider);
  return ref.read(motivationRepositoryProvider).all();
});

class MotivationScreen extends ConsumerStatefulWidget {
  const MotivationScreen({super.key});

  @override
  ConsumerState<MotivationScreen> createState() => _MotivationScreenState();
}

class _MotivationScreenState extends ConsumerState<MotivationScreen> {
  MotivationCategory? _category;
  bool _favoritesOnly = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_messagesProvider);

    return GradientScaffold(
      body: Column(
        children: [
          AkashaHeader(
            title: 'Messages for you',
            subtitle: 'Kind words, whenever you need them',
            trailing: HeaderAction(
              icon: Icons.casino_rounded,
              onTap: () => _shuffle(),
            ),
          ),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                _chip(
                  label: 'All',
                  selected: _category == null && !_favoritesOnly,
                  onTap: () => setState(() {
                    _category = null;
                    _favoritesOnly = false;
                  }),
                ),
                _chip(
                  label: '♡ Saved',
                  selected: _favoritesOnly,
                  onTap: () => setState(() {
                    _favoritesOnly = !_favoritesOnly;
                    _category = null;
                  }),
                ),
                ...MotivationCategory.values.map(
                  (c) => _chip(
                    label: c.label,
                    selected: _category == c,
                    onTap: () => setState(() {
                      _category = _category == c ? null : c;
                      _favoritesOnly = false;
                    }),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: async.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => ErrorStateView(
                onRetry: () => ref.invalidate(_messagesProvider),
              ),
              data: (messages) {
                final filtered = messages.where((m) {
                  if (_favoritesOnly && !m.isFavorite) return false;
                  if (_category != null && m.category != _category) return false;
                  return true;
                }).toList();
                if (filtered.isEmpty) {
                  return const EmptyState(
                    icon: Icons.favorite_border_rounded,
                    title: 'Nothing here yet',
                    message:
                        'Tap the heart on a message to keep it here. Saved words are yours.',
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final message = filtered[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: SoftCard(
                        padding: const EdgeInsets.fromLTRB(15, 13, 8, 13),
                        accent: index % 3 == 0 ? AppColors.primaryPink : null,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message.text,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      height: 1.55,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.darkText,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    message.category.label,
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: .4,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                await ref
                                    .read(motivationRepositoryProvider)
                                    .toggleFavorite(message.id, !message.isFavorite);
                                ref.invalidate(_messagesProvider);
                                ref.invalidate(messageOfDayProvider);
                              },
                              visualDensity: VisualDensity.compact,
                              iconSize: 18,
                              icon: Icon(
                                message.isFavorite
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                color: message.isFavorite
                                    ? AppColors.rose
                                    : AppColors.secondaryText.withValues(alpha: .5),
                              ),
                            ),
                          ],
                        ),
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

  Future<void> _shuffle() async {
    final message = await ref.read(motivationRepositoryProvider).nextMessage(
          categories: _category == null ? [] : [_category!],
        );
    if (message == null || !mounted) return;
    await ref.read(motivationRepositoryProvider).markShown(message.id);
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: AppColors.pinkLavender),
                ),
                child: const Icon(Icons.favorite_rounded, color: Colors.white, size: 22),
              ),
              const SizedBox(height: 16),
              Text(
                message.text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.55,
                  fontWeight: FontWeight.w500,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
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
      ),
    );
    ref.invalidate(_messagesProvider);
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? AppColors.purple : Colors.white.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? AppColors.purple : AppColors.hairline),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.darkText,
            ),
          ),
        ),
      ),
    );
  }
}
