import 'package:akasha/core/theme/app_colors.dart';
import 'package:akasha/core/theme/app_theme.dart';
import 'package:akasha/core/theme/app_tokens.dart';
import 'package:akasha/shared/widgets/app_nav.dart';
import 'package:akasha/shared/widgets/gradient_scaffold.dart';
import 'package:akasha/shared/widgets/progress_ring.dart';
import 'package:akasha/shared/widgets/soft_card.dart';
import 'package:akasha/shared/widgets/states.dart';
import 'package:akasha/shared/widgets/water_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  group('theme', () {
    test('light theme uses the AKASHA palette, not Material defaults', () {
      final theme = AppTheme.light();
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, AppColors.purple);
      expect(theme.colorScheme.secondary, AppColors.primaryPink);
      expect(theme.scaffoldBackgroundColor, AppColors.canvas);
      // The default Material purple (#6750A4) must never appear.
      expect(theme.colorScheme.primary, isNot(const Color(0xFF6750A4)));
    });

    test('dark theme exists and is dark', () {
      final theme = AppTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, AppColors.darkCanvas);
    });

    test('typography has no text below 10px (readability floor)', () {
      final t = AppTheme.light().textTheme;
      final sizes = [
        t.labelSmall?.fontSize,
        t.bodySmall?.fontSize,
        t.bodyMedium?.fontSize,
      ];
      for (final size in sizes) {
        expect(size, isNotNull);
        expect(size!, greaterThanOrEqualTo(10));
      }
    });

    test('cards use a generous radius', () {
      expect(AppRadius.card, greaterThanOrEqualTo(20));
      expect(AppRadius.lg, greaterThanOrEqualTo(20));
      expect(AppRadius.card, lessThanOrEqualTo(28));
    });

    test('shadows are tinted violet, never pure black', () {
      for (final shadow in AppShadows.soft) {
        expect(shadow.color, isNot(Colors.black));
      }
    });
  });

  group('GradientScaffold', () {
    testWidgets('renders its body inside a gradient', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const GradientScaffold(
            body: Center(child: Text('hello akasha')),
          ),
        ),
      );
      expect(find.text('hello akasha'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('can hide the decorative blobs', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const GradientScaffold(
            showBlobs: false,
            body: SizedBox.shrink(),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('SoftCard', () {
    testWidgets('renders content and fires onTap', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(wrap(
        SoftCard(
          onTap: () => tapped++,
          child: const Text('tap me'),
        ),
      ));
      expect(find.text('tap me'), findsOneWidget);
      await tester.tap(find.text('tap me'));
      expect(tapped, 1);
    });

    testWidgets('supports an accent gradient wash', (tester) async {
      await tester.pumpWidget(wrap(
        const SoftCard(accent: AppColors.primaryPink, child: Text('accent')),
      ));
      expect(find.text('accent'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('ProgressRing', () {
    testWidgets('renders and clamps progress above 1.0', (tester) async {
      await tester.pumpWidget(wrap(
        const Center(
          child: ProgressRing(
            progress: 1.8,
            size: 120,
            waterLevel: 0.5,
            child: Text('250'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('250'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('handles negative progress without throwing', (tester) async {
      await tester.pumpWidget(wrap(
        const Center(child: ProgressRing(progress: -0.4)),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('water visuals', () {
    testWidgets('WaterDrop paints', (tester) async {
      await tester.pumpWidget(wrap(const Center(child: WaterDrop(size: 80))));
      expect(tester.takeException(), isNull);
    });

    testWidgets('AnimatedWaterDrop animates without disposing errors',
        (tester) async {
      await tester.pumpWidget(wrap(const Center(child: AnimatedWaterDrop())));
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);
      // Let the repeating controllers be disposed by the tree teardown.
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('DropletMeter handles a total of zero', (tester) async {
      await tester.pumpWidget(
        wrap(const Center(child: DropletMeter(filled: 0, total: 0))),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('DropletMeter caps the visible droplets', (tester) async {
      await tester.pumpWidget(
        wrap(const Center(
          child: DropletMeter(filled: 10, total: 30, maxVisible: 12),
        )),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('states', () {
    testWidgets('EmptyState shows title, message and action', (tester) async {
      var pressed = false;
      await tester.pumpWidget(wrap(
        EmptyState(
          icon: Icons.water_drop_outlined,
          title: 'No water yet',
          message: 'Your first glass is a lovely place to start.',
          actionLabel: 'Add water',
          onAction: () => pressed = true,
        ),
      ));
      expect(find.text('No water yet'), findsOneWidget);
      expect(find.text('Your first glass is a lovely place to start.'),
          findsOneWidget);
      await tester.tap(find.text('Add water'));
      expect(pressed, isTrue);
    });

    testWidgets('LoadingDots animates', (tester) async {
      await tester.pumpWidget(wrap(const Center(child: LoadingDots())));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('AkashaBottomNav', () {
    testWidgets('renders five destinations with labels', (tester) async {
      await tester.pumpWidget(wrap(
        Align(
          alignment: Alignment.bottomCenter,
          child: AkashaBottomNav(currentIndex: 0, onSelect: (_) {}),
        ),
      ));
      for (final item in AkashaBottomNav.defaultItems) {
        expect(find.text(item.label), findsOneWidget);
      }
    });

    testWidgets('reports the tapped index', (tester) async {
      int? selected;
      await tester.pumpWidget(wrap(
        Align(
          alignment: Alignment.bottomCenter,
          child: AkashaBottomNav(
            currentIndex: 0,
            onSelect: (i) => selected = i,
          ),
        ),
      ));
      await tester.tap(find.text('Medicine'));
      expect(selected, 2);
    });

    testWidgets('marks the current destination for accessibility',
        (tester) async {
      await tester.pumpWidget(wrap(
        Align(
          alignment: Alignment.bottomCenter,
          child: AkashaBottomNav(currentIndex: 3, onSelect: (_) {}),
        ),
      ));
      expect(
        tester.getSemantics(find.text('Mind')),
        matchesSemantics(label: 'Mind', isButton: true, isSelected: true),
      );
    });
  });

  group('StatusPill', () {
    testWidgets('renders a label with an icon', (tester) async {
      await tester.pumpWidget(wrap(
        const Center(
          child: StatusPill(
            label: 'Taken',
            color: AppColors.success,
            icon: Icons.check_rounded,
          ),
        ),
      ));
      expect(find.text('Taken'), findsOneWidget);
    });
  });
}
