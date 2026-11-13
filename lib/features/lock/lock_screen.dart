import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../../shared/widgets/gradient_scaffold.dart';
import '../../shared/widgets/water_drop.dart';

/// Standalone lock page (used when the app is opened from a deep link while
/// locked). The in-app gate in app.dart handles the normal case.
class LockScreen extends StatelessWidget {
  const LockScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AnimatedWaterDrop(size: 110),
            const SizedBox(height: 24),
            Text('AKASHA is locked', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              child: ElevatedButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
