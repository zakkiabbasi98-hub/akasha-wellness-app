import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// A hand-painted water droplet (no bitmap assets needed, scales perfectly).
class WaterDrop extends StatelessWidget {
  const WaterDrop({
    super.key,
    this.size = 120,
    this.gradient = AppColors.waterFill,
    this.glow = true,
  });

  final double size;
  final List<Color> gradient;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 0.78,
      height: size,
      child: CustomPaint(
        painter: _DropPainter(gradient: gradient, glow: glow),
      ),
    );
  }
}

class _DropPainter extends CustomPainter {
  _DropPainter({required this.gradient, required this.glow});

  final List<Color> gradient;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final tip = Offset(w / 2, 0);
    final path = Path()
      ..moveTo(w / 2, 0)
      ..cubicTo(w * 0.92, h * 0.34, w, h * 0.58, w, h * 0.68)
      ..cubicTo(w, h * 0.88, w * 0.78, h, w / 2, h)
      ..cubicTo(w * 0.22, h, 0, h * 0.88, 0, h * 0.68)
      ..cubicTo(0, h * 0.58, w * 0.08, h * 0.34, w / 2, 0)
      ..close();

    if (glow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = gradient.last.withValues(alpha: .30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: gradient,
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );

    // Highlight — a small curved sliver of light on the upper-left.
    final highlight = Path()
      ..moveTo(w * 0.30, h * 0.52)
      ..quadraticBezierTo(w * 0.20, h * 0.72, w * 0.34, h * 0.84);
    canvas.drawPath(
      highlight,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.07
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: .55),
    );

    // Additive sparkle at the tip.
    canvas.drawCircle(
      Offset(w * 0.50, h * 0.18),
      w * 0.035,
      Paint()..color = Colors.white.withValues(alpha: .85),
    );
    // ignore: unused_local_variable
    final _ = tip;
  }

  @override
  bool shouldRepaint(covariant _DropPainter old) => old.gradient != gradient;
}

/// "Idle" droplet: slowly floats and breathes. Used on splash and the
/// hydration card.
class AnimatedWaterDrop extends StatefulWidget {
  const AnimatedWaterDrop({
    super.key,
    this.size = 130,
    this.gradient = AppColors.waterFill,
    this.floating = true,
  });

  final double size;
  final List<Color> gradient;
  final bool floating;

  @override
  State<AnimatedWaterDrop> createState() => _AnimatedWaterDropState();
}

class _AnimatedWaterDropState extends State<AnimatedWaterDrop>
    with TickerProviderStateMixin {
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  )..repeat(reverse: true);

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _float.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_float, _pulse]),
      builder: (context, _) {
        final dy = widget.floating
            ? (Curves.easeInOut.transform(_float.value) - .5) * 10
            : 0.0;
        final scale = 1 + (Curves.easeInOut.transform(_pulse.value) - .5) * .045;
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(
            scale: scale,
            child: WaterDrop(
              size: widget.size,
              gradient: widget.gradient,
            ),
          ),
        );
      },
    );
  }
}

/// A row of small droplets that fill up as hydration progresses — the
/// dashboard's fastest-to-read indicator of "how many glasses to go".
class DropletMeter extends StatelessWidget {
  const DropletMeter({
    super.key,
    required this.filled,
    required this.total,
    this.maxVisible = 12,
    this.size = 15,
    this.activeGradient = AppColors.waterFill,
    this.inactiveColor = AppColors.hairline,
  });

  final int filled;
  final int total;
  final int maxVisible;
  final double size;
  final List<Color> activeGradient;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final shown = math.min(total, maxVisible);
    final ratio = total == 0 ? 0.0 : filled / total;
    final filledShown = (ratio * shown).round().clamp(0, shown);
    return Wrap(
      spacing: 3.5,
      runSpacing: 3.5,
      children: List.generate(shown, (i) {
        final active = i < filledShown;
        return CustomPaint(
          size: Size(size * .78, size),
          painter: _MiniDropPainter(
            active: active,
            gradient: activeGradient,
            inactive: inactiveColor,
          ),
        );
      }),
    );
  }
}

class _MiniDropPainter extends CustomPainter {
  _MiniDropPainter({
    required this.active,
    required this.gradient,
    required this.inactive,
  });

  final bool active;
  final List<Color> gradient;
  final Color inactive;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w / 2, 0)
      ..cubicTo(w * .92, h * .34, w, h * .58, w, h * .68)
      ..cubicTo(w, h * .88, w * .78, h, w / 2, h)
      ..cubicTo(w * .22, h, 0, h * .88, 0, h * .68)
      ..cubicTo(0, h * .58, w * .08, h * .34, w / 2, 0)
      ..close();

    final paint = Paint()
      ..color = inactive;
    if (active) {
      paint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: gradient,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _MiniDropPainter old) =>
      old.active != active || old.gradient != gradient;
}
