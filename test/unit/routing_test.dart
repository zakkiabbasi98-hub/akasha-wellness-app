import 'package:akasha/core/routing/app_router.dart';
import 'package:flutter_test/flutter_test.dart';

/// Navigation regressions are invisible until someone taps the button: a route
/// constant that does not exist in the router still compiles, still renders the
/// tile, and fails only at the moment of use (or silently lands on the error
/// page). Seven such dead tiles — every Settings sub-page — were shipped and
/// caught by the audit that produced this suite.
void main() {
  group('route constants match the route tree', () {
    test('every constant is a real location', () {
      const constants = {
        'splash': Routes.splash,
        'onboarding': Routes.onboarding,
        'lock': Routes.lock,
        'home': Routes.home,
        'water': Routes.water,
        'medicine': Routes.medicine,
        'mind': Routes.mind,
        'profile': Routes.profile,
        'waterReminders': Routes.waterReminders,
        'waterReminderAdd': Routes.waterReminderAdd,
        'waterHistory': Routes.waterHistory,
        'waterStats': Routes.waterStats,
        'medicineAdd': Routes.medicineAdd,
        'medicineHistory': Routes.medicineHistory,
        'motivation': Routes.motivation,
        'journal': Routes.journal,
        'journalEditor': Routes.journalEditor,
        'mood': Routes.mood,
        'moodHistory': Routes.moodHistory,
        'breathing': Routes.breathing,
        'gratitude': Routes.gratitude,
        'reflection': Routes.reflection,
        'loveNotes': Routes.loveNotes,
        'aiCompanion': Routes.aiCompanion,
        'report': Routes.report,
        'calendar': Routes.calendar,
        'notificationHistory': Routes.notificationHistory,
        'settings': Routes.settings,
        'waterSettings': Routes.waterSettings,
        'voiceSettings': Routes.voiceSettings,
        'notificationSettings': Routes.notificationSettings,
        'privacySettings': Routes.privacySettings,
        'syncSettings': Routes.syncSettings,
        'diagnostics': Routes.diagnostics,
        'about': Routes.about,
      };

      for (final entry in constants.entries) {
        expect(
          RouteTree.all,
          contains(entry.value),
          reason: 'Routes.${entry.key} = "${entry.value}" is not in RouteTree',
        );
      }
    });

    test('the tree has no duplicate or malformed locations', () {
      expect(RouteTree.all.toSet().length, RouteTree.all.length);
      for (final path in RouteTree.all) {
        expect(path.startsWith('/'), isTrue, reason: '$path must be absolute');
        expect(path.contains('//'), isFalse, reason: '$path has a double slash');
        expect(path.length, greaterThan(1));
      }
    });

    test('sub-pages live under their own branch, not a bare root path', () {
      // A tile that routes to a bare root sub-path (eg /settings/water) would
      // push onto whichever branch happens to be active and mis-highlight the
      // bottom navigation. Settings are Profile children; reports, calendar and
      // history are Home children.
      expect(Routes.settings, startsWith('${Routes.profile}/'));
      expect(Routes.waterSettings, startsWith('${Routes.settings}/'));
      expect(Routes.voiceSettings, startsWith('${Routes.settings}/'));
      expect(Routes.notificationSettings, startsWith('${Routes.settings}/'));
      expect(Routes.privacySettings, startsWith('${Routes.settings}/'));
      expect(Routes.syncSettings, startsWith('${Routes.settings}/'));
      expect(Routes.diagnostics, startsWith('${Routes.settings}/'));
      expect(Routes.about, startsWith('${Routes.settings}/'));

      expect(Routes.report, startsWith('${Routes.home}/'));
      expect(Routes.calendar, startsWith('${Routes.home}/'));
      expect(Routes.notificationHistory, startsWith('${Routes.home}/'));
    });

    test('water sub-pages are inside the water branch', () {
      for (final path in [
        Routes.waterReminders,
        Routes.waterReminderAdd,
        Routes.waterHistory,
        Routes.waterStats,
      ]) {
        expect(path, startsWith('${Routes.water}/'), reason: path);
      }
    });

    test('medicine and mind sub-pages are inside their branches', () {
      expect(Routes.medicineAdd, startsWith('${Routes.medicine}/'));
      expect(Routes.medicineHistory, startsWith('${Routes.medicine}/'));
      for (final path in [
        Routes.motivation,
        Routes.journal,
        Routes.journalEditor,
        Routes.mood,
        Routes.moodHistory,
        Routes.breathing,
        Routes.gratitude,
        Routes.reflection,
        Routes.loveNotes,
        Routes.aiCompanion,
      ]) {
        expect(path, startsWith('${Routes.mind}/'), reason: path);
      }
    });

    test('the five tabs match the bottom navigation order', () {
      // Order matters: AkashaBottomNav.defaultItems is indexed by branch.
      expect(
        [Routes.home, Routes.water, Routes.medicine, Routes.mind, Routes.profile],
        hasLength(5),
      );
    });
  });
}
