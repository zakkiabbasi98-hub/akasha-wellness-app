import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../data/models/user_settings.dart';

/// Local text-to-speech for spoken reminders and the "preview" button in
/// Voice settings.
///
/// Everything uses the phone's already-installed TTS engine — no network, no
/// API keys, no audio files bundled. If the device has no usable engine (or the
/// chosen language is missing) every call fails silently and the app keeps
/// working; the settings screen tells Akasha that voice availability depends on
/// her phone.
class VoiceService {
  VoiceService();

  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool _available = false;

  bool get isAvailable => _available;

  Future<bool> init() async {
    if (_ready) return _available;
    _ready = true;
    try {
      _available = true;
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.46);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.08);
      return true;
    } catch (e) {
      debugPrint('AKASHA: TTS unavailable: $e');
      _available = false;
      return false;
    }
  }

  /// Returns the installed engines/languages, or an empty list if unsupported.
  Future<List<dynamic>> languages() async {
    try {
      final result = await _tts.getLanguages;
      return result is List ? result : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<List<dynamic>> voices() async {
    try {
      final result = await _tts.getVoices;
      return result is List ? result : const [];
    } catch (_) {
      return const [];
    }
  }

  /// Applies a voice persona. When the engine has a matching voice for the
  /// locale we prefer it; otherwise we keep the engine default and only adjust
  /// pitch/rate, which every engine supports.
  Future<void> applyProfile(VoiceProfile profile, {String languageCode = 'en'}) async {
    await init();
    if (!_available || profile == VoiceProfile.disabled) return;
    try {
      await _tts.setSpeechRate(profile.rate);
      await _tts.setPitch(profile.pitch);
      await _tts.setLanguage(
        languageCode == 'en' ? 'en-US' : languageCode,
      );
      // Nudge the engine toward a feminine/calm voice when the platform exposes
      // named voices. Silently ignored where unsupported.
      final installed = await voices();
      final desiredGender = switch (profile) {
        VoiceProfile.softFeminine || VoiceProfile.cheerfulFeminine => 'female',
        VoiceProfile.calmMasculine => 'male',
        _ => null,
      };
      if (desiredGender != null && installed.isNotEmpty) {
        for (final v in installed) {
          if (v is Map && v['gender']?.toString() == desiredGender) {
            await _tts.setVoice(Map<String, String>.from(
              v.map((k, value) => MapEntry(k.toString(), value.toString())),
            ));
            break;
          }
        }
      }
    } catch (e) {
      debugPrint('AKASHA: TTS profile failed: $e');
    }
  }

  /// Speak a line. Fire-and-forget: never blocks the UI and never throws.
  Future<void> speak(String text, {VoiceProfile? profile, String languageCode = 'en'}) async {
    await init();
    if (!_available) return;
    if (profile == VoiceProfile.disabled) return;
    if (profile != null) await applyProfile(profile, languageCode: languageCode);
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('AKASHA: TTS speak failed: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
  }
}
