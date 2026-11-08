import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_tokens.dart';

/// The single source of truth for AKASHA's Material 3 theming.
///
/// Typography intentionally uses the platform font (SF/Roboto) with tuned
/// letter-spacing and weights: it keeps the app 100% offline, avoids a network
/// font fetch at first launch, and still reads elegantly. Drop Poppins into
/// assets/fonts and uncomment the family override below for a custom face —
/// see assets/fonts/README.md.
abstract final class AppTheme {
  /// Set to 'Poppins' after adding the font files to enable custom typography.
  static const String? fontFamily = null;

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.purple,
      onPrimary: AppColors.onAccent,
      primaryContainer: AppColors.lightLavender,
      onPrimaryContainer: AppColors.purple,
      secondary: AppColors.primaryPink,
      onSecondary: AppColors.onAccent,
      secondaryContainer: AppColors.softPink,
      onSecondaryContainer: AppColors.onSecondaryContainer,
      tertiary: AppColors.skyBlue,
      onTertiary: AppColors.onTertiary,
      tertiaryContainer: AppColors.softBlue,
      onTertiaryContainer: AppColors.onTertiaryContainer,
      error: AppColors.danger,
      onError: AppColors.white,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      surface: AppColors.white,
      onSurface: AppColors.darkText,
      surfaceContainerHighest: AppColors.cardMuted,
      onSurfaceVariant: AppColors.secondaryText,
      outline: AppColors.hairline,
      outlineVariant: AppColors.divider,
      shadow: AppColors.deepPurple,
      scrim: AppColors.scrim,
      inverseSurface: AppColors.darkText,
      onInverseSurface: AppColors.white,
      inversePrimary: AppColors.lavender,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      fontFamily: fontFamily,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: IconThemeData(color: AppColors.darkText, size: 22),
        titleTextStyle: TextStyle(
          color: AppColors.darkText,
          fontSize: 19,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardR,
          side: const BorderSide(color: AppColors.hairline, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.purple,
          foregroundColor: AppColors.white,
          disabledBackgroundColor: AppColors.lavender.withValues(alpha: .4),
          disabledForegroundColor: AppColors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.purple,
          foregroundColor: AppColors.white,
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.purple,
          side: const BorderSide(color: AppColors.lavender, width: 1.4),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.purple,
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.cardMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        hintStyle: const TextStyle(
          color: AppColors.secondaryText,
          fontSize: 14.5,
          fontWeight: FontWeight.w400,
        ),
        labelStyle: const TextStyle(color: AppColors.secondaryText, fontSize: 14),
        floatingLabelStyle: const TextStyle(color: AppColors.purple, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdR(),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdR(),
          borderSide: const BorderSide(color: AppColors.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdR(),
          borderSide: const BorderSide(color: AppColors.primaryPink, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdR(),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        errorStyle: const TextStyle(fontSize: 12.5),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.cardMuted,
        selectedColor: AppColors.softPink,
        side: const BorderSide(color: AppColors.hairline),
        labelStyle: const TextStyle(
          color: AppColors.darkText,
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
        ),
        secondaryLabelStyle: const TextStyle(
          color: AppColors.purple,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.pillR),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkText,
        contentTextStyle: const TextStyle(color: AppColors.white, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdR()),
        insetPadding: const EdgeInsets.all(16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgR),
        titleTextStyle: const TextStyle(
          color: AppColors.darkText,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.secondaryText,
          fontSize: 14.5,
          height: 1.5,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.hairline,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        ),
      ),
      switchTheme: SwitchThemeData(
        // The track carries the colour on this design, so the thumb stays white
        // selected or not (a single expression, not a redundant ternary).
        thumbColor: WidgetStateProperty.all(AppColors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.primaryPink : AppColors.hairline,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primaryPink,
        inactiveTrackColor: AppColors.hairline,
        thumbColor: AppColors.purple,
        overlayColor: AppColors.primaryPinkOverlay,
        trackHeight: 6,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.purple,
        textColor: AppColors.darkText,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          // Gentle shared-axis-style zoom reads as "premium" without being showy.
          TargetPlatform.android: ZoomPageTransitionsBuilder(
            allowSnapshotting: false,
          ),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData dark() {
    final lightTheme = light();
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.lavender,
      onPrimary: AppColors.darkOnPrimary,
      primaryContainer: AppColors.darkSurfaceAlt,
      onPrimaryContainer: AppColors.darkTextPrimary,
      secondary: AppColors.primaryPink,
      onSecondary: AppColors.darkOnSecondary,
      secondaryContainer: AppColors.darkSecondaryContainer,
      onSecondaryContainer: AppColors.darkTextPrimary,
      tertiary: AppColors.skyBlue,
      onTertiary: AppColors.darkOnTertiary,
      tertiaryContainer: AppColors.darkTertiaryContainer,
      onTertiaryContainer: AppColors.darkTextPrimary,
      error: AppColors.darkError,
      onError: AppColors.darkOnError,
      errorContainer: AppColors.darkErrorContainer,
      onErrorContainer: AppColors.darkOnErrorContainer,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkTextPrimary,
      surfaceContainerHighest: AppColors.darkSurfaceAlt,
      onSurfaceVariant: AppColors.darkTextSecondary,
      outline: AppColors.darkOutline,
      outlineVariant: AppColors.darkOutlineVariant,
      shadow: Colors.black,
      scrim: AppColors.darkScrim,
      inverseSurface: AppColors.darkTextPrimary,
      onInverseSurface: AppColors.darkText,
      inversePrimary: AppColors.purple,
    );

    return lightTheme.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.darkCanvas,
      canvasColor: AppColors.darkCanvas,
      cardColor: AppColors.darkSurface,
      appBarTheme: lightTheme.appBarTheme.copyWith(
        iconTheme: const IconThemeData(color: AppColors.darkTextPrimary, size: 22),
        titleTextStyle: lightTheme.appBarTheme.titleTextStyle?.copyWith(
          color: AppColors.darkTextPrimary,
        ),
        systemOverlayStyle: SystemUiOverlayStyle.light,
      ),
      cardTheme: lightTheme.cardTheme.copyWith(
        color: AppColors.darkSurface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardR,
          side: const BorderSide(color: AppColors.darkHairline),
        ),
      ),
      inputDecorationTheme: lightTheme.inputDecorationTheme.copyWith(
        fillColor: AppColors.darkSurfaceAlt,
        hintStyle: const TextStyle(color: AppColors.darkTextSecondary, fontSize: 14.5),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdR(),
          borderSide: const BorderSide(color: AppColors.darkOutline),
        ),
      ),
      dialogTheme: lightTheme.dialogTheme.copyWith(backgroundColor: AppColors.darkSurface),
      bottomSheetTheme: lightTheme.bottomSheetTheme.copyWith(
        backgroundColor: AppColors.darkSurface,
      ),
      chipTheme: lightTheme.chipTheme.copyWith(
        backgroundColor: AppColors.darkSurfaceAlt,
        side: const BorderSide(color: AppColors.darkOutline),
        labelStyle: const TextStyle(color: AppColors.darkTextPrimary, fontSize: 13.5),
      ),
      textTheme: _textTheme(lightTheme.textTheme, dark: true),
      dividerTheme: const DividerThemeData(color: AppColors.darkOutlineVariant, thickness: 1),
    );
  }

  static TextTheme _textTheme(TextTheme base, {bool dark = false}) {
    final primary = dark ? AppColors.darkTextPrimary : AppColors.darkText;
    final secondary = dark ? AppColors.darkTextSecondary : AppColors.secondaryText;
    TextStyle t(double size, FontWeight w, {double ls = -0.2, Color? color, double h = 1.35}) =>
        TextStyle(
          fontSize: size,
          fontWeight: w,
          letterSpacing: ls,
          color: color ?? primary,
          height: h,
        );

    return base.copyWith(
      displayLarge: t(40, FontWeight.w700, ls: -1.0, h: 1.15),
      displayMedium: t(34, FontWeight.w700, ls: -0.8, h: 1.18),
      displaySmall: t(28, FontWeight.w700, ls: -0.6, h: 1.2),
      headlineLarge: t(26, FontWeight.w700, ls: -0.5),
      headlineMedium: t(22, FontWeight.w600, ls: -0.4),
      headlineSmall: t(19, FontWeight.w600, ls: -0.3),
      titleLarge: t(18, FontWeight.w600, ls: -0.2),
      titleMedium: t(15.5, FontWeight.w600, ls: -0.1),
      titleSmall: t(13.5, FontWeight.w600, ls: 0.1),
      bodyLarge: t(16, FontWeight.w400, ls: 0, h: 1.5),
      bodyMedium: t(14.5, FontWeight.w400, ls: 0, h: 1.5),
      bodySmall: t(12.5, FontWeight.w400, ls: 0.1, color: secondary, h: 1.45),
      labelLarge: t(14, FontWeight.w600, ls: 0.2),
      labelMedium: t(12, FontWeight.w500, ls: 0.3, color: secondary),
      labelSmall: t(11, FontWeight.w500, ls: 0.4, color: secondary),
    );
  }
}
