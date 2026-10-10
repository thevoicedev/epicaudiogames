package com.epicaudiogames.app

import android.content.Context
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.OptIn
import androidx.annotation.VisibleForTesting
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import com.epicaudiogames.engine.Step
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** What [AppAudio] reads aloud: the welcome, a help page, or Settings' sample of the voice speed. */
sealed interface AppClip {
    data object Welcome : AppClip

    /** The help page [id] ("voice"). */
    data class Help(val id: String) : AppClip

    /** Settings › Sound and voice › Play a sample: the welcome's first line, at the voice speed chosen. */
    data object Sample : AppClip
}

/**
 * What a page read aloud needs of the app's audio (ui/HelpScreen.kt's Listen, and onboarding's welcome): [AppAudio],
 * or a test's stand-in. [clipPlaying] and [highlight] are Compose state.
 */
interface PageAudio {
    /** The clip being read aloud, if one is. */
    val clipPlaying: AppClip?

    /** Where the voice is in the page being read: the paragraph and how much of it has been said. */
    val highlight: HelpHighlight?

    /** Whether [clip] can be read aloud in this build. */
    fun hasClip(clip: AppClip): Boolean

    /** Reads [clip] aloud from its start (whatever was being read stops). */
    fun play(clip: AppClip)

    /** Stops reading aloud. */
    fun stopClip()
}

/**
 * The app's own sounds, outside a game's turns (docs/DESIGN.md › Sounds, haptics and the microphone; Help; Intro): the
 * intro's sting, the welcome and the help pages read aloud with the word being read marked, the success sound, and
 * Settings' samples. The screens call these; a game playing has its own (GameController). iOS: Audio/AppAudio.swift.
 *
 * - The sting plays once per process, without the audio focus (so it never stops another app's audio), and not at all
 *   while another app's music plays. [playIntro], [skipIntro], [introPlaying].
 * - The welcome and the help play through an AudioPlayer as the game "app" (assets/app/), at the voice speed, with the
 *   audio focus taken for a moment only, so another app's audio comes back after; a call, or the headphones taken out,
 *   stops them. [play], [stopClip], [clipPlaying], [highlight].
 * - Settings' samples of the sting and of the music at its volume ([previewIntro], [previewMusic]), one sound at a
 *   time with a page being read: each stops the other.
 * - Before a game opens, everything stops ([stopAll]).
 */
@OptIn(UnstableApi::class)
class AppAudio(private val context: Context, private val settings: AppSettings) : PageAudio {
    private val handler = Handler(Looper.getMainLooper())
    private val scope = MainScope()
    private val audioManager = context.getSystemService(AudioManager::class.java)
    private val earcons = Earcons(context)
    private val haptics = Haptics(context)
    private val loaded = lazy { AppManifest.load(context.assets) }

    /** The app's help and sounds (assets/app/app.json, this app's pages); null if the build has none. */
    val manifest: AppManifest? get() = loaded.value

    init {
        // Read away from the screen's thread as the app starts; a screen asking sooner waits for it.
        scope.launch(Dispatchers.Default) { loaded.value }
    }

    // ----- The intro's sting -----

    /** The sting is playing (the intro shows it). */
    var introPlaying by mutableStateOf(false)
        private set
    private var sting: ExoPlayer? = null
    private var introDone: (() -> Unit)? = null
    private val introWatchdog = Runnable { endIntro() }

    /**
     * Plays the sting, if it's the process's first, the build has one, and no other app's music is playing (the intro
     * then goes without it). Returns whether it plays: if so, [onDone] comes as it ends (or is skipped, or can't play
     * on), and not otherwise. The intro screen asks only with Settings' "Play the intro sound" on.
     */
    fun playIntro(onDone: () -> Unit): Boolean {
        if (introPlayed) return false
        introPlayed = true
        val s = manifest?.sting ?: return false
        if (audioManager?.isMusicActive == true) {
            Log.i(TAG, "another app's music is playing: no sting")
            return false
        }
        val player = ExoPlayer.Builder(context)
            .setAudioAttributes(
                AudioAttributes.Builder().setUsage(C.USAGE_GAME).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(),
                false,
            )
            .build()
        var started = false
        player.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                // Playing at last (a phone starting the app cold takes a moment to get it ready): it ends by itself,
                // or a moment after its length at the latest.
                if (!isPlaying || started || sting !== player) return
                started = true
                handler.removeCallbacks(introWatchdog)
                handler.postDelayed(introWatchdog, (s.seconds * 1000).toLong() + STING_WATCHDOG_MS)
            }

            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED && sting === player) endIntro()
            }

            override fun onPlayerError(error: PlaybackException) {
                // (A player let go slowly says so here too, once it's no longer the sting.)
                if (sting !== player) return
                Log.w(TAG, "can't play the sting", error)
                endIntro()
            }
        })
        player.setMediaItem(MediaItem.fromUri("asset:///${AppManifest.FOLDER}/${s.file}"))
        player.prepare()
        player.play()
        sting = player
        introDone = onDone
        introPlaying = true
        // Should it not start soon, the intro goes on without it; once it plays, should it never say it's done, the
        // intro still ends a moment after its length (onIsPlayingChanged).
        handler.postDelayed(introWatchdog, STING_START_MS)
        return true
    }

    /** The intro skipped (a tap, Escape): the sting fades out quickly, then the intro's onDone. */
    fun skipIntro() {
        val player = sting ?: return
        handler.removeCallbacks(introWatchdog)
        val start = player.volume
        for (k in 1..FADE_STEPS) {
            handler.postDelayed({
                if (sting === player) {
                    player.volume = start * (FADE_STEPS - k) / FADE_STEPS
                    if (k == FADE_STEPS) endIntro()
                }
            }, k * FADE_MS / FADE_STEPS)
        }
    }

    private fun endIntro() {
        handler.removeCallbacks(introWatchdog)
        val player = sting
        sting = null
        introPlaying = false
        val done = introDone
        introDone = null
        player?.release()
        done?.invoke()
    }

    // ----- The welcome, help pages and the voice speed's sample -----

    /** The clip being read aloud, if one is (a page's Listen button shows Pause for its own). */
    override var clipPlaying by mutableStateOf<AppClip?>(null)
        private set

    /** Where the voice is in the page being read ([HelpHighlight]): null when nothing is, or before it starts. */
    override var highlight by mutableStateOf<HelpHighlight?>(null)
        private set

    private var player: AudioPlayer? = null
    private var reading: HelpPage? = null
    private var ticker: Job? = null
    /** The files of the app's folder that clips play (app/tts, app/earcons), read once. */
    private val files: Set<String> by lazy {
        listOf("tts", "earcons").flatMap { dir ->
            runCatching { context.assets.list("${AppManifest.FOLDER}/$dir") }.getOrNull().orEmpty().map { "$dir/$it" }
        }.toSet()
    }

    /** Whether [clip] can be read aloud: the page is in the manifest, and its clips are in this build. */
    override fun hasClip(clip: AppClip): Boolean {
        val page = page(clip) ?: return false
        return page.hasClips && page.steps.filterIsInstance<Step.Play>().all { p -> EXTENSIONS.any { "${p.path}$it" in files } }
    }

    /**
     * Reads [clip] aloud from its start (whatever was being read stops), at the voice speed, with the word being read
     * in [highlight]. Not while a call has the audio.
     */
    override fun play(clip: AppClip) {
        val page = page(clip) ?: return
        stopClip()
        stopPreview()
        if (!takeFocus()) {
            Log.i(TAG, "the audio focus is someone else's: not reading $clip")
            return
        }
        val p = player ?: AudioPlayer(
            context, AppManifest.FOLDER, emptyList(),
            onFinished = ::clipEnded, onInterrupted = ::stopClip, handleFocus = false,
        ).also { player = it }
        clipPlaying = clip
        reading = page
        p.setSpeed(settings.voiceSpeed)
        p.play(page.steps)
        ticker = scope.launch {
            while (isActive) {
                follow(page, p)
                delay(TICK_MS)
            }
        }
    }

    /** Stops reading aloud (the Pause button, a page closing, a game opening, a call). */
    override fun stopClip() {
        if (clipPlaying == null) return
        player?.stop()
        clipEnded()
    }

    /** The page read to its end (or stopped): nothing marked, and other apps' audio back. */
    private fun clipEnded() {
        ticker?.cancel()
        ticker = null
        reading = null
        clipPlaying = null
        highlight = null
        dropFocus()
    }

    /** The word being read now; in a pause between paragraphs, the last one stays marked. */
    private fun follow(page: HelpPage, p: AudioPlayer) {
        val (clip, t) = p.position() ?: return
        HelpHighlight.of(page, clip, t)?.let { highlight = it }
    }

    /** The page a clip reads: Settings' sample is the welcome's first line alone. */
    private fun page(clip: AppClip): HelpPage? {
        val m = manifest ?: return null
        return when (clip) {
            AppClip.Welcome -> m.welcome
            is AppClip.Help -> m.topic(clip.id)
            AppClip.Sample -> m.welcome?.let { w ->
                val first = w.steps.firstOrNull { it is Step.Play && !it.sfx } ?: return null
                w.copy(steps = listOf(first), clipParagraph = w.clipParagraph.take(1))
            }
        }
    }

    // ----- Short sounds, and the samples Settings plays -----

    /** A pack installed while the Shop or the store sheet shows: the success sound, and a tick if ticks are on. */
    fun playSuccess() {
        earcons.play(Earcon.SUCCESS)
        if (settings.listeningHaptics) haptics.success()
    }

    /**
     * Settings › Listening sounds or Vibrate when listening starts, turned on: what the player will get as the mic
     * opens (the sound, the tick, each if it's on).
     */
    fun previewCue() {
        if (settings.listeningHaptics) haptics.micOpened()
        if (settings.listeningSounds) earcons.play(Earcon.LISTEN_START)
    }

    /** Settings › Voice speed › Play a sample: the welcome's first line at the speed chosen (again from its start). */
    fun previewVoiceSpeed() = play(AppClip.Sample)

    /** The voice speed changed: a page being read goes at the new speed at once. */
    fun speedChanged() {
        if (clipPlaying != null) player?.setSpeed(settings.voiceSpeed)
    }

    // ----- Settings' samples of the intro's sting and of the music's volume -----

    /** The sample playing, if one is. */
    private var preview: ExoPlayer? = null
    /** It holds the audio focus (the music's sample, as a page read aloud does). */
    private var previewFocus = false

    /** Whether one of Settings' samples (the sting, or the music) is playing. */
    val previewing: Boolean get() = preview != null

    /**
     * Settings › Play the intro sound, turned on: the sting, as the app will start with it (without the audio focus,
     * as the intro has it). Nothing if the build has none.
     */
    fun previewIntro() {
        val s = manifest?.sting ?: return
        stopPreview()
        stopClip()
        startPreview("${AppManifest.FOLDER}/${s.file}", volume = 1f, millis = (s.seconds * 1000).toLong())
    }

    /**
     * Settings › Music volume, a step picked: a few seconds of a game's music at that volume ([MUSIC_SAMPLE]: the
     * Werewolf's village, at its own volume in the game times the music volume), fading out; a sample playing starts
     * again at the new volume. Off: silence, as the music will be. With the audio focus for a moment, as Play a sample
     * has it, so another app's music doesn't play over it.
     */
    fun previewMusic() {
        stopPreview()
        val volume = settings.musicVolume
        if (volume <= 0f) return
        val file = musicSample ?: return
        stopClip()
        if (!takeFocus()) {
            Log.i(TAG, "the audio focus is someone else's: no music sample")
            return
        }
        previewFocus = true
        startPreview(file, MUSIC_SAMPLE_VOLUME * volume, MUSIC_SAMPLE_MS, fadeMs = MUSIC_FADE_MS)
    }

    /** The music sample's file in this build (as AudioPlayer finds a bed: its first extension there); null if none. */
    private val musicSample: String? by lazy {
        EXTENSIONS.map { MUSIC_SAMPLE + it }.firstOrNull { f -> runCatching { context.assets.openFd(f).close() }.isSuccess }
            .also { if (it == null) Log.w(TAG, "no $MUSIC_SAMPLE in this build: no music sample") }
    }

    /**
     * Plays [file] (in the assets) at [volume], as the game's audio, for [millis] at most: its end faded out over
     * [fadeMs], if given. What it replaces has been stopped by the caller.
     */
    private fun startPreview(file: String, volume: Float, millis: Long, fadeMs: Long? = null) {
        val p = ExoPlayer.Builder(context)
            .setAudioAttributes(
                AudioAttributes.Builder().setUsage(C.USAGE_GAME).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(),
                false,
            )
            .build()
        p.addListener(object : Player.Listener {
            override fun onPlaybackStateChanged(state: Int) {
                if (state == Player.STATE_ENDED && preview === p) stopPreview()
            }

            override fun onPlayerError(error: PlaybackException) {
                if (preview !== p) return
                Log.w(TAG, "can't play the sample", error)
                stopPreview()
            }
        })
        p.volume = volume
        p.setMediaItem(MediaItem.fromUri("asset:///$file"))
        p.prepare()
        p.play()
        preview = p
        if (fadeMs != null) {
            for (k in 1..FADE_STEPS) {
                handler.postDelayed({
                    if (preview === p) {
                        p.volume = volume * (FADE_STEPS - k) / FADE_STEPS
                        if (k == FADE_STEPS) stopPreview()
                    }
                }, millis - fadeMs + k * fadeMs / FADE_STEPS)
            }
        }
        // Should it never say it's done (a phone starting it slowly), it ends a moment after its length anyway.
        handler.postDelayed({ if (preview === p) stopPreview() }, millis + PREVIEW_WATCHDOG_MS)
    }

    /** The sample playing stops (another sample, a page read, a game opening, a call), and the focus goes back. */
    private fun stopPreview() {
        val p = preview ?: return
        preview = null
        p.release()
        if (previewFocus) {
            previewFocus = false
            if (clipPlaying == null) dropFocus()
        }
    }

    /** A game is opening: the sting, a sample and anything being read stop (the intro, if it was showing, is done). */
    fun stopAll() {
        if (sting != null) endIntro()
        stopClip()
        stopPreview()
    }

    /** The app's model is gone. */
    fun close() {
        stopAll()
        player?.release()
        player = null
        scope.cancel()
    }

    // ----- The audio focus, for a page read aloud and the music's sample -----

    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        // A call, or another app speaking (a navigation voice): the reading or sample stops; the player starts it again.
        if (change == AudioManager.AUDIOFOCUS_LOSS || change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
            stopClip()
            stopPreview()
        }
    }

    private val focusRequest: AudioFocusRequest? = if (Build.VERSION.SDK_INT >= 26) {
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(
                android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_GAME)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            .setOnAudioFocusChangeListener(focusListener, handler)
            .build()
    } else {
        null
    }

    /** The audio focus for a moment: another app's music pauses, and comes back once [dropFocus] lets it go. */
    private fun takeFocus(): Boolean {
        val am = audioManager ?: return true
        val result = if (Build.VERSION.SDK_INT >= 26 && focusRequest != null) {
            am.requestAudioFocus(focusRequest)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        }
        return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    private fun dropFocus() {
        val am = audioManager ?: return
        if (Build.VERSION.SDK_INT >= 26 && focusRequest != null) {
            am.abandonAudioFocusRequest(focusRequest)
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(focusListener)
        }
    }

    companion object {
        private const val TAG = "AppAudio"
        /** The sting plays on the process's first intro only (a test sets it back). */
        @VisibleForTesting
        internal var introPlayed = false
        /** How long after the sting's length an intro whose end isn't reported ends anyway. */
        private const val STING_WATCHDOG_MS = 1_000L
        /** A sting that hasn't started playing this long after it was asked for isn't played (the intro goes on). */
        private const val STING_START_MS = 2_000L
        /** Skipping fades the sting out over this long, in steps. */
        private const val FADE_MS = 150L
        private const val FADE_STEPS = 6
        /** How often the word being read is looked at. */
        private const val TICK_MS = 50L
        /** The clips' files, as AudioPlayer looks for them. */
        private val EXTENSIONS = listOf(".m4a", ".mp3", ".opus")
        /**
         * Music volume's sample: a game's bed (games/the-werewolf/map.json's village, music at an even level from its
         * start), at its volume there ([MUSIC_SAMPLE_VOLUME]), times the volume picked, for [MUSIC_SAMPLE_MS].
         */
        private const val MUSIC_SAMPLE = "the-werewolf/audio/village-bg"
        private const val MUSIC_SAMPLE_VOLUME = 1f
        private const val MUSIC_SAMPLE_MS = 4_000L
        /** The music sample's last half second fades out, as a bed does at a turn's end, only slower. */
        private const val MUSIC_FADE_MS = 500L
        /** A sample that hasn't said it's done this long after its length (a phone slow to start it) is stopped anyway. */
        private const val PREVIEW_WATCHDOG_MS = 2_000L
    }
}
