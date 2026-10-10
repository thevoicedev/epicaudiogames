package com.epicaudiogames.app

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * The app's own short sounds (content/app/earcons/, chosen with tools/app_audio.py; docs/DESIGN.md › Sounds, haptics
 * and the microphone). They play as they are, at 1x whatever the voice speed. iOS: Audio/CueBank.swift and
 * EpicAppCore's AppCue.
 */
enum class Earcon(val file: String) {
    /** The microphone opening: two notes rising. */
    LISTEN_START("listen-start"),
    /** The recogniser ending the listen, or the player turning the mic off: the same notes falling. */
    LISTEN_STOP("listen-stop"),
    /** A pack installed while the Shop or the store sheet shows. */
    SUCCESS("success"),
}

/**
 * Plays [Earcon]s from assets/app/earcons/<name>.wav (read once each, as they're first wanted), each on an AudioTrack
 * of its own with the whole sound in it (as HeadsetMic's silent track), so it starts at once. No audio focus: a sound
 * this short doesn't stop the game, or another app.
 *
 * While a Bluetooth headset's call link is held ([play]'s callLink), a sound goes over it as call audio, or it wouldn't
 * reach the headset. [play]'s done comes once the sound has been heard out: the recogniser starts after it, so it never
 * hears it.
 */
class Earcons(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    /** Each sound read so far: null for one the build doesn't have, or that can't be read. */
    private val sounds = mutableMapOf<Earcon, Wav.Pcm?>()

    /**
     * Plays [earcon]; [done] (if given) comes once it has been heard out: when the track has played its last frame,
     * plus a moment for the sound to leave the speaker (longer over the call link), or at the latest a little after
     * the sound's length should things go quiet. A sound that can't be played is done at once (posted). Returns a way
     * to cut it short, after which [done] doesn't come.
     */
    fun play(earcon: Earcon, callLink: Boolean = false, done: (() -> Unit)? = null): () -> Unit {
        val pcm = if (earcon in sounds) sounds[earcon] else read(earcon).also { sounds[earcon] = it }
        val track = pcm?.let { track(it, callLink) }
        if (pcm == null || track == null) {
            val now = Runnable { done?.invoke() }
            handler.post(now)
            return { handler.removeCallbacks(now) }
        }
        val frames = pcm.samples.size
        var over = false
        val finish = Runnable {
            if (over) return@Runnable
            over = true
            release(track)
            if (done != null) Log.i(TAG, "${earcon.file} heard out")
            done?.invoke()
        }
        val tail = if (callLink) CALL_LINK_TAIL_MS else TAIL_MS
        val watchdog = Runnable { finish.run() }
        track.setPlaybackPositionUpdateListener(object : AudioTrack.OnPlaybackPositionUpdateListener {
            override fun onMarkerReached(t: AudioTrack) {
                handler.removeCallbacks(watchdog)
                handler.postDelayed(finish, tail)
            }

            override fun onPeriodicNotification(t: AudioTrack) = Unit
        }, handler)
        track.notificationMarkerPosition = frames
        val started = runCatching { track.play() }.isSuccess
        Log.i(TAG, "${earcon.file}${if (callLink) " over the call link" else ""}")
        // The last frame's marker doesn't come on every phone: the watchdog ends it a little after its length.
        handler.postDelayed(watchdog, if (started) pcm.millis + WATCHDOG_MS else 0)
        return {
            if (!over) {
                over = true
                handler.removeCallbacks(watchdog)
                handler.removeCallbacks(finish)
                release(track)
            }
        }
    }

    private fun read(earcon: Earcon): Wav.Pcm? {
        val pcm = runCatching { context.assets.open("$FOLDER/${earcon.file}.wav").use { Wav.pcm16Mono(it.readBytes()) } }
            .onFailure { Log.w(TAG, "no ${earcon.file}.wav in this build", it) }
            .getOrNull()
        if (pcm == null) Log.w(TAG, "${earcon.file}: not a 16-bit mono WAV")
        return pcm
    }

    /** A track holding the whole sound: the game's audio, or call audio over the headset's link. */
    private fun track(pcm: Wav.Pcm, callLink: Boolean): AudioTrack? = runCatching {
        AudioTrack.Builder()
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(if (callLink) AudioAttributes.USAGE_VOICE_COMMUNICATION else AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            .setAudioFormat(
                AudioFormat.Builder()
                    .setSampleRate(pcm.rate)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                    .build(),
            )
            .setTransferMode(AudioTrack.MODE_STATIC)
            .setBufferSizeInBytes(pcm.samples.size * 2)
            .build()
            .apply { write(pcm.samples, 0, pcm.samples.size) }
    }.onFailure { Log.w(TAG, "can't make a track", it) }.getOrNull()

    private fun release(track: AudioTrack) {
        runCatching { track.stop() }
        track.release()
    }

    private companion object {
        const val TAG = "Earcons"
        const val FOLDER = "app/earcons"
        /** After the last frame has played: the sound still leaving the speaker. */
        const val TAIL_MS = 80L
        /** Over a headset's call link, which takes longer to carry it. */
        const val CALL_LINK_TAIL_MS = 150L
        /** How long after its length a sound whose end isn't reported counts as over. */
        const val WATCHDOG_MS = 500L
    }
}

/**
 * WAV files, read by hand: the RIFF chunks walked, any that aren't the format or the sound let go (LIST, fact, JUNK,
 * whatever a sound editor adds). Plain Kotlin, tested on the JVM (WavTest).
 */
object Wav {
    /** A sound: its 16-bit [samples], one channel, at [rate] per second. */
    class Pcm(val samples: ShortArray, val rate: Int) {
        val millis: Long get() = samples.size * 1000L / rate
    }

    /**
     * The sound in [bytes], if they're a WAV of 16-bit PCM in one channel (plain, or WAVE_FORMAT_EXTENSIBLE with PCM
     * inside); null for anything else. A data chunk that claims more than the file has is read as far as it goes.
     */
    fun pcm16Mono(bytes: ByteArray): Pcm? {
        if (bytes.size < 12 || tag(bytes, 0) != "RIFF" || tag(bytes, 8) != "WAVE") return null
        var rate = 0
        var at = 12
        while (at + 8 <= bytes.size) {
            val id = tag(bytes, at)
            val size = uint32(bytes, at + 4)
            val body = at + 8
            when (id) {
                "fmt " -> {
                    if (size < 16 || body + 16 > bytes.size) return null
                    var codec = uint16(bytes, body)
                    // WAVE_FORMAT_EXTENSIBLE: the codec is the first two bytes of its sub-format's GUID.
                    if (codec == EXTENSIBLE) codec = if (size >= 26 && body + 26 <= bytes.size) uint16(bytes, body + 24) else 0
                    val channels = uint16(bytes, body + 2)
                    val bits = uint16(bytes, body + 14)
                    if (codec != PCM || channels != 1 || bits != 16) return null
                    rate = uint32(bytes, body + 4).toInt()
                    if (rate <= 0) return null
                }
                "data" -> {
                    if (rate == 0) return null      // the sound before its format: not a WAV we know
                    val end = minOf(body + size, bytes.size.toLong()).toInt()
                    val count = (end - body) / 2
                    val samples = ShortArray(count) { i ->
                        val p = body + i * 2
                        ((bytes[p].toInt() and 0xFF) or (bytes[p + 1].toInt() shl 8)).toShort()
                    }
                    return Pcm(samples, rate)
                }
            }
            // Chunks are padded to an even length.
            val next = body + size + (size and 1)
            if (next > Int.MAX_VALUE) return null
            at = next.toInt()
        }
        return null
    }

    private const val PCM = 1
    private const val EXTENSIBLE = 0xFFFE

    private fun tag(b: ByteArray, at: Int) = String(b, at, 4, Charsets.US_ASCII)

    private fun uint16(b: ByteArray, at: Int) = (b[at].toInt() and 0xFF) or ((b[at + 1].toInt() and 0xFF) shl 8)

    private fun uint32(b: ByteArray, at: Int): Long =
        (uint16(b, at).toLong()) or (uint16(b, at + 2).toLong() shl 16)
}
