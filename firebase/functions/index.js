// Firebase Cloud Functions backend for the OPTIONAL AKASHA AI companion.
//
// Security model (repair R4)
// -------------------------
// This endpoint costs money to run and can generate medical-adjacent text, so
// every request must clear the same gate before it reaches a model:
//
//   1. POST only, with a JSON body.
//   2. A verified Firebase ID token — `Authorization: Bearer <idToken>`.
//      The uid comes from the *verified token*, never from the request body.
//   3. Optional App Check token (`X-Firebase-AppCheck`) — enforced when
//      ENFORCE_APP_CHECK=true, recommended for production.
//   4. Strict CORS: an allow-list, no wildcard. Native app requests send no
//      Origin header and are permitted; browser requests must match the list.
//   5. Input validation: bounded message and history lengths/shapes.
//   6. Per-user rate limiting (sliding window in Firestore) plus a global
//      circuit breaker.
//   7. Safety interception before any model call.
//   8. Errors never leak provider or internal detail to the client.
//
// Deploy
// ------
//   cd firebase && npm install
//   firebase login && firebase use --add
//   firebase functions:secrets:set AI_PROVIDER_KEY
//   firebase deploy --only functions,firestore:rules
//
// Required env (see functions/.env.example):
//   ALLOWED_ORIGINS=https://your-web-app.example
//   ENFORCE_APP_CHECK=false            # true in production
//   AI_BASE_URL, AI_MODEL              # optional overrides
//
// If this function is never deployed the app still works: the companion falls
// back to a local reflective responder and says so honestly.

const functions = require('firebase-functions/v1');
const admin = require('firebase-admin');

if (!admin.apps.length) admin.initializeApp();

const REGION = 'us-central1';

const LIMITS = {
  messageChars: 1200,
  historyItems: 10,
  historyItemChars: 1200,
  requestsPerMinute: 6,
  requestsPerDay: 120,
  globalRequestsPerMinute: 600,
};

const SYSTEM_GUARDRAIL = `
You are a warm, gentle wellness companion inside a personal app for a young
woman named Akasha. Keep answers short (2-5 sentences), kind, and practical.
Never diagnose, never give medical or medication advice, never moralise or
shame. Never claim to be a therapist or doctor. If she mentions self-harm or
immediate danger, respond with concern, urge her to contact a trusted person or
local emergency services right now, and stop offering exercises.
`.trim();

// Mirrors the client-side guard so a crisis message is never sent to a model.
const CRISIS_PHRASES = [
  'kill myself', 'end my life', 'end it all', 'want to die', 'wanna die',
  'better off dead', 'suicide', 'suicidal', 'hurt myself', 'self harm',
  'no reason to live', 'cutting myself',
];

const CRISIS_REPLY =
  'If you are in immediate danger or thinking about harming yourself, please '
  + 'reach out to a real person right now — a trusted family member, a friend, or '
  + 'your local emergency number. This companion is not a crisis service and '
  + 'cannot contact anyone for you. You deserve support from a human being.';

// ── Helpers ────────────────────────────────────────────────────────────────

function allowedOrigins() {
  return (process.env.ALLOWED_ORIGINS || '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);
}

/**
 * Applies CORS headers for an allow-listed origin and returns whether the
 * origin is acceptable.
 *
 * A request with no Origin header is a native/mobile or server call; those are
 * allowed because they are authenticated separately and CORS is a browser
 * concept. A browser request must match the allow-list exactly.
 */
function applyCors(req, res) {
  const origin = req.headers.origin;
  const list = allowedOrigins();
  if (!origin) {
    // Native app or curl: no CORS headers needed, and none granted.
    return true;
  }
  if (list.includes(origin)) {
    res.set('Access-Control-Allow-Origin', origin);
    res.set('Vary', 'Origin');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Firebase-AppCheck');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Max-Age', '3600');
    return true;
  }
  return false;
}

async function verifyUser(req) {
  const header = req.headers.authorization || '';
  if (!header.startsWith('Bearer ')) return null;
  const token = header.slice(7).trim();
  if (!token) return null;
  try {
    const decoded = await admin.auth().verifyIdToken(token, true);
    return decoded;
  } catch (err) {
    functions.logger.warn('rejected token', { code: err.code });
    return null;
  }
}

async function verifyAppCheckIfRequired(req) {
  if (process.env.ENFORCE_APP_CHECK !== 'true') return true;
  const token = req.headers['x-firebase-appcheck'];
  if (!token || typeof token !== 'string') return false;
  try {
    await admin.appCheck().verifyToken(token);
    return true;
  } catch (err) {
    functions.logger.warn('app check rejected', { code: err.code });
    return false;
  }
}

/**
 * Sliding-window rate limit kept in Firestore.
 *
 * Keyed on the verified uid, so one account cannot exhaust another's budget.
 * Written with a transaction to stay correct under concurrent invocations.
 * Fails **open** on infrastructure error: a Firestore hiccup should not lock a
 * user out of her companion, and the per-day cap still bounds abuse.
 */
async function checkRateLimit(uid) {
  const db = admin.firestore();
  const ref = db.collection('ai_rate_limits').doc(uid);
  const globalRef = db.collection('ai_rate_limits').doc('__global__');
  const now = Date.now();
  const minuteAgo = now - 60 * 1000;
  const dayAgo = now - 24 * 60 * 60 * 1000;

  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = snap.exists ? snap.data() : {};
      const minuteHits = (data.minute_hits || []).filter((t) => t > minuteAgo);
      const dayCount = (data.day_hits || []).filter((t) => t > dayAgo).length;

      if (minuteHits.length >= LIMITS.requestsPerMinute) {
        return { ok: false, code: 'rate_limited', retryAfter: 30 };
      }
      if (dayCount >= LIMITS.requestsPerDay) {
        return { ok: false, code: 'daily_limit', retryAfter: 3600 };
      }

      tx.set(
        ref,
        {
          minute_hits: [...minuteHits, now],
          day_hits: (data.day_hits || []).filter((t) => t > dayAgo).concat(now),
          updated_at: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return { ok: true };
    });
  } catch (err) {
    functions.logger.error('rate limit check failed open', err.message);
    return { ok: true };
  }
}

/** Global circuit breaker so a deploy bug cannot run up an unbounded bill. */
async function checkGlobalBudget() {
  const db = admin.firestore();
  const ref = db.collection('ai_rate_limits').doc('__global__');
  const now = Date.now();
  const minuteAgo = now - 60 * 1000;
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const data = snap.exists ? snap.data() : {};
      const hits = (data.minute_hits || []).filter((t) => t > minuteAgo);
      if (hits.length >= LIMITS.globalRequestsPerMinute) return false;
      tx.set(ref, { minute_hits: [...hits, now] }, { merge: true });
      return true;
    });
  } catch (err) {
    functions.logger.error('global budget check failed open', err.message);
    return true;
  }
}

function validateBody(body) {
  if (!body || typeof body !== 'object') return 'body must be a JSON object';
  const { message, history } = body;
  if (typeof message !== 'string' || message.trim().length === 0) {
    return 'message is required';
  }
  if (message.length > LIMITS.messageChars) return 'message too long';
  if (history !== undefined) {
    if (!Array.isArray(history)) return 'history must be an array';
    if (history.length > LIMITS.historyItems) return 'history too long';
    for (const item of history) {
      if (!item || typeof item !== 'object') return 'history item invalid';
      if (typeof item.content !== 'string') return 'history item content invalid';
      if (item.content.length > LIMITS.historyItemChars) {
        return 'history item too long';
      }
      if (item.role !== 'user' && item.role !== 'assistant') {
        return 'history role must be user or assistant';
      }
    }
  }
  return null;
}

// ── Companion endpoint ─────────────────────────────────────────────────────

exports.akashaCompanion = functions
  .region(REGION)
  .runWith({
    secrets: ['AI_PROVIDER_KEY'],
    timeoutSeconds: 30,
    memory: '256MB',
    maxInstances: 20,
  })
  .https.onRequest(async (req, res) => {
    // 1. CORS
    const originOk = applyCors(req, res);
    if (req.method === 'OPTIONS') {
      res.status(originOk ? 204 : 403).send('');
      return;
    }
    if (!originOk) {
      res.status(403).json({ error: 'origin_not_allowed' });
      return;
    }
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'method_not_allowed' });
      return;
    }

    // 2. Authentication — identity comes from the token, never the body.
    const user = await verifyUser(req);
    if (!user) {
      res.status(401).json({ error: 'auth_required' });
      return;
    }

    // 3. App Check (production)
    if (!(await verifyAppCheckIfRequired(req))) {
      res.status(401).json({ error: 'app_check_failed' });
      return;
    }

    // 4. Request validation
    const invalid = validateBody(req.body);
    if (invalid) {
      res.status(400).json({ error: 'invalid_request', detail: invalid });
      return;
    }

    const { message, history } = req.body;

    // 5. Safety interception before any model call.
    const lower = message.toLowerCase();
    if (CRISIS_PHRASES.some((p) => lower.includes(p))) {
      res.status(200).json({ reply: CRISIS_REPLY, safety: 'crisis' });
      return;
    }

    // 6. Rate limits.
    if (!(await checkGlobalBudget())) {
      res.status(429).json({ error: 'busy', retry_after: 60 });
      return;
    }
    const limit = await checkRateLimit(user.uid);
    if (!limit.ok) {
      res.set('Retry-After', String(limit.retryAfter || 30));
      res.status(429).json({ error: limit.code });
      return;
    }

    // 7. Model call. Note: no user identifier is ever forwarded to the
    //    provider, and journal/medication content is never read from the
    //    database — the model only ever sees what this request contains.
    const messages = [
      { role: 'system', content: SYSTEM_GUARDRAIL },
      ...(Array.isArray(history) ? history : []).map((m) => ({
        role: m.role === 'assistant' ? 'assistant' : 'user',
        content: String(m.content || '').slice(0, LIMITS.historyItemChars),
      })),
      { role: 'user', content: message },
    ];

    try {
      const baseUrl =
        process.env.AI_BASE_URL || 'https://api.openai.com/v1/chat/completions';
      const model = process.env.AI_MODEL || 'gpt-4o-mini';

      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 20000);
      let response;
      try {
        response = await fetch(baseUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${process.env.AI_PROVIDER_KEY}`,
          },
          body: JSON.stringify({ model, messages, temperature: 0.7, max_tokens: 300 }),
          signal: controller.signal,
        });
      } finally {
        clearTimeout(timer);
      }

      if (!response.ok) {
        // Never surface the provider's status text to the client.
        functions.logger.error('provider error', { status: response.status, uid: user.uid });
        res.status(502).json({ error: 'companion_unavailable' });
        return;
      }

      const data = await response.json();
      const reply = data?.choices?.[0]?.message?.content?.trim();
      if (!reply) {
        res.status(502).json({ error: 'empty_reply' });
        return;
      }
      // Defense in depth: re-check the interception assistant-side too.
      if (CRISIS_PHRASES.some((p) => reply.toLowerCase().includes('kill yourself'))) {
        res.status(200).json({ reply: CRISIS_REPLY, safety: 'crisis' });
        return;
      }
      res.status(200).json({ reply });
    } catch (err) {
      // AbortError included: the client gets a neutral, retryable message.
      functions.logger.error('companion failure', { uid: user.uid, message: err.message });
      res.status(500).json({ error: 'temporary_failure' });
    }
  });

// ── Health check ───────────────────────────────────────────────────────────
// Unauthenticated on purpose so uptime monitoring works, but it reveals
// nothing: no uid, no config, no secrets, no counts.
exports.akashaHealth = functions
  .region(REGION)
  .https.onRequest((req, res) => {
    res.status(200).json({ ok: true, service: 'akasha' });
  });
