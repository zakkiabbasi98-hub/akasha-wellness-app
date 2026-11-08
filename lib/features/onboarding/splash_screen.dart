import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/water_drop.dart';

/// Premium animated splash: a droplet that falls, settles, and breathes while
/// the wordmark rises into place. It also decides whether the app opens into
/// onboarding or straight to the dashboard, so there is no visible "waiting".
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _drop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final AnimationController _text = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final AnimationController _ripple = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    _drop.forward();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _text.forward();
    });
    _ripple.repeat();
    _route();
  }

  Future<void> _route() async {
    final started = DateTime.now();
    String target = Routes.onboarding;
    try {
      final profile = await ref.read(profileProvider.future);
      if (profile.isOnboarded) target = Routes.home;
    } catch (_) {
      // If the profile cannot be read, onboarding can recreate it safely.
      target = Routes.onboarding;
    }
    // Guarantee the animation gets its moment (min 1.9s total).
    final elapsed = DateTime.now().difference(started);
    final remaining = const Duration(milliseconds: 1900) - elapsed;
    if (remaining > Duration.zero) await Future.delayed(remaining);
    if (!mounted) return;
    context.go(target);
  }

  @override
  void dispose() {
    _drop.dispose();
    _text.dispose();
    _ripple.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: const [
            AppColors.splashPink,
            AppColors.splashLilac,
            AppColors.splashSky,
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Expanding ripple rings behind the droplet.
          AnimatedBuilder(
            animation: _ripple,
            builder: (context, _) {
              return CustomPaint(
                size: MediaQuery.sizeOf(context),
                painter: _RipplePainter(progress: _ripple.value),
              );
            },
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _drop,
                builder: (context, child) {
                  final t = Curves.easeOutBack.transform(_drop.value.clamp(0, 1));
                  return Opacity(
                    opacity: (t).clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, -60 * (1 - _drop.value)),
                      child: Transform.scale(scale: 0.6 + 0.4 * t, child: child),
                    ),
                  );
                },
                child: const AnimatedWaterDrop(size: 132),
              ),
              const SizedBox(height: 34),
              AnimatedBuilder(
                animation: _text,
                builder: (context, child) {
                  final v = Curves.easeOutCubic.transform(_text.value);
                  return Opacity(
                    opacity: v,
                    child: Transform.translate(
                      offset: Offset(0, 18 * (1 - v)),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  children: [
                    Text(
                      'AKASHA',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 10,
                        height: 1,
                        color: AppColors.darkText.withValues(alpha: .92),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _dot(AppColors.primaryPink),
                        _pill(AppColors.lavender),
                        _dot(AppColors.skyBlue),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Hydrate  •  Smile  •  Shine',
                      style: TextStyle(
                        fontSize: 13,
                        letterSpacing: 2.4,
                        fontWeight: FontWeight.w500,
                        color: AppColors.secondaryText.withValues(alpha: .9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            bottom: 52,
            child: FadeTransition(
              opacity: _text,
              child: const Text(
                'made with care, for you',
                style: TextStyle(
                  fontSize: 11.5,
                  letterSpacing: 1.2,
                  color: AppColors.secondaryText,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color color) => Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  Widget _pill(Color color) => Container(
        width: 26,
        height: 6,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
      );
}

class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final p = (progress + i / 3) % 1.0;
      final radius = 90 + p * 170;
      canvas.drawCircle(
        center.translate(0, -20),
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = AppColors.lavender.withValues(alpha: (1 - p) * .28),
      );
    }
    // ignore: unused_local_variable
    final _ = math.pi;
  }

  @override
  bool shouldRepaint(covariant _RipplePainter old) => old.progress != progress;
}
