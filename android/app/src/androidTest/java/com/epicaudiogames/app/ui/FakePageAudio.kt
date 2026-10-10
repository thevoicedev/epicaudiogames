package com.epicaudiogames.app.ui

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.epicaudiogames.app.AppClip
import com.epicaudiogames.app.HelpHighlight
import com.epicaudiogames.app.PageAudio

/**
 * A stand-in for AppAudio's reading aloud, for the screens' tests: it plays nothing, keeps what it was asked to play
 * ([played]), and its [clipPlaying] and [highlight] are the test's to set (Compose state, as AppAudio's are). With
 * [clips] false, the build has none.
 */
class FakePageAudio(private val clips: Boolean = true) : PageAudio {
    override var clipPlaying by mutableStateOf<AppClip?>(null)
    override var highlight by mutableStateOf<HelpHighlight?>(null)
    val played = mutableListOf<AppClip>()

    override fun hasClip(clip: AppClip) = clips

    override fun play(clip: AppClip) {
        played += clip
        clipPlaying = clip
        highlight = null
    }

    override fun stopClip() {
        clipPlaying = null
        highlight = null
    }
}
