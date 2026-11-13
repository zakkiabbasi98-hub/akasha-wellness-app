import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/user_settings.dart';
import '../../shared/widgets/akasha_text_field.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/app_nav.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/soft_card.dart';
import '../../shared/widgets/states.dart';

/// The settings hub. Every control writes to the database immediately — there
/// is no "apply" step that could lose a change.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsControllerProvider);
    final profileAsync = ref.watch(profileProvider);

    return GradientScaffold(
      body: Column(
        children: [
          const AkashaHeader(title: 'Settings', subtitle: 'Everything, your way'),
          Expanded(
            child: settingsAsync.when(
              loading: () => const Center(child: LoadingDots()),
              error: (_, __) => const ErrorStateView(),
              data: (settings) => profileAsync.when(
                loading: () => const Center(child: LoadingDots()),
                error: (_, __) => const ErrorStateView(),
                data: (profile) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                    children: [
                      // ── Profile ──────────────────────────────────────────
                      const SectionHeader(title: 'You', icon: Icons.person_rounded),
                      SoftCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            SectionTile(
                              icon: Icons.badge_outlined,
                              title: 'Name',
                              subtitle: profile.displayName,
                              onTap: () async {
                                final name = await showAkashaTextPrompt(
                                  context,
                                  title: 'What should I call you?',
                                  initialValue: profile.displayName,
                                  hint: 'Your name',
                                );
                                if (name == null) return;
                                await ref
                                    .read(profileRepositoryProvider)
                                    .updateProfile(profile.copyWith(displayName: name));
                                ref.invalidate(profileProvider);
                                ref.invalidate(dataRevisionProvider);
                              },
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            SectionTile(
                              icon: Icons.water_drop_outlined,
                              title: 'Daily water goal',
                              subtitle: '${settings.waterTargetMl} ml '
                                  '(${(settings.waterTargetMl / 1000).toStringAsFixed(1)} L)',
                              onTap: () => _editWaterTarget(context, ref, settings),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            SectionTile(
                              icon: Icons.local_drink_outlined,
                              title: 'Glass sizes',
                              subtitle:
                                  '${settings.smallGlassMl} / ${settings.glassSizeMl} / ${settings.largeGlassMl} ml',
                              onTap: () => _editGlassSizes(context, ref, settings),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            SectionTile(
                              icon: Icons.palette_outlined,
                              title: 'Appearance',
                              subtitle: switch (settings.themeMode) {
                                AppThemeMode.light => 'Light — always',
                                AppThemeMode.dark => 'Dark',
                                AppThemeMode.system => 'Follow the system',
                              },
                              onTap: () => _pickTheme(context, ref, settings),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── Reminders ────────────────────────────────────────
                      const SectionHeader(
                          title: 'Reminders', icon: Icons.alarm_rounded),
                      SoftCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            SectionTile(
                              icon: Icons.water_drop_rounded,
                              title: 'Water reminders',
                              subtitle:
                                  '${settings.waterRemindersPaused ? 'Paused · ' : ''}'
                                  '${settings.waterIntervalMin} min intervals',
                              iconColor: AppColors.info,
                              onTap: () => context.push(Routes.waterSettings),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            SectionTile(
                              icon: Icons.medication_rounded,
                              title: 'Medicine reminders',
                              subtitle: settings.medicineRemindersPaused
                                  ? 'Paused'
                                  : 'Active for your schedule',
                              iconColor: AppColors.rose,
                              trailing: Switch.adaptive(
                                value: !settings.medicineRemindersPaused,
                                activeTrackColor: AppColors.primaryPink,
                                onChanged: (value) async {
                                  await ref
                                      .read(settingsControllerProvider.notifier)
                                      .updateAndReschedule((s) => s.copyWith(
                                            medicineRemindersPaused: !value,
                                          ));
                                },
                              ),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            SectionTile(
                              icon: Icons.notifications_outlined,
                              title: 'Notifications & quiet hours',
                              subtitle: settings.quietModeEnabled
                                  ? 'Quiet ${AkashaDates.minutesToLabel(settings.quietStartMin)} – '
                                      '${AkashaDates.minutesToLabel(settings.quietEndMin)}'
                                  : 'Quiet hours off',
                              iconColor: AppColors.warning,
                              onTap: () => context.push(Routes.notificationSettings),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            SectionTile(
                              icon: Icons.record_voice_over_outlined,
                              title: 'Voice',
                              subtitle: settings.voiceEnabled
                                  ? settings.voiceProfile.label
                                  : 'Voice off',
                              iconColor: AppColors.purple,
                              onTap: () => context.push(Routes.voiceSettings),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── Mind & Soul prefs ────────────────────────────────
                      const SectionHeader(
                          title: 'Encouragement', icon: Icons.auto_awesome_rounded),
                      SoftCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            SectionTile(
                              icon: Icons.favorite_rounded,
                              title: 'Daily messages',
                              subtitle: settings.motivationEnabled
                                  ? '${settings.motivationPerDay} gentle messages a day'
                                  : 'Off',
                              iconColor: AppColors.primaryPink,
                              trailing: Switch.adaptive(
                                value: settings.motivationEnabled,
                                activeTrackColor: AppColors.primaryPink,
                                onChanged: (value) async {
                                  await ref
                                      .read(settingsControllerProvider.notifier)
                                      .updateAndReschedule(
                                        (s) => s.copyWith(motivationEnabled: value),
                                      );
                                },
                              ),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            SectionTile(
                              icon: Icons.mark_email_unread_outlined,
                              title: 'Little love notes',
                              subtitle: settings.loveNotesEnabled
                                  ? 'On'
                                  : 'Off — notes still visible in the app',
                              iconColor: AppColors.rose,
                              trailing: Switch.adaptive(
                                value: settings.loveNotesEnabled,
                                activeTrackColor: AppColors.primaryPink,
                                onChanged: (value) async {
                                  await ref
                                      .read(settingsControllerProvider.notifier)
                                      .updateAndReschedule(
                                        (s) => s.copyWith(loveNotesEnabled: value),
                                      );
                                },
                              ),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            SectionTile(
                              icon: Icons.chat_bubble_outline_rounded,
                              title: 'AI companion',
                              subtitle: settings.aiEnabled
                                  ? 'Enabled — with your consent'
                                  : 'Off by default',
                              iconColor: AppColors.purple,
                              trailing: Switch.adaptive(
                                value: settings.aiEnabled,
                                activeTrackColor: AppColors.primaryPink,
                                onChanged: (value) async {
                                  if (value) {
                                    final ok = await showAkashaConfirm(
                                      context,
                                      title: 'Turn on the companion?',
                                      message:
                                          'Messages you send are processed by a secure '
                                          'backend to generate replies. Nothing is stored '
                                          'outside your device unless you also enable cloud '
                                          'sync. You can turn this off at any time.',
                                      confirmLabel: 'I understand, enable',
                                      icon: Icons.shield_outlined,
                                    );
                                    if (!ok) return;
                                  }
                                  await ref
                                      .read(settingsControllerProvider.notifier)
                                      .update((s) => s.copyWith(
                                            aiEnabled: value,
                                            aiConsentGiven:
                                                value || s.aiConsentGiven,
                                          ));
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── Privacy & data ───────────────────────────────────
                      const SectionHeader(
                          title: 'Privacy & data', icon: Icons.lock_outline_rounded),
                      SoftCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            SectionTile(
                              icon: Icons.shield_outlined,
                              title: 'Privacy settings',
                              subtitle: 'App lock, what is stored, consent',
                              onTap: () => context.push(Routes.privacySettings),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            SectionTile(
                              icon: Icons.cloud_outlined,
                              title: 'Cloud sync & backup',
                              subtitle: settings.syncEnabled
                                  ? 'On${settings.lastSyncAt != null ? ' · last sync ${AkashaDates.relativeTime(settings.lastSyncAt!)}' : ''}'
                                  : 'Off — everything stays on this phone',
                              onTap: () => context.push(Routes.syncSettings),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            SectionTile(
                              icon: Icons.file_download_outlined,
                              title: 'Export my data',
                              subtitle: 'Share a copy as a JSON file',
                              onTap: () => _exportData(context, ref),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            SectionTile(
                              icon: Icons.delete_forever_outlined,
                              title: 'Delete my data',
                              subtitle: 'Remove everything from this phone',
                              iconColor: AppColors.danger,
                              onTap: () => _wipe(context, ref),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const SectionHeader(
                          title: 'Diagnostics', icon: Icons.build_outlined),
                      SoftCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          children: [
                            SectionTile(
                              icon: Icons.health_and_safety_outlined,
                              title: 'Permissions & diagnostics',
                              subtitle: 'Are reminders able to reach you?',
                              onTap: () => context.push(Routes.diagnostics),
                            ),
                            const Divider(height: 1, indent: 16, endIndent: 16),
                            SectionTile(
                              icon: Icons.info_outline_rounded,
                              title: 'About AKASHA',
                              subtitle: 'v1.0.0',
                              onTap: () => context.push(Routes.about),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Center(
                        child: Text(
                          '${AppConstants.appName} · ${AppConstants.tagline}',
                          style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 1,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Editors ──────────────────────────────────────────────────────────────

  Future<void> _editWaterTarget(
    BuildContext context,
    WidgetRef ref,
    UserSettings settings,
  ) async {
    final controller = TextEditingController(text: '${settings.waterTargetMl}');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Daily water goal'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose something realistic for your body and your day. This is not '
              'medical advice — your own doctor knows best.',
              style: TextStyle(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 14),
            AkashaTextField(
              controller: controller,
              hint: 'Millilitres per day',
              keyboardType: TextInputType.number,
              suffix: const Padding(
                padding: EdgeInsets.only(right: 14),
                child: Center(
                  widthFactor: 1,
                  child: Text('ml', style: TextStyle(fontSize: 12)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [1500, 1800, 2000, 2500, 3000].map((v) {
                return ActionChip(
                  label: Text('$v'),
                  onPressed: () => controller.text = '$v',
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              if (parsed != null && parsed >= 500 && parsed <= 8000) {
                Navigator.pop(context, parsed);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    await ref
        .read(settingsControllerProvider.notifier)
        .update((s) => s.copyWith(waterTargetMl: result));
    ref.invalidate(todayWaterProvider);
    ref.invalidate(dataRevisionProvider);
  }

  Future<void> _editGlassSizes(
    BuildContext context,
    WidgetRef ref,
    UserSettings settings,
  ) async {
    final small = TextEditingController(text: '${settings.smallGlassMl}');
    final medium = TextEditingController(text: '${settings.glassSizeMl}');
    final large = TextEditingController(text: '${settings.largeGlassMl}');
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Glass sizes'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'These are your own glasses, not a standard. Use whatever you actually drink from.',
              style: TextStyle(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 14),
            AkashaTextField(
              controller: small,
              label: 'Small glass (ml)',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            AkashaTextField(
              controller: medium,
              label: 'Usual glass (ml)',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            AkashaTextField(
              controller: large,
              label: 'Large glass (ml)',
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final s = int.tryParse(small.text.trim()) ?? settings.smallGlassMl;
    final m = int.tryParse(medium.text.trim()) ?? settings.glassSizeMl;
    final l = int.tryParse(large.text.trim()) ?? settings.largeGlassMl;
    if (s < 30 || m < 30 || l < 30) return;
    // Water alarms carry the glass amount in their payload, so changing the
    // sizes must rebuild the schedule — otherwise "I drank water" from an
    // already-scheduled notification would log the old amount.
    await ref.read(settingsControllerProvider.notifier).updateAndReschedule(
          (current) => current.copyWith(
            smallGlassMl: s,
            glassSizeMl: m,
            largeGlassMl: l,
          ),
        );
    ref.invalidate(dataRevisionProvider);
    ref.invalidate(todayWaterProvider);
  }

  Future<void> _pickTheme(
    BuildContext context,
    WidgetRef ref,
    UserSettings settings,
  ) async {
    final selected = await showModalBottomSheet<AppThemeMode>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Appearance',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 19)),
            const SizedBox(height: 14),
            ...AppThemeMode.values.map((mode) => RadioListTile<AppThemeMode>(
                  value: mode,
                  groupValue: settings.themeMode,
                  activeColor: AppColors.purple,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    switch (mode) {
                      AppThemeMode.light => 'Light (recommended)',
                      AppThemeMode.dark => 'Dark',
                      AppThemeMode.system => 'Follow the system',
                    },
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  onChanged: (value) => Navigator.pop(context, value),
                )),
          ],
        ),
      ),
    );
    if (selected == null) return;
    await ref
        .read(settingsControllerProvider.notifier)
        .update((s) => s.copyWith(themeMode: selected));
  }

  Future<void> _exportData(BuildContext context, WidgetRef ref) async {
    try {
      final snapshot = await ref.read(profileRepositoryProvider).exportSnapshot();
      final dir = Directory.systemTemp;
      final file = File(
        '${dir.path}/akasha-export-${AkashaDates.key(DateTime.now())}.json',
      );
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(snapshot),
      );
      // SharePlus.instance.share is the current entry point; `Share.shareXFiles`
      // still exists in share_plus 12 but is deprecated and slated for removal.
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: 'My AKASHA data export',
          text: 'A copy of my own AKASHA records.',
        ),
      );
      if (context.mounted) {
        showAkashaToast(
          context,
          'Export ready. Keep it somewhere safe.',
          icon: Icons.file_download_done_rounded,
          color: AppColors.success,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      showAkashaToast(
        context,
        'Could not create the export file on this device.',
        icon: Icons.error_outline_rounded,
        color: AppColors.danger,
      );
    }
  }

  Future<void> _wipe(BuildContext context, WidgetRef ref) async {
    final ok = await showAkashaConfirm(
      context,
      title: 'Delete all personal data?',
      message:
          'This removes your water logs, medicines, journal, moods, love notes and '
          'every reminder from this phone. It cannot be undone. If cloud sync is on, '
          'you will be asked separately about your cloud copy.',
      confirmLabel: 'Delete everything',
      destructive: true,
      icon: Icons.delete_forever_rounded,
    );
    if (!ok) return;
    await ref.read(profileRepositoryProvider).wipeAll();
    await ref.read(notificationServiceProvider).cancelAll();
    await ref.read(seedServiceProvider).ensureFirstRunData();
    ref.invalidate(profileProvider);
    ref.invalidate(settingsProvider);
    ref.invalidate(dataRevisionProvider);
    if (!context.mounted) return;
    showAkashaToast(
      context,
      'Your data has been removed from this phone.',
      icon: Icons.check_circle_rounded,
      color: AppColors.success,
    );
    context.go(Routes.home);
  }
}
