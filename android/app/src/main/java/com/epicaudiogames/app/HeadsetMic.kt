package com.epicaudiogames.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat

/**
 * A Bluetooth headset's microphone, while the game listens (Android 12+).
 *
 * Bluetooth headphones play the game over A2DP, which carries no mic: their mic only works over the headset's call
 * link (SCO, or LE Audio's), and the speech recogniser records from the phone's own mic unless that link is the
 * phone's communication device. So for each listen the headset is made the communication device, and the listen
 * waits (a moment at most) for the link; as the listen ends it's let go, so the game's voice plays in full quality
 * again. Over the call link, sound is narrowband and mono, and switching takes a moment each way: the first words
 * after a listen can come late or clipped. A wired headset's mic needs none of this: Android uses it by itself.
 *
 * Android 14 applies an app's communication device only while that app plays or records itself, and the recogniser
 * records in its own process: so a silent track plays while the link is held.
 */
class HeadsetMic(context: Context) {
    private val audio = context.getSystemService(AudioManager::class.java)
    private val executor = ContextCompat.getMainExecutor(context)
    private val handler = Handler(Looper.getMainLooper())
    private var routed: AudioDeviceInfo? = null
    private var silence: AudioTrack? = null
    /** The listen waiting for the link: it starts when the link comes, or when [WAIT_MS] is up. */
    private var waiting: Runnable? = null
    private var watcher: Any? = null

    /** Makes a connected Bluetooth headset's mic the one listened to, then runs [then]; without one, [then] at once. */
    fun use(then: () -> Unit) {
        cancelWait()
        val device = if (Build.VERSION.SDK_INT >= 31) headset() else null
        if (device == null || Build.VERSION.SDK_INT < 31) {
            release()
            then()
            return
        }
        route(device, then)
    }

    /** Lets the headset's call link go (the listen is over): the phone's mic, and full-quality sound, again. */
    fun release() {
        cancelWait()
        silence?.let { runCatching { it.stop() }; it.release() }
        silence = null
        if (routed != null && Build.VERSION.SDK_INT >= 31) {
            audio.clearCommunicationDevice()
            Log.i(TAG, "the phone's mic again")
        }
        routed = null
    }

    @RequiresApi(31)
    private fun headset(): AudioDeviceInfo? = audio.availableCommunicationDevices.firstOrNull {
        it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO || it.type == AudioDeviceInfo.TYPE_BLE_HEADSET
    }

    @RequiresApi(31)
    private fun route(device: AudioDeviceInfo, then: () -> Unit) {
        if (routed?.id == device.id && audio.communicationDevice?.id == device.id) {
            then()
            return
        }
        if (!audio.setCommunicationDevice(device)) {
            Log.w(TAG, "couldn't use ${device.productName}'s mic")
            then()
            return
        }
        routed = device
        if (silence == null) silence = playSilence()
        Log.i(TAG, "listening through ${device.productName}")
        if (audio.communicationDevice?.id == device.id) {
            then()
            return
        }
        val start = Runnable {
            cancelWait()
            then()
        }
        val listener = AudioManager.OnCommunicationDeviceChangedListener { d ->
            if (d?.id == device.id) start.run()
        }
        audio.addOnCommunicationDeviceChangedListener(executor, listener)
        watcher = listener
        waiting = start
        handler.postDelayed(start, WAIT_MS)
    }

    private fun cancelWait() {
        waiting?.let { handler.removeCallbacks(it) }
        waiting = null
        val w = watcher
        if (w != null && Build.VERSION.SDK_INT >= 31) {
            audio.removeOnCommunicationDeviceChangedListener(w as AudioManager.OnCommunicationDeviceChangedListener)
        }
        watcher = null
    }

    /** A silent call-audio track, looping: the app counts as playing while the recogniser records. */
    private fun playSilence(): AudioTrack? = runCatching {
        val frames = 1600     // 0.1 s at 16 kHz
        AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(16000)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(frames * 2)
            .build()
            .apply {
                write(ShortArray(frames), 0, frames)
                setLoopPoints(0, frames, -1)
                play()
            }
    }.onFailure { Log.w(TAG, "no silent track", it) }.getOrNull()

    private companion object {
        const val TAG = "HeadsetMic"
        /** How long a listen waits for the headset's link before it starts anyway. */
        const val WAIT_MS = 1500L
    }
}
