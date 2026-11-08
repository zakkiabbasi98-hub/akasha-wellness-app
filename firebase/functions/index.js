// Firebase Cloud Functions backend for the OPTIONAL AKASHA AI companion.
//
// Why a function instead of calling a model provider from the app:
//   * API keys stay server-side. The Flutter app ships with no secrets.
//   * Abuse/rate limiting and content safeguards live in one place.
//   * The endpoint can be swapped without shipping a new APK.
//
// Deploy
// ------
//   cd firebase
//   npm install
//   firebase login                     # your own Google account
//   firebase use --add                 # pick your project
//   firebase functions:secrets:set AI_PROVIDER_KEY
//   firebase deploy --only functions
//
// Then build the app with the endpoint:
//   flutter build apk --release \
//     --dart-define=AKASHA_AI_ENDPOINT=https://<region>-<project>.cloudfunctions.net/akashaCompanion
//
// The contract expected by lib/features/ai_companion/ai_service.dart:
//   POST { message: string, history: [{role, content}], system: string }
//   200  { reply: string }
//
// If you never deploy this, the app still works: the companion falls back to a
// local reflective responder and says so honestly.

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const fetch = require('node-fetch');

admin.initializeApp();

const SYSTEM_GUARDRAIL = `
You are a warm, gentle wellness companion inside a personal app for a young
woman named Akasha. Keep answers short (2-5 sentences), kind, and practical.
Never diagnose, never give medical or medication advice, never moralise or
shame. If she mentions self-harm or immediate danger, respond with concern,
urge her to contact a trusted person or local emergency services right now,
and stop offering exercises.
`;

// Explicit, conservative language check (mirrors the client-side guard so a
// crisis message is never sent to a model at all).
const CRISIS_PHRASES = [
  'kill myself', 'end my life', 'end it all', 'want to die', 'wanna die',
  'better off dead', 'suicide', 'suicidal', 'hurt myself', 'self harm',
  'no reason to live',
];

const CRISIS_REPLY =
  'If you are in immediate danger or thinking about harming yourself, please '
  + 'reach out to a real person right now — a trusted family member, a friend, or '
  + 'your local emergency number. This companion is not a crisis service and '
  + 'cannot contact anyone for you. You deserve support from a human being.';

exports.akashaCompanion = functions
  .region('us-central1')
  .runWith({
    secrets: ['AI_PROVIDER_KEY', 'AI_BASE_URL', 'AI_MODEL'],
    timeoutSeconds: 30,
  })
  .https.onRequest(async (req, res) => {
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    if (req.method === 'OPTIONS') {
      res.status(204).send('');
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const { message, history } = req.body || {};
    if (typeof message !== 'string' || message.trim().length === 0) {
      res.status(400).json({ error: 'message is required' });
      return;
    }
    if (message.length > 2000) {
      res.status(400).json({ error: 'message too long' });
      return;
    }

    const lower = message.toLowerCase();
    if (CRISIS_PHRASES.some((p) => lower.includes(p))) {
      res.status(200).json({ reply: CRISIS_REPLY, safety: 'crisis' });
      return;
    }

    // Optional: require an authenticated Firebase user so the endpoint cannot be
    // used by strangers. Uncomment when you enable Firebase Auth in the app.
    //
    // const auth = req.headers.authorization || '';
    // const token = auth.startsWith('Bearer ') ? auth.slice(7) : null;
    // if (!token) { res.status(401).json({ error: 'auth required' }); return; }
    // try { await admin.auth().verifyIdToken(token); }
    // catch { res.status(401).json({ error: 'invalid token' }); return; }

    const messages = [
      { role: 'system', content: SYSTEM_GUARDRAIL },
      ...(Array.isArray(history) ? history.slice(-10) : []).map((m) => ({
        role: m.role === 'assistant' ? 'assistant' : 'user',
        content: String(m.content || '').slice(0, 2000),
      })),
      { role: 'user', content: message },
    ];

    try {
      // Swap this block for whichever provider you prefer. The shape below is
      // the OpenAI-compatible chat-completions contract, which most providers
      // (and most self-hosted gateways) implement.
      const baseUrl =
        process.env.AI_BASE_URL || 'https://api.openai.com/v1/chat/completions';
      const model = process.env.AI_MODEL || 'gpt-4o-mini';
      const response = await fetch(baseUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${process.env.AI_PROVIDER_KEY}`,
        },
        body: JSON.stringify({
          model,
          messages,
          temperature: 0.7,
          max_tokens: 300,
        }),
      });

      if (!response.ok) {
        functions.logger.error('provider error', response.status);
        res.status(502).json({ error: 'provider unavailable' });
        return;
      }
      const data = await response.json();
      const reply = data?.choices?.[0]?.message?.content?.trim();
      if (!reply) {
        res.status(502).json({ error: 'empty reply' });
        return;
      }
      res.status(200).json({ reply });
    } catch (err) {
      functions.logger.error('companion failure', err);
      res.status(500).json({ error: 'temporary failure' });
    }
  });

// Optional: scheduled refresh of cloud-hosted motivational content.
// (The app already ships 104 messages locally, so this is a nice-to-have.)
exports.akashaMotivationFeed = functions
  .region('us-central1')
  .https.onRequest((req, res) => {
    res.status(200).json({
      version: 1,
      note: 'Add your own curated messages here, then point the app at this endpoint.',
      messages: [],
    });
  });
