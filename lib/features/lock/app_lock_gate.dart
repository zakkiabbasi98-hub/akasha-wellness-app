import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/water_drop.dart';
import 'package:flutter/services.dart';

/// Wraps the whole app and shows a soft lock screen when the biometric app lock
/// is enabled and the grace period has expired.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _checking = true;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _evaluate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _hiddenAt = DateTime.now();
    }
    if (state == AppLifecycleState.resumed) {
      final hidden = _hiddenAt;
      final shouldRelock = hidden != null &&
          DateTime.now().difference(hidden).inSeconds > 120;
      if (shouldRelock && _lockEnabled) {
        setState(() => _locked = true);
        _authenticate();
      }
      _hiddenAt = null;
    }
  }

  bool get _lockEnabled =>
      ref.read(settingsControllerProvider).valueOrNull?.appLockEnabled ?? false;

  Future<void> _evaluate() async {
    // Await the provider rather than reading `valueOrNull`: while settings are
    // still loading that value is null, which would be read as "app lock is
    // off" and silently skip the lock on a device that has it enabled.
    final bool enabled;
    try {
      enabled = (await ref.read(settingsProvider.future)).appLockEnabled;
    } catch (e, st) {
      debugPrint('AKASHA: app lock check failed, continuing unlocked: $e\n$st');
      if (mounted) setState(() => _checking = false);
      return;
    }
    if (!mounted) return;
    if (!enabled) {
      if (mounted) setState(() => _checking = false);
      return;
    }
    final canAuth = await ref.read(lockServiceProvider).isBiometricAvailable();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _locked = canAuth;
    });
    if (canAuth) _authenticate();
  }

  Future<void> _authenticate() async {
    final ok = await ref
        .read(lockServiceProvider)
        .authenticate(reason: 'Unlock AKASHA to see your own space');
    if (!mounted) return;
    if (ok) {
      setState(() => _locked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) return widget.child;
    if (!_locked) return widget.child;

    return GradientScaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AnimatedWaterDrop(size: 120),
            const SizedBox(height: 28),
            Text(
              'AKASHA is locked',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Your space stays private.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 220,
              child: ElevatedButton.icon(
                onPressed: _authenticate,
                icon: const Icon(Icons.fingerprint_rounded, size: 20),
                label: const Text('Unlock'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.purple,
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
