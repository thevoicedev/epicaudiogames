package com.epicaudiogames.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/**
 * Listens for one answer with the device's speech recogniser (on the device where it can).
 * Reports the words as they come ([onPartial]), the recogniser's guesses, best first ([onHeard]), speech it
 * couldn't make out ([onHeard] with an empty list), silence ([onSilence]), passing trouble that says nothing about
 * the player ([onTrouble]: the listen just ends) and the sound level ([onLevel]).
 *
 * It goes on with the screen off (the game's foreground service lets it use the mic), and hears a Bluetooth
 * headset's mic when there is one ([HeadsetMic]).
 */
class Listener(
    private val context: Context,
    private val onPartial: (String) -> Unit,
    private val onHeard: (List<String>) -> Unit,
    private val onSilence: () -> Unit,
    private val onLevel: (Float) -> Unit,
    private val onUnavailable: () -> Unit,
    private val onTrouble: () -> Unit,
) {
    private var recognizer: SpeechRecognizer? = null
    private val headset = HeadsetMic(context)
    /** Bumped by every start and stop: what the recogniser reports for a listen that's over is let go. */
    private var session = 0
    var active = false
        private set
    /** Words came while listening (a partial result that isn't blank): a NO_MATCH is then speech, not silence. */
    private var spoke = false

    fun start() {
        session++
        recognizer?.cancel()
        val id = ++session
        active = true
        spoke = false
        // With a Bluetooth headset, once its mic is in use (a moment at most); a stop meanwhile and it doesn't start.
        headset.use { if (id == session && active) listen(id) }
    }

    private fun listen(id: Int) {
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
        r.startListening(intent)
    }

    /** Stops listening, reporting nothing more (cancelling even a listen the recogniser had already given up). */
    fun stop() {
        session++
        recognizer?.cancel()
        active = false
        headset.release()
    }

    fun release() {
        session++
        recognizer?.destroy()
        recognizer = null
        active = false
        headset.release()
    }

    /** The recogniser's calls for listen [id]: only those for the listen going on now are reported. */
    private inner class Callbacks(private val id: Int) : RecognitionListener {
        private val current get() = active && id == session

        override fun onReadyForSpeech(params: Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) {
            if (current) onLevel(((rmsdB + 2f) / 12f).coerceIn(0f, 1f))
        }
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit

        override fun onPartialResults(partialResults: Bundle?) {
            if (!current) return
            val words = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull() ?: return
            if (words.isNotBlank()) spoke = true
            onPartial(words)
        }

        override fun onResults(results: Bundle?) {
            if (!current) return
            active = false
            headset.release()
            val guesses = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION).orEmpty().filter { it.isNotBlank() }
            // No words, and none came while listening: nobody spoke.
            if (guesses.isEmpty() && !spoke) onSilence() else onHeard(guesses)
        }

        override fun onError(error: Int) {
            if (!current) return
            active = false
            headset.release()
            when (error) {
                // Speech it couldn't make out; with no words at all, silence (many recognisers end a silent listen so).
                SpeechRecognizer.ERROR_NO_MATCH -> if (spoke) onHeard(emptyList()) else onSilence()
                // No offline recogniser for the language: the same listen again, with the network allowed.
                ERROR_LANGUAGE_NOT_SUPPORTED, ERROR_LANGUAGE_UNAVAILABLE -> if (offline) {
                    offline = false
                    start()
                } else {
                    onUnavailable()
                }
                // No permission, no recogniser for the language, or one that needs the internet when there is
                // none: answers are typed or tapped instead (the mic button tries again).
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS, SpeechRecognizer.ERROR_NETWORK,
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_SERVER,
                ERROR_SERVER_DISCONNECTED -> onUnavailable()
                // Passing trouble that says nothing about the player (a start turned down while the last listen
                // finishes, a busy recogniser, the mic in use, too many requests): the listen just ends.
                SpeechRecognizer.ERROR_CLIENT, SpeechRecognizer.ERROR_RECOGNIZER_BUSY, SpeechRecognizer.ERROR_AUDIO,
                ERROR_TOO_MANY_REQUESTS -> onTrouble()
                // Silence (ERROR_SPEECH_TIMEOUT), and anything else: as if nobody answered.
                else -> onSilence()
            }
        }
    }

    companion object {
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
