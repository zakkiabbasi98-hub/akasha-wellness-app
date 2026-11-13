import 'package:flutter/material.dart';

/// Spacing, radii, shadows and duration tokens.
///
/// Using a scale (instead of magic numbers in widgets) is what keeps 37
/// screens looking like one product.
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  /// Standard horizontal page padding.
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: 20);
}

abstract final class AppRadius {
  static const double sm = 12;
  static const double md = 18;
  static const double card = 24;
  static const double lg = 28;
  static const double pill = 999;

  static BorderRadius get cardR => BorderRadius.circular(card);
  static BorderRadius get lgR => BorderRadius.circular(lg);
  static BorderRadius get mdR => BorderRadius.circular(md);
  static BorderRadius get smR => BorderRadius.circular(sm);
  static BorderRadius get pillR => BorderRadius.circular(pill);
}

abstract final class AppShadows {
  /// Very soft, always tinted violet — never pure black.
  static List<BoxShadow> get soft => [
        BoxShadow(
          color: const Color(0xFF9270C8).withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ];

  static List<BoxShadow> get lifted => [
        BoxShadow(
          color: const Color(0xFF9270C8).withValues(alpha: 0.14),
          blurRadius: 32,
          offset: const Offset(0, 16),
        ),
      ];

  static List<BoxShadow> tinted(Color c) => [
        BoxShadow(
          color: c.withValues(alpha: 0.28),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];
}

abstract final class AppDurations {
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration base = Duration(milliseconds: 320);
  static const Duration slow = Duration(milliseconds: 620);
  static const Duration breathing = Duration(milliseconds: 4200);

  static const Curve ease = Curves.easeOutCubic;
  static const Curve gentle = Curves.easeInOutCubic;
}
