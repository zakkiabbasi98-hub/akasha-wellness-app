package com.akasha.wellness

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.util.Log
import java.util.Locale

/**
 * Speaks one water reminder, then re-arms tomorrow's.
 *
 * This runs with the app completely closed: Android starts the process for the
 * broadcast, we create our own [TextToSpeech] engine, speak, shut it down and
 * finish. No Flutter engine is started, which is what keeps it reliable on
 * phones that kill Flutter isolates aggressively.
 *
 * Design notes
 * ------------
 * * The TTS engine is created **per firing** and released immediately after.
 *   Holding one in a static field is the classic way to leak an engine and to
 *   break on a process that Android recreated.
 * * `UtteranceProgressListener.onDone` drives shutdown rather than a timer, so
 *   the engine is not torn down mid-sentence.
 * * If TTS is missing or fails to initialise, this logs and stops. The
 *   notification itself (handled by flutter_local_notifications) has already
 *   been shown by the OS at the same time, so the reminder is not lost — only
 *   the audio is, and Diagnostics says so.
 * * A hard timeout releases the engine even if `onDone` never fires (a known
 *   behaviour on some vendor engines).
 */
class VoiceReminderReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "AkashaVoice"
        private const val HARD_TIMEOUT_MS = 30_000L
    }

    private var engine: TextToSpeech? = null
    private var finished = false

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != VoiceReminderScheduler.ACTION_SPEAK) return

        val appContext = context.applicationContext
        val slotId = intent.getStringExtra("slotId") ?: "unknown"
        val minuteOfDay = intent.getIntExtra("minuteOfDay", -1)
        val text = intent.getStringExtra("text").orEmpty()
        val voiceKey = intent.getStringExtra("voiceKey") ?: "soft_feminine"
        val pitch = intent.getFloatExtra("pitch", 1.08f)
        val rate = intent.getFloatExtra("rate", 0.45f)

        // Always re-arm first: if anything below throws or the process is killed
        // mid-utterance, tomorrow's reminder still exists.
        if (minuteOfDay >= 0) {
            VoiceReminderScheduler.armNext(
                appContext,
                VoiceReminderScheduler.Slot(
                    slotId = slotId,
                    minuteOfDay = minuteOfDay,
                    text = text,
                    voiceKey = voiceKey,
                    pitch = pitch,
                    rate = rate
                )
            )
        }

        if (text.isBlank()) {
            Log.w(TAG, "spoken reminder with empty text; nothing to say")
            return
        }

        if (!VoiceReminderScheduler.canSpeakNow(appContext)) {
            Log.i(TAG, "silent mode or DND active — speech suppressed (notification still shown)")
            return
        }

        // pendingResult keeps the process alive while the engine initialises.
        val pending = goAsync()

        try {
            engine = TextToSpeech(appContext) { status ->
                // The OnInitListener can fire before the constructor returns, so
                // `engine` may not be assigned yet. Hop to the main looper to
                // guarantee the assignment completed; otherwise speakNow() would
                // see null and the reminder would silently not speak.
                Handler(Looper.getMainLooper()).post {
                    if (status != TextToSpeech.SUCCESS) {
                        Log.w(TAG, "TTS engine unavailable (status=$status); notification only")
                        release(pending)
                    } else {
                        speakNow(appContext, text, voiceKey, pitch, rate, pending)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "could not create TTS engine: ${e.message}")
            release(pending)
        }

        // Safety net for engines that never call onDone.
        Handler(Looper.getMainLooper()).postDelayed({ release(pending) }, HARD_TIMEOUT_MS)
    }

    private fun speakNow(
        context: Context,
        text: String,
        voiceKey: String,
        pitch: Float,
        rate: Float,
        pending: PendingResult
    ) {
        val tts = engine ?: run { release(pending); return }
        try {
            tts.language = Locale.US
            // flutter_tts maps its rate to a 0..1 scale; Android's TextToSpeech
            // wants roughly 0.5..2.0, so scale it rather than passing it through.
            tts.setSpeechRate((rate * 2f).coerceIn(0.5f, 2.0f))
            tts.setPitch(pitch.coerceIn(0.5f, 2.0f))

            // Prefer a voice matching the persona when the engine exposes one.
            val wantedGender = when (voiceKey) {
                "soft_feminine", "cheerful_feminine" -> "female"
                "calm_masculine" -> "male"
                else -> null
            }
            if (wantedGender != null) {
                tts.voices
                    ?.firstOrNull { it.locale.language == "en" && it.name.contains(wantedGender, true) }
                    ?.let { tts.voice = it }
            }

            tts.setOnUtteranceProgressListener(object : android.speech.tts.UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) = release(pending)
                @Deprecated("Required by the platform listener")
                override fun onError(utteranceId: String?) = release(pending)
                override fun onError(utteranceId: String?, errorCode: Int) = release(pending)
            })

            val mode = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                android.os.Bundle().apply { putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, android.media.AudioManager.STREAM_ALARM) }
            } else null

            tts.speak(text, TextToSpeech.QUEUE_FLUSH, mode, "akasha-$voiceKey")
        } catch (e: Exception) {
            Log.e(TAG, "speak failed: ${e.message}")
            release(pending)
        }
    }

    @Synchronized
    private fun release(pending: PendingResult) {
        if (finished) return
        finished = true
        try {
            engine?.stop()
            engine?.shutdown()
        } catch (e: Exception) {
            Log.w(TAG, "engine shutdown: ${e.message}")
        }
        engine = null
        try {
            pending.finish()
        } catch (_: Exception) {
        }
    }
}
