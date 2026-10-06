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
 * couldn't make out ([onHeard] with an empty list), silence ([onSilence]) and the sound level ([onLevel]).
 */
class Listener(
    private val context: Context,
    private val onPartial: (String) -> Unit,
    private val onHeard: (List<String>) -> Unit,
    private val onSilence: () -> Unit,
    private val onLevel: (Float) -> Unit,
    private val onUnavailable: () -> Unit,
) {
    private var recognizer: SpeechRecognizer? = null
    var active = false
        private set

    fun start() {
        val r = recognizer ?: SpeechRecognizer.createSpeechRecognizer(context).also {
            it.setRecognitionListener(callbacks)
            recognizer = it
        }
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            .putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            .putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            .putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
            .putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 5)
            .putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
        active = true
        r.startListening(intent)
    }

    fun stop() {
        if (active) recognizer?.cancel()
        active = false
    }

    fun release() {
        recognizer?.destroy()
        recognizer = null
        active = false
    }

    private val callbacks = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) = onLevel(((rmsdB + 2f) / 12f).coerceIn(0f, 1f))
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit

        override fun onPartialResults(partialResults: Bundle?) {
            partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.let(onPartial)
        }

        override fun onResults(results: Bundle?) {
            active = false
            onHeard(results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION).orEmpty().filter { it.isNotBlank() })
        }

        override fun onError(error: Int) {
            if (!active) return
            active = false
            when (error) {
                SpeechRecognizer.ERROR_NO_MATCH -> onHeard(emptyList())
                // No permission, no recogniser for the language, or one that needs the internet when there is
                // none: answers are typed or tapped instead (the mic button tries again).
                SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS, SpeechRecognizer.ERROR_NETWORK,
                SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_SERVER,
                ERROR_SERVER_DISCONNECTED, ERROR_LANGUAGE_NOT_SUPPORTED, ERROR_LANGUAGE_UNAVAILABLE -> onUnavailable()
                // Silence, and passing trouble (the audio, a busy recogniser): as if nobody answered.
                else -> onSilence()
            }
        }
    }

    companion object {
        // SpeechRecognizer's codes from Android 12 (API 31), by value so older versions build.
        private const val ERROR_SERVER_DISCONNECTED = 11
        private const val ERROR_LANGUAGE_NOT_SUPPORTED = 12
        private const val ERROR_LANGUAGE_UNAVAILABLE = 13

        fun available(context: Context) = SpeechRecognizer.isRecognitionAvailable(context)
    }
}
