import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../content/motivation_content.dart';

/// Whether a message needs an immediate, human-support response.
enum SafetyFlag { none, selfHarm, crisis }

/// The optional AI wellness companion.
///
/// Security model
/// --------------
/// The app NEVER contains an AI provider API key. Requests go to a backend
/// endpoint you deploy (Firebase Cloud Function or any HTTPS service) which
/// holds the secret server-side and forwards to the model provider. The
/// endpoint URL is injected at build time:
///
///   flutter run --dart-define=AKASHA_AI_ENDPOINT=https://...your-function...
///
/// If no endpoint is configured, or the network is down, or the user has not
/// consented, the companion degrades to a fully local, rule-based reflective
/// responder. That keeps the feature honest (never pretending to be a
/// therapist) and keeps the app usable offline.
class AiCompanionService {
  AiCompanionService({this.endpointOverride});

  static const String _endpointFromEnv =
      String.fromEnvironment('AKASHA_AI_ENDPOINT', defaultValue: '');

  final String? endpointOverride;

  String get endpoint => endpointOverride ?? _endpointFromEnv;

  bool get isConfigured => endpoint.trim().isNotEmpty;

  static const String systemPreamble = '''
You are a warm, gentle wellness companion inside a personal app for a young
woman named Akasha. Your tone is kind, calm, and non-judgemental. You help her
organise her thoughts, separate facts from assumptions, notice what she can
control, and take one small realistic step. You never diagnose, never
moralise, never shame, and never claim to be a therapist or doctor. You keep
answers short (2–5 sentences), ask at most one gentle question, and often
suggest a simple grounding exercise. If she mentions self-harm or immediate
danger, you respond with concern, encourage her to contact a trusted human or
local emergency services right now, and stop giving reflective exercises.
''';

  /// Detects language that suggests self-harm or immediate danger.
  ///
  /// Deliberately conservative: it only flags explicit statements, and the app
  /// always pairs the flag with real-world support guidance rather than
  /// pretending to handle a crisis.
  static SafetyFlag detectSafety(String text) {
    final lower = text.toLowerCase();
    const crisisPhrases = [
      'kill myself',
      'killing myself',
      'end my life',
      'end it all',
      'want to die',
      'wanna die',
      'better off dead',
      'suicide',
      'suicidal',
      'hurt myself',
      'self harm',
      'cutting myself',
      'no reason to live',
      'not want to be here anymore',
    ];
    for (final phrase in crisisPhrases) {
      if (lower.contains(phrase)) return SafetyFlag.crisis;
    }
    return SafetyFlag.none;
  }

  /// Sends a message and returns the companion's reply.
  Future<AiReply> send({
    required String message,
    required List<Map<String, String>> history,
  }) async {
    final safety = detectSafety(message);
    if (safety == SafetyFlag.crisis) {
      return const AiReply(
        text: kCrisisSupportMessage,
        safety: SafetyFlag.crisis,
        fromBackend: false,
      );
    }

    if (!isConfigured) {
      return AiReply(
        text: localReflection(message),
        safety: SafetyFlag.none,
        fromBackend: false,
      );
    }

    try {
      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'message': message,
              'history': history,
              'system': systemPreamble,
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        return AiReply(
          text: localReflection(message),
          safety: SafetyFlag.none,
          fromBackend: false,
          note: 'The companion is offline right now, so here is something gentler and simpler.',
        );
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final reply = (decoded['reply'] ?? decoded['text'] ?? '').toString().trim();
      if (reply.isEmpty) {
        return AiReply(text: localReflection(message), fromBackend: false, safety: SafetyFlag.none);
      }
      return AiReply(text: reply, safety: SafetyFlag.none, fromBackend: true);
    } catch (e) {
      debugPrint('AKASHA AI request failed: $e');
      return AiReply(
        text: localReflection(message),
        safety: SafetyFlag.none,
        fromBackend: false,
        note: 'No connection right now — here is a simpler reflection instead.',
      );
    }
  }

  /// Local fallback: reflective prompts, grounding ideas and gentle reframes.
  /// No model, no network, no pretending.
  String localReflection(String message) {
    final lower = message.toLowerCase();

    if (_matches(lower, ['anxious', 'anxiety', 'panic', 'nervous', 'scared'])) {
      return 'That sounds like a lot to carry. Let us slow things down for a '
          'moment: breathe in for four, hold for two, out for six. Do that three '
          'times. What is one thing around you right now that feels steady?';
    }
    if (_matches(lower, ['overthink', 'overthinking', 'thinking too much', 'replay', 'loop'])) {
      return 'Overthinking usually means something mattered to you. Try writing '
          'one sentence for "what happened" and one for "what I am assuming". '
          'Seeing them side by side often loosens the knot a little.';
    }
    if (_matches(lower, ['sad', 'cry', 'crying', 'lonely', 'alone', 'down'])) {
      return 'I am sorry it feels heavy right now. You do not have to fix it this '
          'minute. Would it help to name one small comfort you could give '
          'yourself in the next ten minutes?';
    }
    if (_matches(lower, ['tired', 'exhausted', 'no energy', 'burnout', 'burned out'])) {
      return 'Tiredness is information, not a failure. If you can, let one thing '
          'wait until tomorrow. What is the smallest version of today that would '
          'still feel okay?';
    }
    if (_matches(lower, ['angry', 'frustrated', 'irritated', 'annoyed'])) {
      return 'That frustration sounds real. Before deciding anything, try moving '
          'your body for a minute — stand up, roll your shoulders, drink some '
          'water. Then: what do you actually want to happen here?';
    }
    if (_matches(lower, ['cant sleep', "can't sleep", 'insomnia', 'awake'])) {
      return 'When sleep will not come, stop trying to force it. Dim the light, '
          'put the phone down, and breathe out a little longer than you breathe '
          'in. If you are still awake in twenty minutes, get up and sit quietly '
          'for a bit rather than fighting it in bed.';
    }
    if (_matches(lower, ['thank', 'thanks'])) {
      return 'I am glad this felt a little useful. Remember you did the work — '
          'I just kept you company. What is one small thing you can do next?';
    }

    return 'Thank you for telling me. Let us take it one piece at a time: what '
        'part of this feels heaviest right now, and what part is actually within '
        'your control today? We can stay with just that.';
  }

  bool _matches(String text, List<String> keys) => keys.any(text.contains);
}

class AiReply {
  const AiReply({
    required this.text,
    required this.safety,
    required this.fromBackend,
    this.note,
  });

  final String text;
  final SafetyFlag safety;
  final bool fromBackend;
  final String? note;

  bool get isCrisis => safety == SafetyFlag.crisis;
}
