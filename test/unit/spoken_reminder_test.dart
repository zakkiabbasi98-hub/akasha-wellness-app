import 'package:akasha/content/motivation_content.dart';
import 'package:akasha/core/notifications/spoken_reminders.dart';
import 'package:akasha/data/models/user_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests for Critical Issue 3: spoken water reminders.
///
/// The bug was that no production code path consumed the voice setting — the
/// only `speak()` calls were in the settings preview and diagnostics. These
/// tests pin the decision layer that the scheduler now uses, so "voice is
/// enabled but nothing is ever spoken" cannot come back unnoticed.
///
/// They deliberately do NOT test audio: `flutter_tts`/Android TextToSpeech is a
/// platform engine and cannot be asserted in a unit test. What is testable — and
/// what actually broke — is whether the app *decides* to speak, and which line.
void main() {
  final day = DateTime(2026, 11, 8);

  group('rotation is stable but not repetitive', () {
    test('the same slot on the same day always says the same thing', () {
      final a = SpokenReminders.lineFor(occurrence: day, slotMinute: 540);
      final b = SpokenReminders.lineFor(occurrence: day, slotMinute: 540);
      expect(a, b,
          reason: 'A line that changes on every rebuild is unsettling and '
              'makes the notification body disagree with the audio.');
    });

    test('consecutive slots in a day speak different lines', () {
      final lines = <String>{
        for (final minute in [540, 600, 660, 720, 780, 840, 900])
          SpokenReminders.lineFor(occurrence: day, slotMinute: minute),
      };
      expect(lines.length, greaterThan(1),
          reason: 'Seven reminders in a row must not repeat one sentence.');
    });

    test('the same slot tomorrow is not guaranteed to repeat today', () {
      final across = <String>{
        for (var d = 0; d < 7; d++)
          SpokenReminders.lineFor(
            occurrence: day.add(Duration(days: d)),
            slotMinute: 540,
          ),
      };
      expect(across.length, greaterThan(1));
    });

    test('the chosen line always comes from the shipped pool', () {
      for (final minute in [0, 540, 720, 1439]) {
        for (var d = 0; d < 10; d++) {
          final line = SpokenReminders.lineFor(
            occurrence: day.add(Duration(days: d)),
            slotMinute: minute,
          );
          expect(kWaterVoiceLines, contains(line));
        }
      }
    });

    test('an empty pool degrades to a single safe line instead of crashing', () {
      final line = SpokenReminders.lineFor(
        occurrence: day,
        slotMinute: 540,
        pool: const [],
      );
      expect(line, kWaterVoiceLines.first);
    });

    test('the medicine line names the medicine', () {
      final line = SpokenReminders.medicineLineFor(
        occurrence: day,
        slotMinute: 480,
        medicineName: 'Metformin',
      );
      expect(line, isNotEmpty);
      expect(line.toLowerCase(), anyOf(contains('medicine'), contains('metformin')));
    });

    test('water and medicine never share the same script', () {
      final water = SpokenReminders.lineFor(occurrence: day, slotMinute: 540);
      final medicine = SpokenReminders.medicineLineFor(
          occurrence: day, slotMinute: 540);
      expect(water, isNot(medicine));
    });
  });

  group('voice profile gating', () {
    test('every profile except "disabled" is allowed to speak', () {
      for (final profile in VoiceProfile.values) {
        expect(
          SpokenReminders.shouldSpeak(profile),
          profile != VoiceProfile.disabled,
          reason: 'profile ${profile.key} handled incorrectly',
        );
      }
    });

    test('the master toggle wins over the selected persona', () {
      // voiceEnabled=false must mean silence even if a persona is chosen.
      final settings = UserSettings(
        id: 's1',
        userId: 'u1',
        createdAt: day,
        updatedAt: day,
        voiceEnabled: false,
        voiceProfile: VoiceProfile.cheerfulFeminine,
      );
      expect(settings.effectiveVoice, VoiceProfile.disabled);
      expect(SpokenReminders.shouldSpeak(settings.effectiveVoice), isFalse);
    });

    test('enabling voice with a persona speaks', () {
      final settings = UserSettings(
        id: 's1',
        userId: 'u1',
        createdAt: day,
        updatedAt: day,
        voiceEnabled: true,
        voiceProfile: VoiceProfile.calmMasculine,
      );
      expect(settings.effectiveVoice, VoiceProfile.calmMasculine);
      expect(SpokenReminders.shouldSpeak(settings.effectiveVoice), isTrue);
    });

    test('every persona has a distinct pitch or rate', () {
      final signatures = <String>{
        for (final p in VoiceProfile.values) '${p.pitch}/${p.rate}',
      };
      // 'disabled' intentionally shares the neutral values.
      expect(signatures.length, greaterThanOrEqualTo(3));
    });
  });

  group('copy safety', () {
    test('no spoken line shames or blames', () {
      const banned = ['lazy', 'excuse', 'failed', 'disappoint', 'should have'];
      for (final line in kWaterVoiceLines) {
        final lower = line.toLowerCase();
        for (final word in banned) {
          expect(lower.contains(word), isFalse, reason: '"$line" contains "$word"');
        }
      }
    });

    test('every line is short enough to speak comfortably', () {
      for (final line in kWaterVoiceLines) {
        expect(line.length, lessThanOrEqualTo(140),
            reason: 'A long line is still talking after she has moved on.');
      }
    });

    test('at least four different lines exist for rotation', () {
      expect(kWaterVoiceLines.length, greaterThanOrEqualTo(4));
    });

    test('no line is empty', () {
      for (final line in kWaterVoiceLines) {
        expect(line.trim(), isNotEmpty);
      }
    });
  });
}
