import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Animated gradient progress ring with a water-fill option.
///
/// Used for hydration progress, daily wellness score, and breathing progress.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    this.size = 180,
    this.strokeWidth = 14,
    this.gradient = AppColors.waterFill,
    this.trackColor = AppColors.hairline,
    this.child,
    this.startAngle = -math.pi / 2,
    this.animate = true,
    this.waterLevel, // 0..1 — draws a calm water surface inside the ring
    this.glow = true,
  });

  /// 0..1 (values above 1 are clamped for the arc but shown by the caller).
  final double progress;
  final double size;
  final double strokeWidth;
  final List<Color> gradient;
  final Color trackColor;
  final Widget? child;
  final double startAngle;
  final bool animate;

  /// When non-null, a soft water fill is painted inside the circle.
  final double? waterLevel;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: clamped),
        duration: animate ? const Duration(milliseconds: 900) : Duration.zero,
        curve: Curves.easeOutCubic,
        builder: (context, value, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size.square(size),
                painter: _RingPainter(
                  progress: value,
                  strokeWidth: strokeWidth,
                  gradient: gradient,
                  trackColor: trackColor,
                  startAngle: startAngle,
                  waterLevel: waterLevel,
                  glow: glow,
                ),
              ),
              if (child != null)
                Padding(
                  padding: EdgeInsets.all(strokeWidth + 8),
                  child: Center(child: child),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.gradient,
    required this.trackColor,
    required this.startAngle,
    required this.waterLevel,
    required this.glow,
  });

  final double progress;
  final double strokeWidth;
  final List<Color> gradient;
  final Color trackColor;
  final double startAngle;
  final double? waterLevel;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawCircle(center, radius, track);

    if (waterLevel != null) {
      _paintWater(canvas, center, radius);
    }

    // Progress arc
    if (progress > 0) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + math.pi * 2,
          colors: [...gradient, gradient.first],
          transform: GradientRotation(startAngle),
        ).createShader(rect);

      if (glow) {
        final glowPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * 1.6
          ..strokeCap = StrokeCap.round
          ..color = gradient.first.withValues(alpha: .22)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        canvas.drawArc(rect, startAngle, 2 * math.pi * progress, false, glowPaint);
      }
      canvas.drawArc(rect, startAngle, 2 * math.pi * progress, false, arcPaint);
    }
  }

  void _paintWater(Canvas canvas, Offset center, double radius) {
    final level = waterLevel!.clamp(0.0, 1.0);
    if (level <= 0) return;
    final inner = radius - strokeWidth / 2 - 2;
    final clipPath = Path()..addOval(Rect.fromCircle(center: center, radius: inner));
    canvas.save();
    canvas.clipPath(clipPath);

    // Surface Y moves up as the level grows; a shallow sine wave gives the
    // "water" a gentle, living edge without ever distracting from the numbers.
    final top = center.dy + inner - (2 * inner * level);
    final wave = Path()..moveTo(center.dx - inner, top);
    const segments = 48;
    final width = inner * 2;
    for (var i = 0; i <= segments; i++) {
      final t = i / segments;
      final x = center.dx - inner + width * t;
      final y = top + math.sin(t * math.pi * 3) * (2.2 + 2.2 * level);
      wave.lineTo(x, y);
    }
    wave
      ..lineTo(center.dx + inner, center.dy + inner)
      ..lineTo(center.dx - inner, center.dy + inner)
      ..close();

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.skyBlue.withValues(alpha: .38),
          AppColors.skyBlue.withValues(alpha: .62),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: inner));
    canvas.drawPath(wave, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress ||
      old.waterLevel != waterLevel ||
      old.gradient != gradient;
}
