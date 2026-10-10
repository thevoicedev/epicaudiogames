package com.epicaudiogames.app

import androidx.activity.ComponentActivity
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The app's own sounds on a phone ([AppAudio]): its manifest and help pages from the build's assets, the intro's sting
 * once per process with its end said (or cut short when skipped), a help page read aloud with the word being read
 * marked, Settings' samples, and the short sounds. Everything on the main thread, as the screens call it. The sounds
 * play for real (an emulator started with -no-audio plays them to nothing, in real time).
 */
@RunWith(AndroidJUnit4::class)
class AppAudioTest {
    /**
     * A screen of the app's showing, as when a player reads help: Android 15 gives the audio focus only to the app on
     * screen (or one playing in a foreground service).
     */
    @get:Rule
    val screen = ActivityScenarioRule(ComponentActivity::class.java)

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val settings = AppSettings(MemoryPrefs())
    private lateinit var audio: AppAudio

    @Before
    fun setUp() {
        main { audio = AppAudio(instrumentation.targetContext.applicationContext, settings) }
    }

    @After
    fun tearDown() = main { audio.close() }

    @Test
    fun theBuildHasThisAppsPagesAndTheirClips() {
        val manifest = audio.manifest
        assertNotNull("no app.json in the build", manifest)
        manifest!!
        assertEquals("Using TalkBack", manifest.topic("screen-reader")?.title)
        for (page in manifest.help) assertTrue(page.id, audio.hasClip(AppClip.Help(page.id)))
        assertTrue(audio.hasClip(AppClip.Welcome))
        assertTrue(audio.hasClip(AppClip.Sample))
        assertFalse(audio.hasClip(AppClip.Help("no-such-topic")))
    }

    @Test
    fun theStingPlaysOncePerProcessAndSaysWhenItsDone() {
        AppAudio.introPlayed = false
        val done = AtomicBoolean(false)
        val plays = main { audio.playIntro { done.set(true) } }
        assertTrue("the sting didn't play", plays)
        assertTrue(main { audio.introPlaying })
        waitFor("the sting's end", 8_000) { done.get() }
        assertFalse(main { audio.introPlaying })
        // Only the process's first intro has it.
        assertFalse(main { audio.playIntro { } })
    }

    @Test
    fun skippingTheStingEndsItAtOnce() {
        AppAudio.introPlayed = false
        val done = AtomicBoolean(false)
        assertTrue(main { audio.playIntro { done.set(true) } })
        val skipped = System.currentTimeMillis()
        main { audio.skipIntro() }
        waitFor("the skipped sting's end", 2_000) { done.get() }
        // A quick fade, not the sting's three seconds.
        assertTrue(System.currentTimeMillis() - skipped < 1_500)
        assertFalse(main { audio.introPlaying })
    }

    @Test
    fun aHelpPageIsReadWithTheWordBeingReadMarked() {
        val topic = AppClip.Help("voice")
        main { audio.play(topic) }
        assertEquals(topic, main { audio.clipPlaying })
        // Its first paragraph, the marked word moving on through it.
        waitFor("the first word marked", 5_000) { main { audio.highlight } != null }
        val first = main { audio.highlight }!!
        assertEquals(0, first.paragraph)
        waitFor("the marked word moving on", 5_000) { main { audio.highlight }!!.chars > first.chars }
        main { audio.stopClip() }
        assertNull(main { audio.clipPlaying })
        assertNull(main { audio.highlight })
    }

    @Test
    fun anotherPageStopsTheOneBeingRead() {
        main { audio.play(AppClip.Help("voice")) }
        main { audio.play(AppClip.Welcome) }
        assertEquals(AppClip.Welcome, main { audio.clipPlaying })
        // A game opening stops everything.
        main { audio.stopAll() }
        assertNull(main { audio.clipPlaying })
    }

    @Test
    fun settingsSamplesOfTheStingAndTheMusicPlayAndEnd() {
        // Play the intro sound, turned on: the sting (three seconds and a bit), whatever the process's intro did.
        AppAudio.introPlayed = true
        main { audio.previewIntro() }
        assertTrue("the sting's sample didn't play", main { audio.previewing })
        waitFor("the sting's sample's end", 20_000) { !main { audio.previewing } }
        // Music volume at 50%: a few seconds of a game's music, then it fades out.
        main {
            settings.musicVolume = 0.5f
            audio.previewMusic()
        }
        assertTrue("the music's sample didn't play", main { audio.previewing })
        waitFor("the music's sample's end", 20_000) { !main { audio.previewing } }
        // Off: silence, and a sample still playing stops.
        main {
            audio.previewMusic()
            settings.musicVolume = 0f
            audio.previewMusic()
        }
        assertFalse(main { audio.previewing })
        // One sound at a time: a page read aloud stops a sample, and a sample a page.
        main {
            audio.previewIntro()
            audio.play(AppClip.Help("voice"))
        }
        assertFalse(main { audio.previewing })
        assertEquals(AppClip.Help("voice"), main { audio.clipPlaying })
        main { audio.previewIntro() }
        assertNull(main { audio.clipPlaying })
        main { audio.stopAll() }
        assertFalse(main { audio.previewing })
    }

    @Test
    fun theShortSoundsPlay() {
        main {
            audio.previewCue()
            audio.playSuccess()
            audio.previewVoiceSpeed()
        }
        assertEquals(AppClip.Sample, main { audio.clipPlaying })
        // The sample is one line, four and a half seconds: it's over soon (a busy emulator takes longer).
        waitFor("the sample's end", 20_000) { main { audio.clipPlaying } == null }
    }

    private fun <T> main(block: () -> T): T {
        var result: Result<T>? = null
        instrumentation.runOnMainSync { result = runCatching(block) }
        return result!!.getOrThrow()
    }

    private fun waitFor(what: String, millis: Long, condition: () -> Boolean) {
        val end = System.currentTimeMillis() + millis
        while (!condition()) {
            assertTrue("waited ${millis}ms for $what", System.currentTimeMillis() < end)
            Thread.sleep(50)
        }
    }
}
