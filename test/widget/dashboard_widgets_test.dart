import 'package:akasha/core/theme/app_theme.dart';
import 'package:akasha/data/models/medicine_models.dart';
import 'package:akasha/data/models/mind_models.dart';
import 'package:akasha/data/models/user_settings.dart';
import 'package:akasha/data/models/water_models.dart';
import 'package:akasha/features/dashboard/dashboard_screen.dart';
import 'package:akasha/features/dashboard/widgets/dashboard_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(16), child: child),
        ),
      ),
    );

UserSettings settings({int target = 2000, int glass = 250}) => UserSettings(
      id: 's',
      userId: 'u',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      waterTargetMl: target,
      glassSizeMl: glass,
    );

DailyWaterSummary summary({int total = 750, int target = 2000}) =>
    DailyWaterSummary(
      dayKey: '2026-11-08',
      totalMl: total,
      glassCount: total ~/ 250,
      targetMl: target,
      entries: const [],
    );

Medicine medicine({String name = 'Example medicine'}) => Medicine(
      id: 'm1',
      userId: 'u',
      name: name,
      dosage: '1 tablet',
      startDay: '2026-11-01',
      reminderMinutes: const [480],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

MedicineLog log(DoseStatus status, {int minute = 480}) => MedicineLog(
      id: 'l1',
      userId: 'u',
      medicineId: 'm1',
      dayKey: '2026-11-08',
      scheduledMinute: minute,
      status: status,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  group('WaterHeroCard', () {
    testWidgets('shows the real total and percentage', (tester) async {
      await tester.pumpWidget(host(WaterHeroCard(
        summary: summary(total: 750),
        settings: settings(),
        onAdd: () {},
      )));
      await tester.pumpAndSettle();

      // 750 ml of 2000 → 38%
      expect(find.text('38%'), findsOneWidget);
      expect(find.text('Hydration'), findsOneWidget);
      expect(find.textContaining('1250 ml to go'), findsOneWidget);
    });

    testWidgets('shows the goal-reached message at 100%', (tester) async {
      await tester.pumpWidget(host(WaterHeroCard(
        summary: summary(total: 2000),
        settings: settings(),
        onAdd: () {},
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('Goal reached'), findsOneWidget);
    });

    testWidgets('invites a first glass when empty', (tester) async {
      await tester.pumpWidget(host(WaterHeroCard(
        summary: summary(total: 0),
        settings: settings(),
        onAdd: () {},
      )));
      await tester.pumpAndSettle();
      expect(find.textContaining('first glass'), findsOneWidget);
    });

    testWidgets('quick-add rows call back with the right amount',
        (tester) async {
      int? amount;
      String? label;
      await tester.pumpWidget(host(WaterHeroCard(
        summary: summary(),
        settings: settings(),
        onAdd: () {},
        onQuickAdd: (a, l) {
          amount = a;
          label = l;
        },
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usual · 250 ml'));
      expect(amount, 250);
      expect(label, 'medium');
    });

    testWidgets('renders with a null summary (loading state) safely',
        (tester) async {
      await tester.pumpWidget(host(WaterHeroCard(
        summary: null,
        settings: settings(),
        onAdd: () {},
      )));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('MedicineTodayCard', () {
    testWidgets('invites adding a medicine when empty', (tester) async {
      await tester.pumpWidget(host(MedicineTodayCard(
        doses: const [],
        onOpen: () {},
        onRespond: (_, __) async {},
      )));
      expect(find.text('Add a medicine'), findsOneWidget);
      expect(find.textContaining('reminders will follow your own schedule'),
          findsOneWidget);
    });

    testWidgets('lists doses and reports taken count', (tester) async {
      await tester.pumpWidget(host(MedicineTodayCard(
        doses: [
          DoseView(log: log(DoseStatus.taken), medicine: medicine(name: 'A')),
          DoseView(
            log: log(DoseStatus.scheduled, minute: 600),
            medicine: medicine(name: 'B'),
          ),
        ],
        onOpen: () {},
        onRespond: (_, __) async {},
      )));
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.textContaining('1 of 2 taken'), findsOneWidget);
    });

    testWidgets('quick actions report the chosen status', (tester) async {
      DoseStatus? reported;
      await tester.pumpWidget(host(MedicineTodayCard(
        doses: [DoseView(log: log(DoseStatus.scheduled), medicine: medicine())],
        onOpen: () {},
        onRespond: (_, status) async => reported = status,
      )));
      // The tick is the first circular quick action (the medicine header uses
      // the filled medication icon, so this is unambiguous).
      await tester.tap(find.byIcon(Icons.check_rounded).first);
      await tester.pump();
      expect(reported, DoseStatus.taken);
    });
  });

  group('MoodCard', () {
    testWidgets('asks how the heart is when there is no check-in',
        (tester) async {
      await tester.pumpWidget(host(MoodCard(latest: null, onOpen: () {})));
      expect(find.textContaining('How is your heart today?'), findsOneWidget);
    });

    testWidgets('shows the latest mood label and note', (tester) async {
      final entry = MoodEntry(
        id: 'mood-1',
        userId: 'u',
        dayKey: '2026-11-08',
        mood: MoodType.calm,
        note: 'quiet evening',
        loggedAt: DateTime(2026, 11, 8, 20),
        createdAt: DateTime(2026, 11, 8, 20),
        updatedAt: DateTime(2026, 11, 8, 20),
      );
      await tester.pumpWidget(host(MoodCard(latest: entry, onOpen: () {})));
      expect(find.textContaining('Calm'), findsOneWidget);
      expect(find.textContaining('quiet evening'), findsOneWidget);
    });
  });

  group('ShortcutGrid', () {
    testWidgets('renders the expected shortcuts', (tester) async {
      await tester.pumpWidget(host(ShortcutGrid(
        onJournal: () {},
        onBreathing: () {},
        onReflection: () {},
        onLoveNotes: () {},
        onCalendar: () {},
        onReports: () {},
        onCompanion: () {},
        onWaterSettings: () {},
      )));
      expect(find.text('Journal'), findsOneWidget);
      expect(find.text('Breathe'), findsOneWidget);
      expect(find.text('Reflect'), findsOneWidget);
      expect(find.text('Love notes'), findsOneWidget);
      // The AI shortcut is hidden until the feature is enabled.
      expect(find.text('Companion'), findsNothing);
    });

    testWidgets('shows the companion shortcut when AI is enabled',
        (tester) async {
      await tester.pumpWidget(host(ShortcutGrid(
        onJournal: () {},
        onBreathing: () {},
        onReflection: () {},
        onLoveNotes: () {},
        onCalendar: () {},
        onReports: () {},
        onCompanion: () {},
        onWaterSettings: () {},
        aiEnabled: true,
      )));
      expect(find.text('Companion'), findsOneWidget);
    });
  });

  group('SelfCareCard & MotivationCard', () {
    testWidgets('self-care renders the prompt', (tester) async {
      await tester.pumpWidget(host(SelfCareCard(
        prompt: 'Unclench your jaw.',
        doneToday: false,
        onWrite: () {},
        onJournal: () {},
      )));
      expect(find.text('Unclench your jaw.'), findsOneWidget);
      expect(find.text('done today'), findsNothing);
    });

    testWidgets('motivation card shows the message text', (tester) async {
      final message = MotivationalMessage(
        id: 'msg-1',
        category: MotivationCategory.calmness,
        text: 'The day is not a race, and you are not behind.',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      await tester.pumpWidget(
        host(MotivationCard(message: message, onOpen: () {}, onHeart: () {})),
      );
      expect(
        find.text('The day is not a race, and you are not behind.'),
        findsOneWidget,
      );
    });

    testWidgets('motivation card falls back to a kind default',
        (tester) async {
      await tester.pumpWidget(
        host(MotivationCard(message: null, onOpen: () {}, onHeart: () {})),
      );
      expect(find.textContaining('doing better than you think'), findsOneWidget);
    });
  });
}
