package com.akasha.wellness

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * Schedules **spoken** water reminders natively.
 *
 * Why this exists (repair R3)
 * ---------------------------
 * `flutter_tts` runs inside the Flutter engine. Once Android terminates the app
 * process there is no Dart to call, so a "spoken reminder" implemented in Dart
 * can only speak while the app happens to be alive — which is exactly when the
 * user is already looking at the screen and does not need to be told.
 *
 * The only supported way to speak at an alarm time with the app closed is a
 * native alarm that starts a BroadcastReceiver, which initialises its own
 * TextToSpeech engine. That is what this object schedules and what
 * [VoiceReminderReceiver] plays.
 *
 * Division of labour (important, and documented in docs/NOTIFICATIONS.md):
 *   * **Notification** delivery stays in Dart (flutter_local_notifications).
 *   * **Speech** is entirely native. Dart never speaks on an alarm, so a
 *     reminder can never be spoken twice.
 *   * Dart remains the single source of truth for *which* slots exist: it hands
 *     the plan down through [apply] whenever the schedule changes.
 *
 * Honest limitations:
 *   * Force-stopped apps get no alarms at all. Android gives no exception; the
 *     app says so in Diagnostics instead of pretending otherwise.
 *   * Silent mode / Do Not Disturb suppress speech. That is the user's
 *     decision and is never overridden.
 *   * If the device has no TTS engine, [isSpeechAvailable] is false and the
 *     notification body carries the line instead of audio.
 */
object VoiceReminderScheduler {

    private const val TAG = "AkashaVoice"
    private const val PREFS = "akasha_voice_reminders"
    private const val KEY_PLAN = "plan"
    private const val KEY_ENABLED = "enabled"

    const val ACTION_SPEAK = "com.akasha.wellness.SPEAK_REMINDER"
    const val ACTION_REARM = "com.akasha.wellness.REARM_VOICE"

    /** One spoken occurrence, as handed down by Dart. */
    data class Slot(
        val slotId: String,
        val minuteOfDay: Int,
        val text: String,
        val voiceKey: String,
        val pitch: Float,
        val rate: Float
    )

    /**
     * Replaces the whole native voice plan.
     *
     * [planJson] is a JSON array of `{slotId, minuteOfDay, text, voiceKey,
     * pitch, rate}`. Being a full replacement (never a merge) is what keeps
     * "edit a slot" and "delete a slot" correct: the old alarm ids are
     * cancelled first, then the new set is registered.
     */
    @Synchronized
    fun apply(context: Context, planJson: String, enabled: Boolean) {
        cancelAll(context)
        if (!enabled) {
            prefs(context).edit().putBoolean(KEY_ENABLED, false).apply()
            Log.i(TAG, "spoken reminders disabled")
            return
        }

        val slots = mutableListOf<Slot>()
        try {
            val array = JSONArray(planJson)
            for (i in 0 until array.length()) {
                val o = array.getJSONObject(i)
                slots += Slot(
                    slotId = o.getString("slotId"),
                    minuteOfDay = o.getInt("minuteOfDay"),
                    text = o.optString("text", ""),
                    voiceKey = o.optString("voiceKey", "soft_feminine"),
                    pitch = o.optDouble("pitch", 1.08).toFloat(),
                    rate = o.optDouble("rate", 0.45).toFloat()
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "could not parse voice plan: ${e.message}")
            return
        }

        prefs(context).edit()
            .putBoolean(KEY_ENABLED, true)
            .putString(KEY_PLAN, planJson)
            .apply()

        for (slot in slots) {
            armNext(context, slot)
        }
        Log.i(TAG, "spoken reminders armed for ${slots.size} slot(s)")
    }

    /**
     * Arms the next occurrence of [slot] (today if still ahead, otherwise
     * tomorrow) and leaves a note so [VoiceReminderReceiver] can re-arm itself
     * after it fires — that daily chain is what keeps speech working for weeks
     * without the app being opened.
     */
    fun armNext(context: Context, slot: Slot) {
        val now = Calendar.getInstance()
        val at = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, slot.minuteOfDay / 60)
            set(Calendar.MINUTE, slot.minuteOfDay % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            // The midnight slot (minute 0) belongs to the *next* midnight once
            // today has started — the midnight reminder is inclusive.
            if (!after(now)) add(Calendar.DAY_OF_YEAR, 1)
        }
        armAt(context, slot, at.timeInMillis)
    }

    private fun armAt(context: Context, slot: Slot, epochMillis: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingIntentFor(context, slot, epochMillis)

        try {
            when {
                // setAlarmClock survives Doze and is the most reliable option
                // for a user-facing reminder; the OS shows a small alarm icon,
                // which is honest about what the app is doing.
                canExact(am) -> am.setAlarmClock(
                    AlarmManager.AlarmClockInfo(epochMillis, pi), pi
                )
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, epochMillis, pi)
                else -> am.set(AlarmManager.RTC_WAKEUP, epochMillis, pi)
            }
        } catch (e: SecurityException) {
            // Exact-alarm permission was revoked between the check and here.
            // Degrade rather than crash: a late reminder beats none.
            Log.w(TAG, "exact alarm refused, falling back to inexact: ${e.message}")
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, epochMillis, pi)
                } else {
                    am.set(AlarmManager.RTC_WAKEUP, epochMillis, pi)
                }
            } catch (e2: Exception) {
                Log.e(TAG, "could not arm voice alarm: ${e2.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "could not arm voice alarm: ${e.message}")
        }
    }

    private fun canExact(am: AlarmManager): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) am.canScheduleExactAlarms() else true

    private fun pendingIntentFor(context: Context, slot: Slot, epochMillis: Long): PendingIntent {
        val intent = Intent(context, VoiceReminderReceiver::class.java).apply {
            action = ACTION_SPEAK
            putExtra("slotId", slot.slotId)
            putExtra("minuteOfDay", slot.minuteOfDay)
            putExtra("text", slot.text)
            putExtra("voiceKey", slot.voiceKey)
            putExtra("pitch", slot.pitch)
            putExtra("rate", slot.rate)
            // Distinct request codes per slot, so alarms do not replace each other.
            data = android.net.Uri.parse("akasha://voice/${slot.slotId}/$epochMillis")
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        return PendingIntent.getBroadcast(
            context,
            ("${slot.slotId}:$epochMillis").hashCode() and 0x7FFFFFFF,
            intent,
            flags
        )
    }

    /** Cancels every armed voice alarm. */
    fun cancelAll(context: Context) {
        val stored = prefs(context).getString(KEY_PLAN, null) ?: return
        try {
            val array = JSONArray(stored)
            for (i in 0 until array.length()) {
                val o = array.getJSONObject(i)
                // We cannot enumerate pending intents, so identify them by the
                // same (slotId, epoch) pairs we armed. Two days ahead is enough
                // because only one occurrence per slot is ever pending.
                for (offsetDays in 0..2) {
                    val cal = Calendar.getInstance().apply {
                        set(Calendar.HOUR_OF_DAY, o.getInt("minuteOfDay") / 60)
                        set(Calendar.MINUTE, o.getInt("minuteOfDay") % 60)
                        set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
                        add(Calendar.DAY_OF_YEAR, offsetDays)
                    }
                    val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val pi = pendingIntentFor(
                        context,
                        Slot(
                            slotId = o.getString("slotId"),
                            minuteOfDay = o.getInt("minuteOfDay"),
                            text = "",
                            voiceKey = "",
                            pitch = 1f,
                            rate = 1f
                        ),
                        cal.timeInMillis
                    )
                    am.cancel(pi)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "cancelAll: ${e.message}")
        }
    }

    /** Re-arms everything from the stored plan (used after boot / time change). */
    fun rearmFromStore(context: Context) {
        if (!prefs(context).getBoolean(KEY_ENABLED, false)) return
        val stored = prefs(context).getString(KEY_PLAN, null) ?: return
        try {
            val array = JSONArray(stored)
            for (i in 0 until array.length()) {
                val o = array.getJSONObject(i)
                armNext(
                    context,
                    Slot(
                        slotId = o.getString("slotId"),
                        minuteOfDay = o.getInt("minuteOfDay"),
                        text = o.optString("text", ""),
                        voiceKey = o.optString("voiceKey", "soft_feminine"),
                        pitch = o.optDouble("pitch", 1.08).toFloat(),
                        rate = o.optDouble("rate", 0.45).toFloat()
                    )
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "rearmFromStore: ${e.message}")
        }
    }

    /**
     * True when speech should actually happen right now.
     *
     * Respects the user's own phone settings rather than overriding them:
     * silent mode and Do Not Disturb both mean "not now", and the notification
     * (which the OS handles correctly) still appears.
     */
    fun canSpeakNow(context: Context): Boolean {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (audio.ringerMode != AudioManager.RINGER_MODE_NORMAL) return false
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as android.app.NotificationManager
        if (!nm.isNotificationPolicyAccessGranted) return true // cannot know; allow
        return nm.currentInterruptionFilter == android.app.NotificationManager.INTERRUPTION_FILTER_ALL
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
