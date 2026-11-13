import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../features/sync/cloud_backend.dart';
import '../../features/sync/sync_service.dart';
import '../../shared/widgets/akasha_text_field.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// Optional cloud backup. Fully functional offline-first: turning this on only
/// adds a queue, never a dependency.
class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _showForm = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsControllerProvider);

    return GradientScaffold(
      body: Column(
        children: [
          const AkashaHeader(
            title: 'Cloud sync',
            subtitle: 'Optional backup across devices',
          ),
          Expanded(
            child: settingsAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => const ErrorStateView(),
              data: (settings) {
                final sync = ref.read(syncServiceProvider);
                final configured = sync.cloudConfigured;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  children: [
                    SoftCard(
                      accent: AppColors.lavender,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                settings.syncEnabled
                                    ? Icons.cloud_done_rounded
                                    : Icons.cloud_off_rounded,
                                size: 20,
                                color: settings.syncEnabled
                                    ? AppColors.success
                                    : AppColors.secondaryText,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  settings.syncEnabled && configured
                                      ? 'Sync is on'
                                      : settings.syncEnabled
                                          ? 'Sync is on, but not configured'
                                          : 'Everything stays on this phone',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontSize: 14.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            !configured
                                ? 'This build has no Firebase configuration, so cloud '
                                    'sync is inactive. Everything else works exactly the '
                                    'same, fully offline. See docs/FIREBASE_SETUP.md to '
                                    'connect your own project.'
                                : settings.syncEnabled
                                    ? 'Changes are queued locally and uploaded when you '
                                        'have a connection. Nothing is ever lost, and a '
                                        'newer record is never overwritten by an older one.'
                                    : 'Turn sync on to back up your records to your own '
                                        'account. Local data remains the source of truth.',
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.55,
                              color: AppColors.secondaryText,
                            ),
                          ),
                          if (settings.lastSyncAt != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Last successful sync: '
                              '${AkashaDates.relativeTime(settings.lastSyncAt!)}',
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ],
                          if (configured) ...[
                            const SizedBox(height: 12),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              value: settings.syncEnabled,
                              activeTrackColor: AppColors.primaryPink,
                              onChanged: (value) async {
                                if (value) {
                                  final ok = await showAkashaConfirm(
                                    context,
                                    title: 'Turn on cloud sync?',
                                    message:
                                        'Your records — including journal entries — will be '
                                        'uploaded to your own authenticated account. Only you '
                                        'can read them. You can turn this off and delete the '
                                        'cloud copy at any time.',
                                    confirmLabel: 'I agree, turn it on',
                                    icon: Icons.shield_outlined,
                                  );
                                  if (!ok) return;
                                }
                                await ref
                                    .read(syncServiceProvider)
                                    .enableSync(enable: value);
                                ref.invalidate(settingsProvider);
                                if (!mounted) return;
                                setState(() {});
                              },
                              title: const Text(
                                'Enable cloud sync',
                                style: TextStyle(
                                    fontSize: 13.5, fontWeight: FontWeight.w600),
                              ),
                            ),
                            if (settings.syncEnabled && !_showForm) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: _busy ? null : _syncNow,
                                      child: _busy
                                          ? const SizedBox(
                                              height: 16,
                                              width: 16,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2),
                                            )
                                          : const Text('Sync now'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () =>
                                          setState(() => _showForm = true),
                                      child: const Text('Account'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      SoftCard(
                        child: Text(
                          _message!,
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: AppColors.darkText,
                          ),
                        ),
                      ),
                    ],
                    if (configured && _showForm) ...[
                      const SizedBox(height: 14),
                      SoftCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your account',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Used only to scope your own records. Your password is '
                              'handled by Firebase Authentication and is never stored by '
                              'this app.',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.45,
                                color: AppColors.secondaryText,
                              ),
                            ),
                            const SizedBox(height: 12),
                            AkashaTextField(
                              controller: _email,
                              label: 'Email',
                              keyboardType: TextInputType.emailAddress,
                              icon: Icons.alternate_email_rounded,
                            ),
                            const SizedBox(height: 10),
                            AkashaTextField(
                              controller: _password,
                              label: 'Password',
                              obscure: true,
                              icon: Icons.lock_outline_rounded,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _authenticate(signUp: false),
                                    child: const Text('Sign in'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _authenticate(signUp: true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.purple,
                                      minimumSize: const Size.fromHeight(48),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: const Text('Create'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (configured && settings.syncEnabled) ...[
                      const SizedBox(height: 14),
                      SoftCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: SectionTile(
                          icon: Icons.delete_outline_rounded,
                          title: 'Delete my cloud data',
                          subtitle: 'Removes the backup (local data stays)',
                          iconColor: AppColors.danger,
                          onTap: () async {
                            final ok = await showAkashaConfirm(
                              context,
                              title: 'Delete your cloud backup?',
                              message:
                                  'Your records on this phone stay exactly where they are. '
                                  'The cloud copy under your account will be removed.',
                              confirmLabel: 'Delete cloud data',
                              destructive: true,
                            );
                            if (!ok || !mounted) return;
                            setState(() => _busy = true);
                            try {
                              await ref
                                  .read(syncServiceProvider)
                                  .deleteCloudAccount();
                              if (!mounted) return;
                              setState(() {
                                _busy = false;
                                _message = 'Cloud data removed.';
                              });
                              ref.invalidate(settingsProvider);
                            } catch (e) {
                              setState(() {
                                _busy = false;
                                _message =
                                    'Could not reach the cloud. Nothing was changed.';
                              });
                            }
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Sync is deliberately conservative: local writes always succeed '
                      'first, uploads retry with backoff, duplicates are prevented by '
                      'deterministic record ids, and delete tombstones propagate so a '
                      'removal on one device is respected on another.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            height: 1.55,
                          ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    final state = await ref.read(syncServiceProvider).syncNow();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = state.message ??
          (state.phase == SyncPhase.idle
              ? 'Synced ${state.pushedRecords} change(s), ${state.pulledRecords} received.'
              : 'Sync paused. Your changes are safe on this phone.');
    });
  }

  Future<void> _authenticate({required bool signUp}) async {
    setState(() => _busy = true);
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.length < 6) {
      setState(() {
        _busy = false;
        _message = 'Please enter an email and a password of at least 6 characters.';
      });
      return;
    }
    final sync = ref.read(syncServiceProvider);
    final result = signUp
        ? await sync.signUp(email, password)
        : await sync.signIn(email, password);
    if (!mounted) return;
    if (!result.success) {
      setState(() {
        _busy = false;
        _message = result.error ?? 'Could not sign in right now.';
      });
      return;
    }
    await sync.syncNow();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _showForm = false;
      _message = 'Signed in as ${result.email}. Your records will sync now.';
    });
    ref.invalidate(settingsProvider);
  }
}
