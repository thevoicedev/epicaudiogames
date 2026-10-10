package com.epicaudiogames.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.util.Log

/**
 * Listens for one answer with the device's speech recogniser (on the device where it can), the games' own way to
 * hear ([Hearing.SPEECH]). Reports through [events]: the words as they come (onPartial), the recogniser's guesses,
 * best first (onHeard), speech it couldn't make out (onHeard with an empty list), silence (onSilence), passing trouble
 * that says nothing about the player (onTrouble: the listen just ends) and the sound level (onLevel).
 *
 * Each listen opens with the listening sound (the events' cue: it plays, and the recogniser starts once it has been
 * heard out, so it never hears it; [ListenSequence]). It goes on with the screen off (the game's foreground service
 * lets it use the mic), and hears a Bluetooth headset's mic when there is one ([HeadsetMic]): the sound then waits for
 * the headset's call link, and goes over it. The recogniser's own sounds (Google's, as its mic opens and as a listen
 * ends with nothing heard) are kept from the player while it listens ([RecognizerBeep]): the game's are the only ones.
 */
class Listener(private val context: Context, private val events: ListenerEvents) : Listening {
    private var recognizer: SpeechRecognizer? = null
    private val headset = HeadsetMic(context)
    private val sequence = ListenSequence(headset::use, { headset.inUse }, events.cue, ::listen)
    /** The notification sound, muted while the recogniser listens (its own sounds play as notification sounds). */
    private val beep = RecognizerBeep.of(context)
    var active = false
        private set
    /** Words came while listening (a partial result that isn't blank): a NO_MATCH is then speech, not silence. */
    private var spoke = false
    /** When the recogniser first started for this listen (uptime ms); null until it has. */
    private var startedAt: Long? = null

    override val available: Boolean get() = available(context)

    /**
     * How long the recogniser should wait once the player stops talking before it takes the answer as complete (Time
     * to answer's Longer and Longest: a pause to think mid-answer doesn't cut it short); null for the recogniser's own.
     * Only a hint, which some recognisers don't take.
     */
    override var settleMs: Long? = null

    /**
     * Listens: the headset's link if there's a headset, the listening sound, then the recogniser. [withCue] false is
     * the same listen going on, without the sound: the recogniser started again (online, after the device turned out
     * not to have the language; or more time to answer, GameController's silence), its time counted from the first.
     */
    override fun start(withCue: Boolean) {
        recognizer?.cancel()
        active = true
        spoke = false
        if (withCue) startedAt = null
        sequence.start(withCue)
    }

    /** How long the recogniser has been listening, since it first started for this listen (0 before it has). */
    override fun heardFor(): Long = startedAt?.let { SystemClock.uptimeMillis() - it } ?: 0L

    private fun listen(id: Int) {
        if (!active || !sequence.isCurrent(id)) return
        if (startedAt == null) startedAt = SystemClock.uptimeMillis()
        val r = recognizer ?: SpeechRecognizer.createSpeechRecognizer(context).also { recognizer = it }
        // A listener for this listen alone: what the recogniser still reports for an earlier one goes to that one's.
        r.setRecognitionListener(Callbacks(id))
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            // Offline only while the device has the language: without it, the recogniser would never work.
            .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, offline)
            .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            .putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
        settleMs?.let {
            intent.putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, it)
                .putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, it)
        }
        // Muted before the recogniser starts (its sound comes as its mic opens), and for as long as it listens, a
        // restart for more time to answer included: until a moment after the listen is over.
        beep.listen()
        Log.i(TAG, "listening")
        r.startListening(intent)
    }

    /**
     * Stops listening, reporting nothing more (cancelling even a listen the recogniser had already given up), and
     * cutting the listening sound short if it's still playing.
     */
    override fun stop() {
        sequence.stop()
        recognizer?.cancel()
        active = false
        headset.release()
        beep.over()
    }

    override fun release() {
        sequence.stop()
        recognizer?.destroy()
        recognizer = null
        active = false
        headset.release()
        // The game is closing (and the app may be going): the notification sound comes back at once.
        beep.over(now = true)
    }

    /**
     * The recogniser is done: [report] says how. The headset's link is let go after, and the notification sound comes
     * back a moment later, unless the same listen went on meanwhile (more time to answer, or online after offline),
     * which keeps both.
     */
    private fun over(report: () -> Unit) {
        active = false
        report()
        if (!active) {
            headset.release()
            beep.over()
        }
    }

    /** The recogniser's calls for listen [id]: only those for the listen going on now are reported. */
    private inner class Callbacks(private val id: Int) : RecognitionListener {
        private val current get() = active && sequence.isCurrent(id)

        override fun onReadyForSpeech(params: Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) {
            if (current) events.onLevel(((rmsdB + 2f) / 12f).coerceIn(0f, 1f))
        }
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit

        override fun onPartialResults(partialResults: Bundle?) {
            if (!current) return
            val words = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: return
            if (words.isNotBlank()) spoke = true
            events.onPartial(words)
        }

        override fun onResults(results: Bundle?) {
            if (!current) return
            val guesses = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION).orEmpty().filter { it.isNotBlank() }
            Log.i(TAG, "the recogniser heard ${guesses.size} guesses")
            // No words, and none came while listening: nobody spoke.
            over { if (guesses.isEmpty() && !spoke) events.onSilence() else events.onHeard(guesses) }
        }

        override fun onError(error: Int) {
            if (!current) return
            Log.i(TAG, "the recogniser stopped: error $error")
            over {
                when (error) {
                    // Speech it couldn't make out; with no words at all, silence (many recognisers end a silent listen
                    // so).
                    SpeechRecognizer.ERROR_NO_MATCH -> if (spoke) events.onHeard(emptyList()) else events.onSilence()
                    // No offline recogniser for the language: the same listen again, with the network allowed (and no
                    // second listening sound).
                    ERROR_LANGUAGE_NOT_SUPPORTED, ERROR_LANGUAGE_UNAVAILABLE -> if (offline) {
                        offline = false
                        start(withCue = false)
                    } else {
                        events.onUnavailable()
                    }
                    // No permission, no recogniser for the language, or one that needs the internet when there is
                    // none: answers are typed or tapped instead (the mic button tries again).
                    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS, SpeechRecognizer.ERROR_NETWORK,
                    SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_SERVER,
                    ERROR_SERVER_DISCONNECTED -> events.onUnavailable()
                    // Passing trouble that says nothing about the player (a start turned down while the last listen
                    // finishes, a busy recogniser, the mic in use, too many requests): the listen just ends.
                    SpeechRecognizer.ERROR_CLIENT, SpeechRecognizer.ERROR_RECOGNIZER_BUSY, SpeechRecognizer.ERROR_AUDIO,
                    ERROR_TOO_MANY_REQUESTS -> events.onTrouble()
                    // Silence (ERROR_SPEECH_TIMEOUT), and anything else: as if nobody answered.
                    else -> events.onSilence()
                }
            }
        }
    }

    companion object {
        private const val TAG = "Listener"

        // SpeechRecognizer's codes from Android 12 (API 31), by value so older versions build.
        private const val ERROR_TOO_MANY_REQUESTS = 10
        private const val ERROR_SERVER_DISCONNECTED = 11
        private const val ERROR_LANGUAGE_NOT_SUPPORTED = 12
        private const val ERROR_LANGUAGE_UNAVAILABLE = 13

        /** Whether to ask for the recogniser on the device: until it turns out not to have the language. */
        private var offline = true

        fun available(context: Context) = SpeechRecognizer.isRecognitionAvailable(context)
    }
}
