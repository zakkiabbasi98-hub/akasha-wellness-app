import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Full-screen pastel gradient with optional floating decorative blobs.
///
/// Used as the root of every screen so the "wellness journal" mood is uniform.
class GradientScaffold extends StatelessWidget {
  const GradientScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.brightness = Brightness.light,
    this.colors,
    this.showBlobs = true,
    this.padding = EdgeInsets.zero,
    this.resizeToAvoidBottomInset = true,
  });

  final Widget body;
  final PreferredSizeWidget? appBar;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Brightness brightness;
  final List<Color>? colors;
  final bool showBlobs;
  final EdgeInsets padding;
  final bool resizeToAvoidBottomInset;

  bool get _isDark => brightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    final palette = colors ??
        (_isDark
            ? const [AppColors.darkSurfaceDeep, AppColors.darkSurfaceRaised, AppColors.darkCanvasDeep]
            : AppColors.blushGradient);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: palette,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: true,
        extendBodyBehindAppBar: true,
        appBar: appBar,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        body: Stack(
          children: [
            if (showBlobs) ...[
              const _Blob(
                alignment: Alignment(-1.15, -0.98),
                size: 240,
                color: AppColors.primaryPink,
                opacity: .22,
              ),
              const _Blob(
                alignment: Alignment(1.2, -0.72),
                size: 200,
                color: AppColors.lavender,
                opacity: .26,
              ),
              _Blob(
                alignment: const Alignment(1.05, 0.92),
                size: 260,
                color: _isDark ? AppColors.purple : AppColors.skyBlue,
                opacity: _isDark ? .22 : .16,
              ),
            ],
            SafeArea(
              bottom: false,
              child: Padding(padding: padding, child: body),
            ),
          ],
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({
    required this.alignment,
    required this.size,
    required this.color,
    required this.opacity,
  });

  final Alignment alignment;
  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: opacity),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
