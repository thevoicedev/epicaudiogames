package com.epicaudiogames.app

import android.content.Context
import android.net.Uri
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import com.epicaudiogames.engine.Step

/**
 * Plays a turn's clips, one after another, from the game's assets (assets/<id>/<path>.m4a, .mp3 or .opus).
 * [position] says which clip is playing and where, so the transcript can follow it.
 */
class AudioPlayer(private val context: Context, private val gameId: String, private val onFinished: () -> Unit) {
    private val player = ExoPlayer.Builder(context)
        .setAudioAttributes(
            AudioAttributes.Builder().setUsage(C.USAGE_GAME).setContentType(C.AUDIO_CONTENT_TYPE_SPEECH).build(),
            true,
        )
        .build()
    private val files = mutableMapOf<String, Set<String>>()
    private var clips = 0

    init {
        player.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED && clips > 0) {
                    clips = 0
                    onFinished()
                }
            }
        })
    }

    fun play(steps: List<Step.Play>) {
        clips = steps.size
        player.setMediaItems(steps.map { MediaItem.fromUri(uri(it.path)) })
        player.prepare()
        player.play()
    }

    fun stop() {
        clips = 0
        player.stop()
        player.clearMediaItems()
    }

    /** The clip playing (its index in the turn) and the seconds into it. */
    fun position(): Pair<Int, Double>? =
        if (clips == 0) null else player.currentMediaItemIndex to player.currentPosition / 1000.0

    fun release() = player.release()

    private fun uri(path: String): Uri {
        val dir = "$gameId/" + path.substringBeforeLast('/', "")
        val name = path.substringAfterLast('/')
        val names = files.getOrPut(dir) { context.assets.list(dir.trimEnd('/'))?.toSet() ?: emptySet() }
        val file = listOf(".m4a", ".mp3", ".opus").map { name + it }.firstOrNull { it in names } ?: "$name.m4a"
        return Uri.parse("asset:///$dir/$file")
    }
}
