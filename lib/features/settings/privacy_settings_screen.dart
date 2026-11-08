import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../content/motivation_content.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// Privacy and security controls, written in plain language.
class PrivacySettingsScreen extends ConsumerStatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  ConsumerState<PrivacySettingsScreen> createState() =>
      _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState
    extends ConsumerState<PrivacySettingsScreen> {
  bool? _biometricsAvailable;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final available = await ref.read(lockServiceProvider).isBiometricAvailable();
    if (mounted) setState(() => _biometricsAvailable = available);
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsControllerProvider);

    return GradientScaffold(
      body: Column(
        children: [
          const AkashaHeader(
            title: 'Privacy',
            subtitle: 'Your data belongs to you',
          ),
          Expanded(
            child: settingsAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => const ErrorStateView(),
              data: (settings) => ListView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                children: [
                  const SectionHeader(
                      title: 'What AKASHA stores', icon: Icons.storage_rounded),
                  SoftCard(
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PrivacyLine(
                          icon: Icons.phone_android_rounded,
                          title: 'Everything essential lives on this phone',
                          body:
                              'Water logs, medicines, journal entries, moods, gratitude, '
                              'breathing sessions and love notes are stored in a local '
                              'SQLite database inside the app\'s private storage.',
                        ),
                        SizedBox(height: 12),
                        _PrivacyLine(
                          icon: Icons.cloud_off_rounded,
                          title: 'Nothing leaves unless you turn sync on',
                          body:
                              'Cloud backup is off by default. If you enable it, records '
                              'sync only to your own authenticated account.',
                        ),
                        SizedBox(height: 12),
                        _PrivacyLine(
                          icon: Icons.block_rounded,
                          title: 'No ads, no trackers, no analytics',
                          body:
                              'There is no advertising SDK and no behavioural profiling. '
                              'Your wellness data is never used for marketing.',
                        ),
                        SizedBox(height: 12),
                        _PrivacyLine(
                          icon: Icons.location_off_rounded,
                          title: 'No location, microphone or contacts',
                          body:
                              'The app never requests location, never records audio and '
                              'never reads your contacts.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionHeader(
                      title: 'App lock', icon: Icons.fingerprint_rounded),
                  SoftCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: SwitchListTile.adaptive(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      value: settings.appLockEnabled,
                      activeTrackColor: AppColors.primaryPink,
                      onChanged: _biometricsAvailable == false
                          ? null
                          : (value) async {
                              if (value) {
                                final ok = await ref
                                    .read(lockServiceProvider)
                                    .authenticate(
                                      reason: 'Confirm it is you to enable the lock',
                                    );
                                if (!ok) return;
                              }
                              await ref
                                  .read(settingsControllerProvider.notifier)
                                  .update((s) => s.copyWith(appLockEnabled: value));
                            },
                      title: const Text(
                        'Lock AKASHA with my fingerprint or device PIN',
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _biometricsAvailable == false
                            ? 'No biometric or device lock is available on this phone.'
                            : 'The app re-locks 2 minutes after you leave it. Biometric '
                                'data never leaves your device — Android handles it.',
                        style: const TextStyle(fontSize: 11, height: 1.4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionHeader(
                      title: 'AI processing', icon: Icons.psychology_alt_rounded),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          settings.aiConsentGiven
                              ? 'You have consented to AI processing.'
                              : 'AI features are off and no messages are processed.',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.darkText,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'When enabled, the messages you type are sent to a secure '
                          'backend to generate a reply. No API key is stored in the app. '
                          'Conversations stay on this device unless you also enable cloud '
                          'sync. You can withdraw consent at any time by turning the '
                          'companion off.',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.55,
                            color: AppColors.secondaryText,
                          ),
                        ),
                        if (settings.aiConsentGiven) ...[
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: () async {
                              final ok = await showAkashaConfirm(
                                context,
                                title: 'Withdraw AI consent?',
                                message:
                                    'The companion will be disabled and your saved '
                                    'conversation will stop being available in the app.',
                                confirmLabel: 'Withdraw',
                                destructive: true,
                              );
                              if (!ok) return;
                              await ref
                                  .read(settingsControllerProvider.notifier)
                                  .update((s) => s.copyWith(
                                        aiEnabled: false,
                                        aiConsentGiven: false,
                                      ));
                            },
                            child: const Text('Withdraw consent'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const SectionHeader(
                      title: 'If you need real support',
                      icon: Icons.volunteer_activism_rounded),
                  SoftCard(
                    accent: AppColors.primaryPink,
                    child: Text(
                      kCrisisSupportMessage,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: AppColors.darkText,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SoftCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: SectionTile(
                      icon: Icons.description_outlined,
                      title: 'Full privacy policy',
                      subtitle: 'docs/PRIVACY.md in the project',
                      onTap: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Privacy policy (summary)'),
                          content: const SingleChildScrollView(
                            child: Text(
                              'AKASHA is a personal wellness application. All essential '
                              'data is stored locally on your device in an app-private '
                              'database.\n\n'
                              'Cloud synchronisation is optional, requires your explicit '
                              'consent, and stores data only under your own authenticated '
                              'account. Journal entries are never accessible to other '
                              'users.\n\n'
                              'There is no advertising, no third-party analytics and no '
                              'sale or sharing of health or medication data. The app does '
                              'not access your location, microphone or contacts.\n\n'
                              'AI features are opt-in. When enabled, only the messages '
                              'you send are transmitted to a secure backend to generate a '
                              'reply. API keys are held server-side and never shipped in '
                              'the app.\n\n'
                              'You can export your data, delete individual records, or '
                              'erase everything from this device at any time in Settings.',
                              style: TextStyle(fontSize: 13, height: 1.6),
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Close'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrivacyLine extends StatelessWidget {
  const _PrivacyLine({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.purple),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkText,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
