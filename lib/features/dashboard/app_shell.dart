import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../../shared/widgets/app_nav.dart';

/// Persistent shell for the five primary destinations.
///
/// `StatefulShellRoute` keeps each tab's navigation stack alive, so switching
/// from Water back to Home does not reset scroll position or rebuild state.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const List<String> _paths = [
    Routes.home,
    Routes.water,
    Routes.medicine,
    Routes.mind,
    Routes.profile,
  ];

  void _onSelect(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: navigationShell,
      bottomNavigationBar: AkashaBottomNav(
        currentIndex: navigationShell.currentIndex,
        onSelect: _onSelect,
      ),
    );
  }
}

/// Helper so any card can jump to a tab (and pop the stack first).
void goToTab(BuildContext context, int index) {
  switch (index) {
    case 0:
      context.go(Routes.home);
    case 1:
      context.go(Routes.water);
    case 2:
      context.go(Routes.medicine);
    case 3:
      context.go(Routes.mind);
    case 4:
      context.go(Routes.profile);
  }
}
