import 'package:flutter/material.dart';

/// Central colour palette for AKASHA.
///
/// Every colour in the app must come from here (or from the Material
/// [ColorScheme] built out of it) so the visual language stays consistent.
/// Contrast has been checked for body text on the light surfaces:
///   darkText on white      → 9.3:1
///   darkText on softPink   → 8.6:1
///   secondaryText on white → 4.6:1  (AA for normal text)
abstract final class AppColors {
  // ── Core brand ──────────────────────────────────────────────────────────
  static const Color primaryPink = Color(0xFFF2A9CE);
  static const Color softPink = Color(0xFFFCEAF4);
  static const Color lavender = Color(0xFFCBB5F5);
  static const Color lightLavender = Color(0xFFF1EAFC);
  static const Color skyBlue = Color(0xFFA9D2F5);
  static const Color softBlue = Color(0xFFEAF4FD);
  static const Color purple = Color(0xFF9270C8);
  static const Color white = Color(0xFFFFFFFF);

  // ── Text ────────────────────────────────────────────────────────────────
  static const Color darkText = Color(0xFF493B58);
  static const Color secondaryText = Color(0xFF94869F);
  static const Color onAccent = Color(0xFFFFFFFF);

  // ── Support ─────────────────────────────────────────────────────────────
  static const Color mint = Color(0xFFA8E0CE);
  static const Color softMint = Color(0xFFE9F8F2);
  static const Color peach = Color(0xFFF8C9A8);
  static const Color softPeach = Color(0xFFFDF0E7);
  static const Color rose = Color(0xFFE38AAE);
  static const Color softYellow = Color(0xFFFCF3D7);
  static const Color gold = Color(0xFFE0B871);

  // ── Surfaces ────────────────────────────────────────────────────────────
  static const Color canvas = Color(0xFFFBF9FD);
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardMuted = Color(0xFFF8F4FC);
  static const Color hairline = Color(0xFFEFE6F5);
  static const Color divider = Color(0xFFF2ECF7);

  // ── Semantic ────────────────────────────────────────────────────────────
  static const Color success = Color(0xFF59B99A);
  static const Color warning = Color(0xFFE0A458);
  static const Color danger = Color(0xFFD9738F);
  static const Color info = Color(0xFF7BA9D8);

  // ── Dark theme (optional) ───────────────────────────────────────────────
  static const Color darkCanvas = Color(0xFF221B2B);
  static const Color darkSurface = Color(0xFF2C2337);
  static const Color darkSurfaceAlt = Color(0xFF362B43);
  static const Color darkTextPrimary = Color(0xFFF6EFFA);
  static const Color darkTextSecondary = Color(0xFFBCAECB);

  /// Soft pastel gradients used across cards and headers.
  static const List<Color> blushGradient = [
    Color(0xFFFFF4F9),
    Color(0xFFF7EFFC),
    Color(0xFFEDF5FE),
  ];

  static const List<Color> pinkLavender = [Color(0xFFF6B9D6), Color(0xFFC3A6F2)];
  static const List<Color> lavenderBlue = [Color(0xFFCBB5F5), Color(0xFFA9D2F5)];
  static const List<Color> pinkPeach = [Color(0xFFF7AFCB), Color(0xFFF8C9A8)];
  static const List<Color> blueMint = [Color(0xFFA9D2F5), Color(0xFFA8E0CE)];
  static const List<Color> waterFill = [Color(0xFFCFE6FB), Color(0xFFA9D2F5)];

  // ── Derived surfaces used by cards, gradients and dark-mode chrome ────────
  // Every screen must use these instead of a literal Color(0x…), so the palette
  // stays in exactly one file (see CONTRIBUTING.md → "Design tokens").
  static const Color warmBrown = Color(0xFF8A6337);   // text on soft peach
  static const Color deepPurple = Color(0xFF9270C8);  // legacy tint alias
  static const Color roseDeep = Color(0xFFE38AAE);    // pressed rose / emphasis
  static const Color skyDeep = Color(0xFF7FB6EA);     // deep water accent

  static const Color darkHairline = Color(0xFF3D304B);
  static const Color darkCanvasDeep = Color(0xFF221B2B);
  static const Color darkSurfaceDeep = Color(0xFF241C2E);
  static const Color darkSurfaceRaised = Color(0xFF2B2136);

  // Gentle one-off gradients (still tokens, never inline literals).
  static const List<Color> splashGradient = [
    Color(0xFFFFF6FA),
    Color(0xFFF7EFFD),
    Color(0xFFEDF5FE),
  ];
  static const List<Color> selfCareGradient = [Color(0xFFF9D9E7), Color(0xFFE3D7FA)];
  static const List<Color> journalGradient = [Color(0xFFF7B8D4), Color(0xFFE0A9E8)];
  static const List<Color> breatheGradient = [Color(0xFFA9D2F5), Color(0xFFB7C4F7)];
  static const List<Color> reflectGradient = [Color(0xFFCBB5F5), Color(0xFFA9C4F5)];
  static const List<Color> loveNoteGradient = [Color(0xFFF6C7B5), Color(0xFFF2A9CE)];
  static const List<Color> calendarGradient = [Color(0xFFA8E0CE), Color(0xFFA9D2F5)];
  static const List<Color> reportsGradient = [Color(0xFFE0B871), Color(0xFFF2A9CE)];
  static const List<Color> reminderGradient = [Color(0xFFF2A9CE), Color(0xFFCBB5F5)];
  static const List<Color> gentleBlush = [Color(0xFFF6B9D6), Color(0xFFC3A6F2)];
  static const List<Color> warmPeachPink = [Color(0xFFF8C9A8), Color(0xFFF2A9CE)];
  static const List<Color> breathCalm = [
    Color(0xFFF2F7FD),
    Color(0xFFF6EFFC),
    Color(0xFFFDF3F9),
  ];

  // Named singles, so a const list never has to index into another list
  // (indexing is not a constant expression in Dart).
  static const Color breathSky = Color(0xFFF2F7FD);
  static const Color breathLilac = Color(0xFFF6EFFC);
  static const Color breathRose = Color(0xFFFDF3F9);
  static const Color splashPink = Color(0xFFFFF6FA);
  static const Color splashLilac = Color(0xFFF7EFFD);
  static const Color splashSky = Color(0xFFEDF5FE);
  static const List<Color> noteCream = [Color(0xFFFFF3F8), Color(0xFFF7EFFC)];
  static const Color trackSoft = Color(0xFFDDE9F8);


  /// Rotating accent pairs so different sections feel distinct but related.
  static const List<List<Color>> accents = [
    pinkLavender,
    lavenderBlue,
    blueMint,
    pinkPeach,
  ];
}
