package com.akasha.wellness

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Listens for wall-clock and timezone changes.
 *
 * Recurring reminders are scheduled with flutter_local_notifications using
 * absolute wall-clock times in the device's local zone. When the zone or the
 * clock itself moves, the previously scheduled instants become wrong, so we
 * ask the Dart side to rebuild the full schedule ("today + horizon").
 *
 * The Dart side listens on the shared-preferences channel written here, so no
 * FlutterEngine has to be spun up from the receiver.
 */
class TimeChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences("akasha_native_events", Context.MODE_PRIVATE)
        prefs.edit().putLong("reschedule_requested_at", System.currentTimeMillis()).apply()
    }
}
