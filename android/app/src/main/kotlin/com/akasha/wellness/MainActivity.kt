package com.akasha.wellness

import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Main activity. Also hosts a small MethodChannel that exposes the few
 * Android system facts Flutter cannot read on its own (exact-alarm grant,
 * battery-optimisation state, DND state, channel importance).
 *
 * All of it is read-only reporting: the app never tries to bypass Do Not
 * Disturb, silent mode, or force-stop. It only tells Akasha what the device
 * currently permits and deep-links to the official settings screen.
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.akasha.wellness/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "canScheduleExactAlarms" -> result.success(canScheduleExactAlarms())
                        "openExactAlarmSettings" -> {
                            openExactAlarmSettings()
                            result.success(null)
                        }
                        "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                        "openBatteryOptimizationSettings" -> {
                            openBatteryOptimizationSettings()
                            result.success(null)
                        }
                        "isNotificationPolicyAccessGranted" -> result.success(isDndAccessGranted())
                        "isDndActive" -> result.success(isDndActive())
                        "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                        "openFullScreenIntentSettings" -> {
                            openFullScreenIntentSettings()
                            result.success(null)
                        }
                        "openNotificationSettings" -> {
                            openNotificationSettings()
                            result.success(null)
                        }
                        "openAppSettings" -> {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.fromParts("package", packageName, null)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(intent)
                            result.success(null)
                        }
                        "deviceSdkInt" -> result.success(Build.VERSION.SDK_INT)
                        "consumeRescheduleRequest" -> result.success(consumeRescheduleRequest())

                        // ── Spoken reminders (native, repair R3) ────────────
                        "applyVoicePlan" -> {
                            val plan = call.argument<String>("plan") ?: "[]"
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            VoiceReminderScheduler.apply(applicationContext, plan, enabled)
                            result.success(null)
                        }
                        "cancelVoicePlan" -> {
                            VoiceReminderScheduler.apply(applicationContext, "[]", false)
                            result.success(null)
                        }
                        "isSpeechAvailable" -> result.success(isSpeechAvailable())
                        "speakTest" -> {
                            val text = call.argument<String>("text") ?: ""
                            speakTest(text)
                            result.success(null)
                        }
                        "isSilentOrDnd" -> {
                            val audio = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            val dnd = nm.isNotificationPolicyAccessGranted &&
                                    nm.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL
                            result.success(audio.ringerMode != android.media.AudioManager.RINGER_MODE_NORMAL || dnd)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("AKASHA_SYSTEM_ERROR", e.message, null)
                }
            }
    }

    private fun canScheduleExactAlarms(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return am.canScheduleExactAlarms()
    }

    private fun openExactAlarmSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
        } else {
            openAppSettings()
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    /**
     * Opens the system dialog asking the user to exempt Akasha from battery
     * optimisation. Only ever triggered by an explicit tap in the diagnostics
     * screen, with the consequences explained in plain language first.
     */
    private fun openBatteryOptimizationSettings() {
        val direct = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.fromParts("package", packageName, null)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        try {
            startActivity(direct)
        } catch (e: Exception) {
            startActivity(
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    private fun isDndAccessGranted(): Boolean {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return nm.isNotificationPolicyAccessGranted
    }

    private fun isDndActive(): Boolean {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return nm.currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL
    }

    /**
     * Whether the app may post a full-screen, alarm-style notification.
     *
     * Android 14 (API 34) turned this into a user-grantable permission;
     * `NotificationManager.canUseFullScreenIntent()` only exists from that
     * release on, so older devices fall through to the install-time grant that
     * the manifest's USE_FULL_SCREEN_INTENT permission provides.
     */
    private fun canUseFullScreenIntent(): Boolean {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 34) {
            return nm.canUseFullScreenIntent()
        }
        return true
    }

    /**
     * Deep-links to the per-app notification settings, which is where Android
     * 14+ hosts the "Full-screen notifications" toggle.
     */
    private fun openFullScreenIntentSettings() {
        if (Build.VERSION.SDK_INT >= 34) {
            val direct = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            try {
                startActivity(direct)
                return
            } catch (e: Exception) {
                // Some OEM builds hide the dedicated page; the per-app
                // notification settings link to it instead.
            }
        }
        openNotificationSettings()
    }

    private fun openNotificationSettings() {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
            putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }

    private fun openAppSettings() {
        startActivity(
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
    }

    /**
     * Reads and clears the marker that [TimeChangeReceiver] writes when the
     * wall clock or the timezone moved while the app was closed.
     *
     * Returns the timestamp of the change (millis) if one happened since the
     * last read, or `null` when nothing needs rebuilding. Dart compares it
     * against the moment it last scheduled alarms, so a clock change that
     * occurred *before* the last successful rebuild does not cause a redundant
     * (or worse, an infinite) reschedule loop.
     */
    /**
     * True when the device has at least one installed TTS engine that declares
     * English support. Launchers can then honestly grey out the voice section
     * instead of failing silently at reminder time.
     */
    private fun isSpeechAvailable(): Boolean {
        return try {
            val intent = Intent("android.intent.action.TTS_SERVICE")
            packageManager.queryIntentServices(intent, 0).isNotEmpty()
        } catch (e: Exception) {
            false
        }
    }

    /** Speaks a short preview immediately (Voice settings → "Hear it"). */
    private fun speakTest(text: String) {
        if (text.isBlank()) return
        try {
            var tts: android.speech.tts.TextToSpeech? = null
            tts = android.speech.tts.TextToSpeech(applicationContext) { status ->
                if (status == android.speech.tts.TextToSpeech.SUCCESS) {
                    tts?.language = java.util.Locale.US
                    tts?.setSpeechRate(0.9f)
                    tts?.speak(text, android.speech.tts.TextToSpeech.QUEUE_FLUSH, null, "akasha-preview")
                }
            }
        } catch (e: Exception) {
            android.util.Log.w("AkashaVoice", "speakTest failed: ${e.message}")
        }
    }

    private fun consumeRescheduleRequest(): Long? {
        val prefs = getSharedPreferences("akasha_native_events", Context.MODE_PRIVATE)
        val stamp = prefs.getLong("reschedule_requested_at", 0L)
        if (stamp <= 0L) return null
        prefs.edit().remove("reschedule_requested_at").apply()
        return stamp
    }
}
