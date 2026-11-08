package com.akasha.wellness

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Listens for wall-clock, timezone, boot and package-update broadcasts.
 *
 * Two different things need to happen when any of these fire:
 *
 * 1. **Dart-side rebuild.** Recurring reminders are scheduled as absolute
 *    wall-clock instants. When the zone or the clock moves, those instants stop
 *    matching the user's intention (a 09:00 reminder becomes 08:00). Dart does
 *    the rebuild, but a BroadcastReceiver cannot talk to Dart without spinning
 *    up a FlutterEngine — so we drop a timestamp marker in SharedPreferences
 *    that the Dart side consumes, exactly once, on the next launch or resume.
 *
 * 2. **Native voice re-arm.** The Kotlin spoken reminders (repair R3) are
 *    separate alarms, so after a reboot they must be re-armed immediately —
 *    the Dart side may not run for hours, and a spoken reminder that only
 *    exists once the app is opened is not a reminder.
 */
class TimeChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return

        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            "android.intent.action.QUICKBOOT_POWERON",
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> {
                val prefs = context.getSharedPreferences("akasha_native_events", Context.MODE_PRIVATE)
                prefs.edit()
                    .putLong("reschedule_requested_at", System.currentTimeMillis())
                    .putString("reason", action)
                    .apply()

                // Re-arm the native speech alarms now, without waiting for Dart.
                try {
                    VoiceReminderScheduler.rearmFromStore(context.applicationContext)
                } catch (e: Exception) {
                    Log.e("AkashaVoice", "re-arm after $action failed: ${e.message}")
                }
            }
        }
    }
}
