package com.epicaudiogames.app

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.source.SilenceMediaSource
import com.epicaudiogames.engine.Step

/**
 * Plays a turn from the game's assets (assets/<id>/<path>.m4a, .mp3 or .opus): its clips and pauses one after
 * another, and its beds (music and overlapping sounds) underneath, each from where it appears in the turn until the
 * turn's audio ends. [position] says which clip is playing and where, so the transcript can follow it.
 */
@OptIn(UnstableApi::class)
class AudioPlayer(private val context: Context, private val gameId: String, private val onFinished: () -> Unit) {
    private val attributes = AudioAttributes.Builder().setUsage(C.USAGE_GAME).setContentType(C.AUDIO_CONTENT_TYPE_SPEECH).build()
    private val player = ExoPlayer.Builder(context).setAudioAttributes(attributes, true).build()
    private val sources = ProgressiveMediaSource.Factory(DefaultDataSource.Factory(context))
    private val files = mutableMapOf<String, Set<String>>()
    private val handler = Handler(Looper.getMainLooper())

    /** For each item of the playlist: its clip's index among the turn's clips, or -1 for a pause. */
    private var clipOf = IntArray(0)
    /** The beds that start (or, for null, stop) when the playlist reaches an item. */
    private var bedsAt = mapOf<Int, List<Step.Bed>>()
    private val beds = mutableMapOf<String, ExoPlayer>()
    private var playing = false

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
                if (playing) startBeds(player.currentMediaItemIndex)
            }
        })
    }

    /** Plays a turn's steps (clips, pauses and beds; other steps are already resolved by the engine). */
    fun play(steps: List<Step>) {
        stopBeds()
        val items = mutableListOf<MediaSource>()
        val clips = mutableListOf<Int>()
        val starts = mutableMapOf<Int, MutableList<Step.Bed>>()
        var clipIndex = 0
        for (s in steps) {
            when (s) {
                is Step.Play -> {
                    items += sources.createMediaSource(MediaItem.fromUri(uri(s.path)))
                    clips += clipIndex++
                }
                is Step.Pause -> if (s.seconds > 0) {
                    items += SilenceMediaSource((s.seconds * 1_000_000).toLong())
                    clips += -1
                }
                is Step.Bed -> starts.getOrPut(items.size) { mutableListOf() } += s
                else -> Unit
            }
        }
        clipOf = clips.toIntArray()
        bedsAt = starts
        if (items.isEmpty()) {
            handler.post(onFinished)
            return
        }
        playing = true
        player.setMediaSources(items)
        player.prepare()
        player.play()
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

    /** Whether the turn has played at least up to this clip (for the transcript when a pause is playing). */
    fun clipsDone(): Int {
        val i = player.currentMediaItemIndex
        return clipOf.take(i).count { it >= 0 }
    }

    fun release() {
        stopBeds()
        player.release()
    }

    private fun startBeds(item: Int) {
        for (b in bedsAt[item].orEmpty()) {
            val path = b.path
            if (path == null) {
                stopBeds()
                continue
            }
            if (path in beds) continue           // already playing: it carries on
            val p = ExoPlayer.Builder(context).setAudioAttributes(attributes, false).build()
            p.volume = b.volume.toFloat()
            p.setMediaSource(sources.createMediaSource(MediaItem.fromUri(uri(path))))
            p.prepare()
            p.play()
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

    private fun uri(path: String): Uri {
        val dir = "$gameId/" + path.substringBeforeLast('/', "")
        val name = path.substringAfterLast('/')
        val names = files.getOrPut(dir) { context.assets.list(dir.trimEnd('/'))?.toSet() ?: emptySet() }
        val file = listOf(".m4a", ".mp3", ".opus").map { name + it }.firstOrNull { it in names } ?: "$name.m4a"
        return Uri.parse("asset:///$dir/$file")
    }
}
