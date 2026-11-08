# AKASHA — Privacy

*Plain language, written for the person using the app, not for a lawyer.*

---

## The short version

Your water log, your medicines, your journal, your moods, your gratitude list and
your reflections live in a private database file **on your phone**. Nobody — not
the developer, not an advertiser, not a "partner" — has a copy, because there is
nowhere for it to be sent. Cloud backup exists, but it is off until you turn it on
and sign in yourself.

**There is no advertising, no analytics and no trackers in this app.** There is no
crash-reporting SDK. There is no third-party SDK that phones home.

---

## What is stored on your device

| Data | Where | Why |
|---|---|---|
| Display name, onboarding answers | `users` table | To greet you and remember your preferences |
| Preferences (targets, quiet hours, voice, theme) | `user_settings` | To behave the way you configured |
| Water reminders and every glass you logged | `water_reminders`, `water_logs`, `water_snoozes` | The core feature |
| Medicines, their times, and every taken/skipped/snoozed/missed dose | `medicines`, `medicine_schedules`, `medicine_logs` | Your own schedule, as you entered it |
| Journal entries, moods, gratitude entries, reflections, breathing sessions | their tables | Mind & Soul features |
| Favourite messages, love notes | `motivational_messages`, `love_notes` | To remember what you liked |
| Reminder history (what fired, what you did) | `notification_history` | So the app can be honest in your reports; pruned after 90 days |
| AI conversation, **if** you enable the companion | `ai_messages` | So you can reread and delete it |

Everything is inside the app's private storage sandbox
(`/data/data/com.akasha.wellness/`), which other apps cannot read on a
non-rooted device.

**Nothing in this file is a secret you must protect alone:** if someone has your
unlocked phone, they can open the app. That is why there is an optional app lock
(Settings → Privacy) that uses your fingerprint or device PIN, with a 2-minute
grace period after you leave the app.

---

## What is never collected

* ❌ No location (the permission is not even requested)
* ❌ No microphone audio
* ❌ No contacts, SMS, call logs, photos or files
* ❌ No advertising identifier (no `AD_ID` permission)
* ❌ No device fingerprint, IMEI, MAC address or phone number
* ❌ No usage analytics, screen-view tracking or session recordings
* ❌ No third-party analytics or crash-reporting SDK
* ❌ No selling, renting, sharing or "anonymising" of health data — there is
  nothing to share

---

## The network, precisely

The app makes a network request only in these cases, and only when you have turned
the feature on:

| Situation | What is sent | To whom |
|---|---|---|
| Cloud sync enabled **and** signed in | Your records (water, medicine, moods, journal, gratitude, reflections, breathing, love notes) | Your **own** Firebase project's Firestore, under your own UID |
| AI companion enabled **and** consented | The text of the message you just typed, plus up to 10 recent turns | The Cloud Function endpoint you configured (`AKASHA_AI_ENDPOINT`) |

Nothing else. Ever. If both are off (the default), the app can run in aeroplane
mode indefinitely with every feature working.

### What the AI endpoint sees

* Your message and the recent conversation history you can see on screen.
* **Not** your water log, your medicines, your journal, or your name.
* Your message is **not** logged by the function. The function holds the model
  provider's API key server-side; the app never contains a key.
* **Crisis messages are never sent.** If the app detects crisis language, it
  shows supportive guidance and emergency contacts locally and stops — the model
  is never called. The server repeats the same check before calling a provider,
  so a modified client cannot bypass it.

---

## Cloud sync in detail

Sync is **off by default**. Turning it on requires:

1. A consent dialog explaining exactly what will leave the phone.
2. An account (email + password, managed by Firebase Authentication).
3. Your own Firebase project (see `docs/FIREBASE_SETUP.md`) — there is no
   developer-hosted server that receives anything.

When enabled:

* Records are stored at `users/{your-uid}/{entity}/{recordId}`.
* Security rules make that path readable **only** by a signed-in request whose
  `auth.uid` equals `{your-uid}`. Another account cannot read, write or even
  enumerate your data.
* Deletion is a tombstone, and "Delete cloud data" in Settings removes the whole
  subtree and the account.

---

## Your rights, in buttons

| Right | Where |
|---|---|
| **See** everything | Settings → Export my data (a JSON file with every row) |
| **Correct** anything | Edit or delete any individual record in the app |
| **Delete** everything | Profile → *Start over*, or Settings → *Delete my data* (with confirmation) |
| **Withdraw AI consent** | Settings → Privacy → *Withdraw consent* (disables the companion) |
| **Withdraw sync consent** | Settings → Cloud backup → turn off / delete cloud data |
| **Stop being notified** | Per-type toggles, quiet hours, pause all reminders |
| **Work offline** | Do not enable sync or AI — the app is complete without them |

There is no "account deletion request" email to send, because there is no server
holding your data that you do not control.

---

## Children

AKASHA is not directed at children under 13. It does not knowingly collect data
from anyone, so there is nothing to delete on request — but the app is intended
for its adult owner.

---

## Health disclaimer (privacy-adjacent, but important)

AKASHA is a **wellness and reminder tool**, not a medical device, and not a
substitute for professional care. It:

* does not diagnose anything;
* does not interpret your symptoms;
* does not recommend, adjust or calculate dosages — the dosage text is what *you*
  typed from your own prescription;
* does not tell you whether to take a missed dose. That is a question for your
  doctor or pharmacist.

If you are in danger or in crisis, contact your local emergency number or a crisis
line. The app can show you that information; it cannot contact anyone for you.

---

## Third-party components

| Package | Network? | Purpose |
|---|---|---|
| `flutter_local_notifications`, `timezone` | no | reminders |
| `sqflite` | no | local database |
| Android `TextToSpeech` (native, via a Kotlin receiver) | no | speaks reminders using the phone's own engine; the text never leaves the device |
| `local_auth` | no | fingerprint/PIN gate (biometric data is handled by Android, never by the app) |
| `permission_handler` | no | asking for permissions |
| `fl_chart`, `go_router`, `flutter_riverpod`, `intl`, `uuid`, `path_provider`, `share_plus` | no | UI, navigation, state, formatting, IDs, files, sharing the export you created |
| `firebase_core`, `firebase_auth`, `cloud_firestore` | **only if you configure and enable sync** | your own cloud backup |
| Cloud Function (`firebase/functions`) | **only if deployed and enabled** | AI replies |

You can remove the Firebase packages entirely and the app still works — see
`docs/BUILD_AND_RELEASE.md` §8.

---

## Reporting a privacy problem

If you believe the app is sending something it should not, do not file a public
issue with personal data in it. Contact the maintainer privately with the device
model, Android version and what you observed. A privacy bug is treated as the most
serious class of bug in this project.

---

*Last updated: version 1.0.0. If this file and the code ever disagree, the code is
wrong and will be fixed.*
