import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// A single bottom-navigation destination.
class NavItem {
  const NavItem({required this.icon, required this.activeIcon, required this.label});

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

/// The app's custom floating bottom bar.
///
/// Not a Material `NavigationBar`: we need a frosted, floating capsule with a
/// soft pink glow behind the active item, which is a big part of the app's
/// personality.
class AkashaBottomNav extends StatelessWidget {
  const AkashaBottomNav({
    super.key,
    required this.currentIndex,
    required this.onSelect,
    this.items = defaultItems,
    this.padded = true,
  });

  final int currentIndex;
  final ValueChanged<int> onSelect;
  final List<NavItem> items;
  final bool padded;

  static const List<NavItem> defaultItems = [
    NavItem(
      icon: Icons.spa_outlined,
      activeIcon: Icons.spa_rounded,
      label: 'Home',
    ),
    NavItem(
      icon: Icons.water_drop_outlined,
      activeIcon: Icons.water_drop_rounded,
      label: 'Water',
    ),
    NavItem(
      icon: Icons.medication_outlined,
      activeIcon: Icons.medication_rounded,
      label: 'Medicine',
    ),
    NavItem(
      icon: Icons.favorite_border_rounded,
      activeIcon: Icons.favorite_rounded,
      label: 'Mind',
    ),
    NavItem(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        padded ? 16 : 0,
        0,
        padded ? 16 : 0,
        (bottomInset > 0 ? 10 : 14),
      ),
      child: Container(
        height: 66,
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkSurface.withValues(alpha: .96)
              : AppColors.white.withValues(alpha: .96),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isDark ? AppColors.darkHairline : AppColors.hairline,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.deepPurple.withValues(alpha: isDark ? .3 : .13),
              blurRadius: 26,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(23),
          child: Row(
            children: List.generate(items.length, (i) {
              final selected = i == currentIndex;
              return Expanded(
                child: _NavButton(
                  item: items[i],
                  selected: selected,
                  onTap: () => onSelect(i),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: AppDurations.base,
              curve: AppDurations.ease,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(colors: AppColors.pinkLavender)
                    : null,
                borderRadius: BorderRadius.circular(14),
                boxShadow: selected
                    ? AppShadows.tinted(AppColors.primaryPink)
                    : null,
              ),
              child: Icon(
                selected ? item.activeIcon : item.icon,
                size: 21,
                color: selected
                    ? AppColors.white
                    : (Theme.of(context).brightness == Brightness.dark
                        ? AppColors.darkTextSecondary
                        : AppColors.secondaryText),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: AppDurations.fast,
              style: TextStyle(
                fontSize: 10.5,
                height: 1,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppColors.purple : AppColors.secondaryText,
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact header used by detail screens: back button + title + optional
/// trailing action, sitting on the gradient background.
class AkashaHeader extends StatelessWidget {
  const AkashaHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _RoundIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(letterSpacing: -0.3),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? AppColors.darkSurface : AppColors.white.withValues(alpha: .86),
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? AppColors.darkHairline : AppColors.hairline,
            ),
          ),
          child: Icon(icon, size: 19, color: AppColors.darkText),
        ),
      ),
    );
  }
}

/// Matching round action button for header trailing slots.
class HeaderAction extends StatelessWidget {
  const HeaderAction({super.key, required this.icon, required this.onTap, this.color});

  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white.withValues(alpha: .86),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.hairline),
          ),
          child: Icon(icon, size: 19, color: color ?? AppColors.purple),
        ),
      ),
    );
  }
}
