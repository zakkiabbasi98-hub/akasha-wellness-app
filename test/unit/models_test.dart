import 'package:akasha/core/database/app_database.dart';
import 'package:akasha/data/models/medicine_models.dart';
import 'package:akasha/data/models/mind_models.dart';
import 'package:akasha/data/models/user_settings.dart';
import 'package:akasha/data/models/water_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserSettings', () {
    final settings = UserSettings(
      id: 'settings-1',
      userId: 'user-1',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      waterTargetMl: 2000,
      glassSizeMl: 250,
    );

    test('glassesTarget rounds up so the goal is always reachable', () {
      expect(settings.glassesTarget, 8);
      expect(settings.copyWith(waterTargetMl: 2050).glassesTarget, 9);
      expect(settings.copyWith(waterTargetMl: 0).glassesTarget, 1);
    });

    test('row round-trip preserves every scheduling field', () {
      final original = settings.copyWith(
        waterStartMin: 480,
        waterEndMin: 0,
        waterIntervalMin: 45,
        waterRemindersPaused: true,
        quietStartMin: 1290,
        quietEndMin: 390,
        voiceProfile: VoiceProfile.cheerfulFeminine,
        themeMode: AppThemeMode.dark,
        motivationCategories: const ['calmness', 'growth'],
        aiEnabled: true,
        aiConsentGiven: true,
      );
      final restored = UserSettings.fromRow(original.toRow());
      expect(restored.waterStartMin, 480);
      expect(restored.waterEndMin, 0);
      expect(restored.waterIntervalMin, 45);
      expect(restored.waterRemindersPaused, isTrue);
      expect(restored.quietStartMin, 1290);
      expect(restored.voiceProfile, VoiceProfile.cheerfulFeminine);
      expect(restored.themeMode, AppThemeMode.dark);
      expect(restored.motivationCategories, ['calmness', 'growth']);
      expect(restored.aiEnabled, isTrue);
      expect(restored.aiConsentGiven, isTrue);
    });

    test('effectiveVoice respects the master toggle', () {
      expect(settings.effectiveVoice, VoiceProfile.softFeminine);
      expect(
        settings.copyWith(voiceEnabled: false).effectiveVoice,
        VoiceProfile.disabled,
      );
    });

    test('every stamped local write is marked dirty for sync', () {
      // The single stamping helper must always set dirty=1: a local edit that
      // forgets the flag is an edit that never reaches the cloud.
      final row = AppDatabase.stamp({'water_target_ml': 2200});
      expect(row['dirty'], 1);
      expect(row['updated_at'], isA<int>());
      final inserted = AppDatabase.stamp({'id': 'x'}, isInsert: true);
      expect(inserted['dirty'], 1);
      expect(inserted['created_at'], isA<int>());
    });

    test('insertRow always supplies created_at (the NOT NULL fix)', () {
      final row = AppDatabase.insertRow({'id': 'x'});
      expect(row['created_at'], isA<int>());
      expect(row['updated_at'], isA<int>());
      expect(row['dirty'], 1);
    });

    test('touch never writes created_at (updates preserve it)', () {
      final patch = AppDatabase.touch({'enabled': 0});
      expect(patch.containsKey('created_at'), isFalse);
      expect(patch['updated_at'], isA<int>());
      expect(patch['dirty'], 1);
    });

    test('insertRow honours an explicit creation time', () {
      final created = DateTime.fromMillisecondsSinceEpoch(1234);
      expect(AppDatabase.insertRow({'id': 'x'}, createdAt: created)['created_at'],
          1234);
    });

    test('copyWith always marks the row dirty for sync', () {
      final changed = settings.copyWith(waterTargetMl: 2500);
      expect(changed.isDirty, isTrue);
      expect(changed.waterTargetMl, 2500);
    });

    test('theme keys round-trip', () {
      for (final mode in AppThemeMode.values) {
        final key = UserSettings.themeKeys[mode];
        expect(UserSettings.themeFromKey(key), mode);
      }
      expect(UserSettings.themeFromKey('nonsense'), AppThemeMode.system);
    });

    test('voice profile keys round-trip', () {
      for (final profile in VoiceProfile.values) {
        expect(VoiceProfile.fromKey(profile.key), profile);
      }
    });
  });

  group('WaterLog', () {
    test('row round-trip preserves the source and amount', () {
      final log = WaterLog(
        id: 'log-1',
        userId: 'user-1',
        dayKey: '2026-11-08',
        loggedAt: DateTime(2026, 11, 8, 10, 30),
        amountMl: 250,
        source: WaterLogSource.notification,
        reminderMinute: 600,
        glassSize: 'medium',
        createdAt: DateTime(2026, 11, 8, 10, 30),
        updatedAt: DateTime(2026, 11, 8, 10, 30),
      );
      final restored = WaterLog.fromRow(log.toRow());
      expect(restored.amountMl, 250);
      expect(restored.source, WaterLogSource.notification);
      expect(restored.reminderMinute, 600);
      expect(restored.dayKey, '2026-11-08');
      expect(restored.loggedAt, DateTime(2026, 11, 8, 10, 30));
    });

    test('source keys round-trip', () {
      for (final source in WaterLogSource.values) {
        expect(WaterLogSourceX.fromKey(source.key), source);
      }
      expect(WaterLogSourceX.fromKey('unexpected'), WaterLogSource.manual);
    });
  });

  group('DailyWaterSummary', () {
    test('progress and remaining never go below zero', () {
      const summary = DailyWaterSummary(
        dayKey: '2026-11-08',
        totalMl: 2500,
        glassCount: 10,
        targetMl: 2000,
        entries: [],
      );
      expect(summary.targetProgress, 1.25);
      expect(summary.remainingMl, 0);
      expect(summary.targetReached, isTrue);
    });

    test('zero target does not divide by zero', () {
      const summary = DailyWaterSummary(
        dayKey: '2026-11-08',
        totalMl: 500,
        glassCount: 2,
        targetMl: 0,
        entries: [],
      );
      expect(summary.targetProgress, 0);
    });
  });

  group('Medicine', () {
    final medicine = Medicine(
      id: 'med-1',
      userId: 'user-1',
      name: 'Example',
      startDay: '2026-11-01',
      weekdays: const [1, 3, 5], // Mon, Wed, Fri
      reminderMinutes: const [480, 1260],
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
    );

    test('isDueOn respects weekdays', () {
      // 2026-11-02 is a Monday, 11-03 Tuesday, 11-04 Wednesday.
      expect(medicine.isDueOn(DateTime(2026, 11, 2)), isTrue);
      expect(medicine.isDueOn(DateTime(2026, 11, 3)), isFalse);
      expect(medicine.isDueOn(DateTime(2026, 11, 4)), isTrue);
    });

    test('isDueOn respects the start date', () {
      expect(medicine.isDueOn(DateTime(2026, 10, 30)), isFalse);
    });

    test('isDueOn respects the end date', () {
      final withEnd = medicine.copyWith(
        endDay: '2026-11-05',
        weekdays: const [1, 2, 3, 4, 5, 6, 7],
      );
      expect(withEnd.isDueOn(DateTime(2026, 11, 4)), isTrue);
      expect(withEnd.isDueOn(DateTime(2026, 11, 6)), isFalse);
    });

    test('disabled medicines are never due', () {
      expect(
        medicine.copyWith(enabled: false).isDueOn(DateTime(2026, 11, 2)),
        isFalse,
      );
    });

    test('row round-trip keeps weekdays and reminder minutes', () {
      final restored = Medicine.fromRow(medicine.toRow());
      expect(restored.weekdays, [1, 3, 5]);
      expect(restored.reminderMinutes, [480, 1260]);
      expect(restored.name, 'Example');
    });

    test('clearEndDay removes an end date', () {
      final withEnd = medicine.copyWith(endDay: '2026-12-01');
      expect(withEnd.endDay, isNotNull);
      expect(withEnd.copyWith(clearEndDay: true).endDay, isNull);
    });
  });

  group('MedicineLog', () {
    test('an unanswered dose is never implicitly taken', () {
      final log = MedicineLog(
        id: 'log-1',
        userId: 'user-1',
        medicineId: 'med-1',
        dayKey: '2026-11-08',
        scheduledMinute: 480,
        createdAt: DateTime(2026, 11, 8),
        updatedAt: DateTime(2026, 11, 8),
      );
      expect(log.status, DoseStatus.scheduled);
      expect(log.isAnswered, isFalse);
    });

    test('isAnswered is true for terminal statuses only', () {
      MedicineLog base() => MedicineLog(
            id: 'l',
            userId: 'u',
            medicineId: 'm',
            dayKey: '2026-11-08',
            scheduledMinute: 480,
            createdAt: DateTime(2026, 11, 8),
            updatedAt: DateTime(2026, 11, 8),
          );
      expect(base().copyWith(status: DoseStatus.taken).isAnswered, isTrue);
      expect(base().copyWith(status: DoseStatus.skipped).isAnswered, isTrue);
      expect(base().copyWith(status: DoseStatus.missed).isAnswered, isTrue);
      expect(base().copyWith(status: DoseStatus.snoozed).isAnswered, isFalse);
    });

    test('scheduledAt composes the day and minute correctly', () {
      final log = MedicineLog(
        id: 'log-1',
        userId: 'user-1',
        medicineId: 'med-1',
        dayKey: '2026-11-08',
        scheduledMinute: 21 * 60,
        createdAt: DateTime(2026, 11, 8),
        updatedAt: DateTime(2026, 11, 8),
      );
      expect(log.scheduledAt, DateTime(2026, 11, 8, 21, 0));
    });

    test('status keys round-trip', () {
      for (final status in DoseStatus.values) {
        expect(DoseStatus.fromKey(status.key), status);
      }
    });
  });

  group('Mood & journal', () {
    test('mood keys round-trip and unknown returns null', () {
      for (final mood in MoodType.values) {
        expect(MoodType.fromKey(mood.key), mood);
      }
      expect(MoodType.fromKey('nonsense'), isNull);
    });

    test('journal row round-trip keeps body, mood and tags', () {
      final entry = JournalEntry(
        id: 'j-1',
        userId: 'u-1',
        dayKey: '2026-11-08',
        title: 'A quiet day',
        body: 'I drank my water and went for a walk.',
        mood: MoodType.calm,
        tags: const ['walk', 'water'],
        createdLocal: DateTime(2026, 11, 8, 20),
        createdAt: DateTime(2026, 11, 8, 20),
        updatedAt: DateTime(2026, 11, 8, 20),
      );
      final restored = JournalEntry.fromRow(entry.toRow());
      expect(restored.body, entry.body);
      expect(restored.mood, MoodType.calm);
      expect(restored.tags, ['walk', 'water']);
      expect(restored.title, 'A quiet day');
    });

    test('gratitude items skip empty slots', () {
      final entry = GratitudeEntry(
        id: 'g-1',
        userId: 'u-1',
        dayKey: '2026-11-08',
        first: 'Warm tea',
        createdAt: DateTime(2026, 11, 8),
        updatedAt: DateTime(2026, 11, 8),
      );
      expect(entry.items, ['Warm tea']);
    });
  });
}
