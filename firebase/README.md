# AKASHA backend (optional)

Nothing in this folder is required to run the app. AKASHA is offline-first: if
these files were deleted, the app would still install, remind, track and report
exactly as before.

This folder exists so you can add:

1. **Cloud backup & multi-device sync** — `firestore.rules` + `firestore.indexes.json`
2. **The AI wellness companion** — `functions/index.js` (keeps your model API key
   server-side; the app never contains a secret)

## Files

| File | Purpose |
|------|---------|
| `firestore.rules` | Strict per-user access. A signed-in user can only touch `users/{their-uid}/**`. Everything else is denied. |
| `firestore.indexes.json` | Composite indexes used by the sync queries. |
| `functions/index.js` | AI proxy (`akashaCompanion`) with a crisis-language guard. |
| `functions/package.json` | Function dependencies (Node 20). |
| `firebase.json` | Rules/indexes/functions wiring + emulator ports. |

See `../docs/FIREBASE_SETUP.md` for the step-by-step connection guide.
