import 'package:flutter/widgets.dart';

/// Layout helpers so the app feels native from a 5" phone to a foldable.
abstract final class Responsive {
  static double width(BuildContext c) => MediaQuery.sizeOf(c).width;
  static double height(BuildContext c) => MediaQuery.sizeOf(c).height;

  static bool isSmall(BuildContext c) => width(c) < 360;
  static bool isCompact(BuildContext c) => width(c) < 400;
  static bool isTablet(BuildContext c) => width(c) >= 600;

  /// Horizontal page padding that grows a touch on larger phones.
  static EdgeInsets pagePadding(BuildContext c) =>
      EdgeInsets.symmetric(horizontal: isTablet(c) ? 28 : 20);

  /// Two-column grid only when there is genuinely room.
  static int gridColumns(BuildContext c) {
    if (isTablet(c)) return 3;
    if (width(c) >= 380) return 2;
    return 2;
  }

  /// Dialog/sheet max width on big screens so forms don't stretch absurdly.
  static double contentMaxWidth(BuildContext c) => isTablet(c) ? 560 : double.infinity;

  static T maxWidth<T extends Widget>(BuildContext c, T child) => Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: contentMaxWidth(c)),
          child: child,
        ),
      );
}
