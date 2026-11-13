import 'package:akasha/content/motivation_content.dart';
import 'package:akasha/data/models/mind_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the library contains at least 100 original messages', () {
    final total = kMotivationSeeds.values.fold<int>(0, (s, l) => s + l.length);
    expect(total, greaterThanOrEqualTo(100));
    // The category map must not be padded with empty lists to fake the count.
    for (final entry in kMotivationSeeds.entries) {
      expect(entry.value, isNotEmpty, reason: '${entry.key.label} is empty');
    }
  });

  test('every requested category is represented', () {
    for (final category in MotivationCategory.values) {
      expect(
        kMotivationSeeds.containsKey(category),
        isTrue,
        reason: '${category.label} has no messages',
      );
    }
  });

  test('no message is duplicated', () {
    final all = kMotivationSeeds.values.expand((l) => l).toList();
    expect(all.toSet().length, all.length);
  });

  test('messages are supportive, not pressuring', () {
    // Guard against guilt/shame phrasing creeping into the library.
    const banned = [
      'you must',
      'you should be ashamed',
      'lazy',
      'you failed',
      'failure',
      'disappoint',
      'no excuse',
      'excuses',
    ];
    for (final message in kMotivationSeeds.values.expand((l) => l)) {
      final lower = message.toLowerCase();
      for (final phrase in banned) {
        expect(
          lower.contains(phrase),
          isFalse,
          reason: 'Message contains "$phrase": $message',
        );
      }
    }
  });

  test('every message is reasonably short for a notification', () {
    for (final message in kMotivationSeeds.values.expand((l) => l)) {
      expect(message.length, lessThanOrEqualTo(160));
      expect(message.trim(), isNotEmpty);
    }
  });

  test('water voice lines exist and vary', () {
    expect(kWaterVoiceLines.length, greaterThanOrEqualTo(4));
    expect(kWaterVoiceLines.toSet().length, kWaterVoiceLines.length);
  });

  test('notification copy is well formed', () {
    for (final copy in kWaterNotificationCopy) {
      expect(copy, hasLength(2));
      expect(copy[0].isNotEmpty, isTrue);
      expect(copy[1].isNotEmpty, isTrue);
    }
    for (final copy in kMedicineNotificationCopy) {
      expect(copy, hasLength(2));
    }
  });

  test('crisis guidance exists and points to real human support', () {
    expect(kCrisisSupportMessage, contains('real person'));
    expect(kCrisisSupportMessage.toLowerCase(), contains('emergency'));
  });
}
