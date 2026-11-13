import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// The card that carries most of the app's content.
///
/// `SoftCard` is intentionally opinionated: 24px radius, hairline border, a
/// whisper-soft violet shadow, and an optional accent gradient wash in the
/// corner so cards feel layered rather than flat.
class SoftCard extends StatelessWidget {
  const SoftCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.onTap,
    this.accent,
    this.radius = AppRadius.card,
    this.borderColor,
    this.background,
    this.showBorder = true,
    this.alignment,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;

  /// When provided, a very soft diagonal gradient of this colour sits behind
  /// the content.
  final Color? accent;
  final double radius;
  final Color? borderColor;
  final Color? background;
  final bool showBorder;
  final AlignmentGeometry? alignment;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = background ?? (isDark ? AppColors.darkSurface : AppColors.white);
    final br = BorderRadius.circular(radius);

    Widget content = Container(
      alignment: alignment,
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: br,
        border: showBorder
            ? Border.all(
                color: borderColor ??
                    (isDark ? AppColors.darkHairline : AppColors.hairline),
                width: 1,
              )
            : null,
        gradient: accent == null
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  bg,
                  Color.alphaBlend(
                    accent!.withValues(alpha: isDark ? .14 : .10),
                    bg,
                  ),
                ],
              ),
        boxShadow: isDark ? null : AppShadows.soft,
      ),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: br,
          splashColor: AppColors.softPink.withValues(alpha: .5),
          highlightColor: AppColors.softPink.withValues(alpha: .25),
          child: content,
        ),
      );
    }

    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: content,
    );
  }
}

/// A card whose whole surface is a pastel gradient — for hero moments
/// (water progress, medicine next-dose, mood prompt).
class GradientCard extends StatelessWidget {
  const GradientCard({
    super.key,
    required this.child,
    this.gradient = AppColors.pinkLavender,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.onTap,
    this.radius = AppRadius.lg,
    this.foreground = AppColors.white,
  });

  final Widget child;
  final List<Color> gradient;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final double radius;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final br = BorderRadius.circular(radius);
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: br,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          boxShadow: AppShadows.tinted(gradient.last),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: br,
            splashColor: Colors.white24,
            highlightColor: Colors.white10,
            child: DefaultTextStyle.merge(
              style: TextStyle(color: foreground),
              child: IconTheme.merge(
                data: IconThemeData(color: foreground),
                child: Padding(padding: padding, child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tappable row inside a settings-style list, with a coloured icon bubble.
class SectionTile extends StatelessWidget {
  const SectionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.iconColor = AppColors.purple,
    this.iconBackground,
    this.showChevron = true,
    this.dense = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color iconColor;
  final Color? iconBackground;
  final bool showChevron;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdR,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: dense ? 12 : 16,
          vertical: dense ? 10 : 13,
        ),
        child: Row(
          children: [
            Container(
              width: dense ? 34 : 40,
              height: dense ? 34 : 40,
              decoration: BoxDecoration(
                color: iconBackground ??
                    Color.alphaBlend(
                      iconColor.withValues(alpha: isDark ? .22 : .14),
                      isDark ? AppColors.darkSurface : AppColors.white,
                    ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: dense ? 17 : 19, color: iconColor),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontSize: dense ? 14 : 15,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(height: 1.35),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (showChevron && onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: AppColors.secondaryText,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small rounded label used for statuses (Taken, Skipped, Missed…).
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.compact = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 4.5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: AppRadius.pillR,
        border: Border.all(color: color.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: compact ? 10 : 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              color: Color.alphaBlend(color.withValues(alpha: .86), AppColors.darkText),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section header used on dashboards: title on the left, optional action right.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
    this.icon,
    this.padding = const EdgeInsets.fromLTRB(2, 0, 2, 10),
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? icon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: AppColors.purple),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    letterSpacing: -0.2,
                  ),
            ),
          ),
          if (actionLabel != null)
            GestureDetector(
              onTap: onAction,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Text(
                  actionLabel!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.purple,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
