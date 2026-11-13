# Notification sounds

AKASHA currently uses the **system notification sound** for every channel, which
means it behaves correctly on any device, respects the user's sound choice, and
adds nothing to the APK.

To use a custom sound:

1. Drop the file here, e.g. `assets/sounds/gentle_chime.mp3`.
2. Copy it to `android/app/src/main/res/raw/gentle_chime.mp3` (lowercase, no
   dashes — Android raw resource rules).
3. In `lib/core/notifications/notification_service.dart`, add to the relevant
   `AndroidNotificationDetails`:

       sound: const RawResourceAndroidNotificationSound('gentle_chime'),

4. Keep sounds short (< 5 s) and gentle. A water reminder should sound like a
   friend, not a fire alarm.

Never use a sound you do not have the right to redistribute.
