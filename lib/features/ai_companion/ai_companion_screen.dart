import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/id.dart';
import '../../data/models/mind_models.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/states.dart';
import 'ai_service.dart';

/// OPTIONAL AI wellness companion.
///
/// Disabled by default, requires explicit consent, and never claims to be a
/// therapist. When no backend endpoint is configured (the default build) it
/// uses a local reflective responder — clearly labelled as "simpler reflection".
class AiCompanionScreen extends ConsumerStatefulWidget {
  const AiCompanionScreen({super.key});

  @override
  ConsumerState<AiCompanionScreen> createState() => _AiCompanionScreenState();
}

class _AiCompanionScreenState extends ConsumerState<AiCompanionScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final List<AiMessage> _messages = [];
  bool _sending = false;
  bool _loading = true;

  late final AiCompanionService _service = AiCompanionService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // A failure here must not leave the screen stuck on its spinner forever
    // (the profile provider can only fail if the database itself is broken, in
    // which case saying so is better than an endless loading state).
    try {
      final profile = await ref.read(profileProvider.future);
      final rows = await AppDatabase.instance.db.query(
        'ai_messages',
        where: 'user_id = ? AND deleted_at IS NULL',
        whereArgs: [profile.id],
        orderBy: 'created_local ASC',
        limit: 200,
      );
      if (!mounted) return;
      setState(() {
        _messages.addAll(rows.map(AiMessage.fromRow));
        _loading = false;
      });
      if (_messages.isEmpty) {
        await _seedGreeting(profile.id);
      } else {
        _scrollToBottom();
      }
    } catch (e, st) {
      debugPrint('AKASHA: companion history failed to load: $e\n$st');
      if (!mounted) return;
      setState(() => _loading = false);
      showAkashaToast(
        context,
        'Your saved conversation could not be opened just now.',
        icon: Icons.info_outline_rounded,
        color: AppColors.warning,
      );
    }
  }

  Future<void> _seedGreeting(String userId) async {
    final greeting = AiMessage(
      id: Ids.newId(),
      userId: userId,
      role: 'assistant',
      content: 'Hello Akasha. I am here if you want to untangle something, or just '
          'put a thought somewhere safe. What is on your mind?',
      createdLocal: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await AppDatabase.instance.db.insert('ai_messages', greeting.toRow());
    if (!mounted) return;
    setState(() => _messages.add(greeting));
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final profile = await ref.read(profileProvider.future);

    final userMessage = AiMessage(
      id: Ids.newId(),
      userId: profile.id,
      role: 'user',
      content: text,
      createdLocal: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await AppDatabase.instance.db.insert('ai_messages', userMessage.toRow());
    if (!mounted) return;
    setState(() {
      _messages.add(userMessage);
      _controller.clear();
      _sending = true;
    });
    _scrollToBottom();

    final reply = await _service.send(
      message: text,
      history: _messages
          .take(12)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList(),
    );

    final assistantMessage = AiMessage(
      id: Ids.newId(),
      userId: profile.id,
      role: 'assistant',
      content: reply.note == null ? reply.text : '${reply.text}\n\n${reply.note}',
      createdLocal: DateTime.now(),
      flagged: reply.isCrisis,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await AppDatabase.instance.db.insert('ai_messages', assistantMessage.toRow());
    if (!mounted) return;
    setState(() {
      _messages.add(assistantMessage);
      _sending = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      body: Column(
        children: [
          const AkashaHeader(
            title: 'Wellness companion',
            subtitle: 'A gentle conversation, never a diagnosis',
          ),
          if (!_service.isConfigured)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.softPeach,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 14, color: AppColors.warning),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Simpler local reflection is active. To enable the full '
                        'companion, configure a secure backend endpoint (see '
                        'docs/FIREBASE_SETUP.md). No API key is ever stored in the app.',
                        style: TextStyle(
                          fontSize: 10.5,
                          height: 1.45,
                          color: AppColors.warmBrown,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: LoadingDots())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    itemCount: _messages.length + (_sending ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const _TypingBubble();
                      }
                      return _Bubble(message: _messages[index]);
                    },
                  ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(
              16,
              10,
              16,
              14 + MediaQuery.of(context).viewInsets.bottom,
            ),
            decoration: BoxDecoration(
              color: AppColors.white.withValues(alpha: .9),
              border: const Border(
                top: BorderSide(color: AppColors.hairline),
              ),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.cardMuted,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.hairline),
                        ),
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            color: AppColors.darkText,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Say anything, Akasha…',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 13,
                            ),
                          ),
                          onSubmitted: (_) => _send(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _sending ? null : _send,
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: AppColors.pinkLavender),
                          shape: BoxShape.circle,
                          boxShadow: AppShadows.tinted(AppColors.primaryPink),
                        ),
                        child: _sending
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.white,
                                ),
                              )
                            : const Icon(Icons.arrow_upward_rounded,
                                size: 20, color: AppColors.white),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'This is a wellness companion, not a therapist or a doctor. In an '
                  'emergency, contact local services.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 9.5,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * .78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(colors: AppColors.pinkLavender)
              : null,
          color: isUser ? null : AppColors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: isUser ? null : Border.all(color: AppColors.hairline),
          boxShadow: isUser ? null : AppShadows.soft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.flagged) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.favorite_rounded, size: 11, color: AppColors.danger),
                    SizedBox(width: 5),
                    Text(
                      'Please reach out to a real person today',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Text(
              message.content,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.55,
                color: isUser ? AppColors.white : AppColors.darkText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AkashaDates.relativeTime(message.createdLocal),
              style: TextStyle(
                fontSize: 9,
                color: isUser
                    ? AppColors.white.withValues(alpha: .75)
                    : AppColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.hairline),
        ),
        child: const LoadingDots(size: 6),
      ),
    );
  }
}
