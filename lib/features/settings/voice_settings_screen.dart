import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../content/motivation_content.dart';
import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/user_settings.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// Voice preferences with a real, local preview.
class VoiceSettingsScreen extends ConsumerStatefulWidget {
  const VoiceSettingsScreen({super.key});

  @override
  ConsumerState<VoiceSettingsScreen> createState() =>
      _VoiceSettingsScreenState();
}

class _VoiceSettingsScreenState extends ConsumerState<VoiceSettingsScreen> {
  bool _previewing = false;
  bool? _ttsAvailable;

  @override
  void initState() {
    super.initState();
    _checkTts();
  }

  Future<void> _checkTts() async {
    final available = await ref.read(voiceServiceProvider).init();
    if (mounted) setState(() => _ttsAvailable = available);
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsControllerProvider);

    return GradientScaffold(
      body: Column(
        children: [
          const AkashaHeader(
            title: 'Voice',
            subtitle: 'Spoken reminders, in a voice you like',
          ),
          Expanded(
            child: settingsAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => const ErrorStateView(),
              data: (settings) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  children: [
                    if (_ttsAvailable == false)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SoftCard(
                          accent: AppColors.peach,
                          child: const Row(
                            children: [
                              Icon(Icons.record_voice_over_outlined,
                                  size: 18, color: AppColors.warning),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'This phone does not appear to have a usable text-to-'
                                  'speech engine installed, so voice reminders will stay '
                                  'silent. Everything else works normally. You can install '
                                  'one from your device settings.',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.5,
                                    color: AppColors.warmBrown,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            value: settings.voiceEnabled,
                            activeTrackColor: AppColors.primaryPink,
                            onChanged: (value) async {
                              await ref
                                  .read(settingsControllerProvider.notifier)
                                  .update((s) => s.copyWith(voiceEnabled: value));
                            },
                            title: const Text(
                              'Speak my reminders',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Uses the voice engine already on your phone. No audio is '
                              'downloaded or uploaded.',
                              style: TextStyle(fontSize: 11, height: 1.4),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Voice style',
                              style: Theme.of(context).textTheme.labelMedium),
                          const SizedBox(height: 10),
                          ...VoiceProfile.values.map((profile) {
                            final selected = settings.voiceProfile == profile;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 7),
                              child: GestureDetector(
                                onTap: () async {
                                  await ref
                                      .read(settingsControllerProvider.notifier)
                                      .update((s) => s.copyWith(
                                            voiceProfile: profile,
                                            voiceEnabled:
                                                profile != VoiceProfile.disabled,
                                            voicePitch: profile.pitch,
                                            voiceRate: profile.rate,
                                          ));
                                  await ref
                                      .read(voiceServiceProvider)
                                      .applyProfile(profile);
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppColors.softPink
                                        : AppColors.cardMuted,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.primaryPink
                                          : AppColors.hairline,
                                      width: selected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        profile == VoiceProfile.disabled
                                            ? Icons.volume_off_rounded
                                            : Icons.graphic_eq_rounded,
                                        size: 17,
                                        color: selected
                                            ? AppColors.purple
                                            : AppColors.secondaryText,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          profile.label,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: selected
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                            color: AppColors.darkText,
                                          ),
                                        ),
                                      ),
                                      if (selected)
                                        const Icon(Icons.check_circle_rounded,
                                            size: 18, color: AppColors.purple),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: settings.voiceProfile == VoiceProfile.disabled ||
                                      _previewing
                                  ? null
                                  : _preview,
                              icon: _previewing
                                  ? const SizedBox(
                                      height: 14,
                                      width: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.play_circle_outline_rounded,
                                      size: 18),
                              label: const Text('Hear a sample'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    SoftCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.speed_rounded,
                                  size: 16, color: AppColors.lavender),
                              const SizedBox(width: 7),
                              Text('Speed',
                                  style: Theme.of(context).textTheme.titleSmall),
                              const Spacer(),
                              Text(
                                settings.voiceRate < 0.42
                                    ? 'Slow'
                                    : settings.voiceRate > 0.52
                                        ? 'Brisk'
                                        : 'Gentle',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                          Slider(
                            value: settings.voiceRate.clamp(0.3, 0.7),
                            min: 0.3,
                            max: 0.7,
                            divisions: 8,
                            activeColor: AppColors.primaryPink,
                            onChanged: (value) async {
                              await ref
                                  .read(settingsControllerProvider.notifier)
                                  .update((s) => s.copyWith(voiceRate: value));
                            },
                          ),
                          Row(
                            children: [
                              const Icon(Icons.graphic_eq_rounded,
                                  size: 16, color: AppColors.lavender),
                              const SizedBox(width: 7),
                              Text('Tone',
                                  style: Theme.of(context).textTheme.titleSmall),
                            ],
                          ),
                          Slider(
                            value: settings.voicePitch.clamp(0.6, 1.6),
                            min: 0.6,
                            max: 1.6,
                            divisions: 10,
                            activeColor: AppColors.lavender,
                            onChanged: (value) async {
                              await ref
                                  .read(settingsControllerProvider.notifier)
                                  .update((s) => s.copyWith(voicePitch: value));
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Voice availability depends entirely on the engine installed on your '
                      'phone. Some devices offer only one voice, and it may not match every '
                      'style above — the app falls back to the closest available option '
                      'instead of failing.',
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

  Future<void> _preview() async {
    setState(() => _previewing = true);
    final settings = ref.read(settingsControllerProvider).valueOrNull;
    final line = kWaterVoiceLines.first;
    await ref.read(voiceServiceProvider).speak(
          line,
          profile: settings?.voiceProfile,
        );
    await Future.delayed(const Duration(seconds: 4));
    if (mounted) setState(() => _previewing = false);
  }
}
