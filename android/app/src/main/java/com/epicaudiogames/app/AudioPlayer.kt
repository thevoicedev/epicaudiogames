package com.epicaudiogames.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.core.content.ContextCompat
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.exoplayer.ExoPlaybackException
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.source.SilenceMediaSource
import com.epicaudiogames.engine.Step
import java.io.File

/**
 * Plays a turn from the game's assets (assets/<id>/<path>.m4a, .mp3 or .opus), or from its installed packs
 * ([packs], whose files come first): its clips and pauses one after another, and its beds (music and overlapping
 * sounds) underneath, each from where it appears in the turn until the turn's audio ends. [position] says which clip
 * is playing and where, so the transcript can follow it.
 *
 * A clip with no file, or one that can't be played, takes no time: its lines show as it's passed. [onInterrupted]
 * says the game should wait for a tap: the audio focus lost for good (or refused, as during a call), or the
 * headphones taken out.
 */
@OptIn(UnstableApi::class)
class AudioPlayer(
    private val context: Context,
    private val gameId: String,
    private val packs: List<File>,
    private val onFinished: () -> Unit,
    private val onInterrupted: () -> Unit,
) {
    private val attributes = AudioAttributes.Builder().setUsage(C.USAGE_GAME).setContentType(C.AUDIO_CONTENT_TYPE_SPEECH).build()
    private val player = ExoPlayer.Builder(context).setAudioAttributes(attributes, true).build()
    private val sources = ProgressiveMediaSource.Factory(DefaultDataSource.Factory(context))
    private val files = mutableMapOf<String, Set<String>>()
    private val handler = Handler(Looper.getMainLooper())

    /** For each item of the playlist: its clip's index among the turn's clips, or -1 for a pause. */
    private var clipOf = IntArray(0)
    /** For each item of the playlist: how many of the turn's clips come before it (any passed over too). */
    private var doneAt = IntArray(0)
    /** The beds that start (or, for null, stop) when the playlist reaches an item. */
    private var bedsAt = mapOf<Int, List<Step.Bed>>()
    private val beds = mutableMapOf<String, ExoPlayer>()
    private var playing = false
    /** The item played on to after one that couldn't be played: each error moves on past the last. */
    private var skippedTo = 0
    private var released = false

    /** The headphones taken out: the game waits for a tap rather than carry on out loud. */
    private val noisy = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            if (intent.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) handler.post { if (!released) onInterrupted() }
        }
    }

    init {
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED && playing) {
                    playing = false
                    fadeOutBeds()
                    onFinished()
                }
            }

            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                // A new playlist's first item is play()'s to start.
                if (playing && reason != Player.MEDIA_ITEM_TRANSITION_REASON_PLAYLIST_CHANGED) {
                    startBeds(player.currentMediaItemIndex)
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                if (playing) passOver(error)
            }

            override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
                // The audio focus lost for good (another app's music), or refused: the voice won't come back.
                if (playing && !playWhenReady && reason == Player.PLAY_WHEN_READY_CHANGE_REASON_AUDIO_FOCUS_LOSS) {
                    interrupt()
                }
                syncBeds()
            }

            override fun onPlaybackSuppressionReasonChanged(reason: Int) = syncBeds()
        })
        ContextCompat.registerReceiver(
            context, noisy, IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY), ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    /** Plays a turn's steps (clips, pauses and beds; other steps are already resolved by the engine). */
    fun play(steps: List<Step>) {
        stopBeds()
        val items = mutableListOf<MediaSource>()
        val clips = mutableListOf<Int>()
        val done = mutableListOf<Int>()
        val starts = mutableMapOf<Int, MutableList<Step.Bed>>()
        var clipIndex = 0
        for (s in steps) {
            when (s) {
                is Step.Play -> {
                    // A clip with no file is passed over (its index still counts, for the transcript).
                    val u = uri(s.path)
                    if (u != null) {
                        items += sources.createMediaSource(MediaItem.fromUri(u))
                        clips += clipIndex
                        done += clipIndex
                    }
                    clipIndex++
                }
                is Step.Pause -> if (s.seconds > 0) {
                    items += SilenceMediaSource((s.seconds * 1_000_000).toLong())
                    clips += -1
                    done += clipIndex
                }
                is Step.Bed -> starts.getOrPut(items.size) { mutableListOf() } += s
                else -> Unit
            }
        }
        clipOf = clips.toIntArray()
        doneAt = done.toIntArray()
        bedsAt = starts
        skippedTo = 0
        if (items.isEmpty()) {
            handler.post(onFinished)
            return
        }
        playing = true
        player.setMediaSources(items)
        player.prepare()
        player.play()
        // The audio focus refused (a call has it): playWhenReady stays false, with no change to report.
        if (!player.playWhenReady) interrupt()
        startBeds(0)
    }

    fun stop() {
        playing = false
        player.stop()
        player.clearMediaItems()
        stopBeds()
    }

    /** The clip playing (its index among the turn's clips) and the seconds into it; null in a pause or when idle. */
    fun position(): Pair<Int, Double>? {
        if (!playing) return null
        val clip = clipOf.getOrNull(player.currentMediaItemIndex) ?: return null
        return if (clip < 0) null else clip to player.currentPosition / 1000.0
    }

    /** How many clips come before the item playing (for the transcript when a pause is playing). */
    fun clipsDone(): Int = doneAt.getOrElse(player.currentMediaItemIndex) { 0 }

    fun release() {
        released = true
        runCatching { context.unregisterReceiver(noisy) }
        stopBeds()
        player.release()
    }

    /**
     * An item that can't be played (a broken file, a decoder failing): the turn goes on from the item after it, as
     * for a clip with no file. Where the item isn't known, or it was the last, the turn ends there.
     */
    private fun passOver(error: PlaybackException) {
        val period = (error as? ExoPlaybackException)?.mediaPeriodId?.periodUid
        val failed = period?.let { player.currentTimeline.getIndexOfPeriod(it) } ?: C.INDEX_UNSET
        Log.w(TAG, "can't play item $failed of the turn", error)
        val next = failed + 1
        if (failed != C.INDEX_UNSET && next < player.mediaItemCount && next > skippedTo) {
            skippedTo = next
            player.seekToDefaultPosition(next)
            player.prepare()
            player.play()
        } else {
            playing = false
            fadeOutBeds()
            onFinished()
        }
    }

    /** The game is told once the player's own callbacks are done (it stops this player), if the turn still plays. */
    private fun interrupt() {
        handler.post { if (playing && !released) onInterrupted() }
    }

    /** The beds play while the voice does: a passing loss of the audio focus (a notification) holds them too. */
    private fun syncBeds() {
        val on = voicePlays()
        beds.values.forEach { it.playWhenReady = on }
    }

    private fun voicePlays() =
        player.playWhenReady && player.playbackSuppressionReason == Player.PLAYBACK_SUPPRESSION_REASON_NONE

    private fun startBeds(item: Int) {
        for (b in bedsAt[item].orEmpty()) {
            val path = b.path
            if (path == null) {
                stopBeds()
                continue
            }
            if (path in beds) continue           // already playing: it carries on
            val u = uri(path) ?: continue
            val p = ExoPlayer.Builder(context).setAudioAttributes(attributes, false).build()
            p.volume = b.volume.toFloat()
            p.setMediaSource(sources.createMediaSource(MediaItem.fromUri(u)))
            p.prepare()
            p.playWhenReady = voicePlays()
            beds[path] = p
        }
    }

    /** The beds stop with the turn, with a short fade (the skill cuts them where its speech ends). */
    private fun fadeOutBeds() {
        val fading = beds.values.toList()
        beds.clear()
        val start = fading.map { it.volume }
        val steps = 6
        for (k in 1..steps) {
            handler.postDelayed({
                fading.forEachIndexed { i, p -> p.volume = start[i] * (steps - k) / steps }
                if (k == steps) fading.forEach { it.release() }
            }, k * 25L)
        }
    }

    private fun stopBeds() {
        beds.values.forEach { it.release() }
        beds.clear()
    }

    /** The clip's file, from a pack or the game's assets; null (and a log line) when there's none. */
    private fun uri(path: String): Uri? {
        for (pack in packs) {
            for (ext in EXTENSIONS) {
                val f = File(pack, path + ext)
                if (f.isFile) return Uri.fromFile(f)
            }
        }
        val dir = "$gameId/" + path.substringBeforeLast('/', "")
        val name = path.substringAfterLast('/')
        val names = files.getOrPut(dir) { context.assets.list(dir.trimEnd('/'))?.toSet() ?: emptySet() }
        val file = EXTENSIONS.map { name + it }.firstOrNull { it in names }
        if (file == null) {
            Log.w(TAG, "no audio for $path")
            return null
        }
        return Uri.parse("asset:///$dir/$file")
    }

    private companion object {
        const val TAG = "AudioPlayer"
        val EXTENSIONS = listOf(".m4a", ".mp3", ".opus")
    }
}
