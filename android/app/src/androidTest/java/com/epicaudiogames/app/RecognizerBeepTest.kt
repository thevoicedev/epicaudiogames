package com.epicaudiogames.app

import android.content.Context
import android.media.AudioManager
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The recogniser's own sounds kept from the player, on a phone (RecognizerBeep.kt): its notification sound muted while
 * the game listens and given back a moment after, nothing else touched (the ringer, the game's own sound, TalkBack's),
 * and a mute left by an app stopped mid-listen given back as the app starts. The phone is left as it was found. One
 * on vibrate or silent, with notification sounds off, or where the app leaves them alone, has nothing to check.
 * NotificationMuteTest (JVM) has the rules on every kind of phone.
 */
@RunWith(AndroidJUnit4::class)
class RecognizerBeepTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext.applicationContext
    private val audio = context.getSystemService(AudioManager::class.java)
    /** The mute's notes, as the app keeps them (RecognizerBeep's SharedPreferences). */
    private val notes = context.getSharedPreferences("listening", Context.MODE_PRIVATE)

    @Before
    fun setUp() {
        assumeTrue("the ringer isn't on", audio.ringerMode == AudioManager.RINGER_MODE_NORMAL)
        assumeFalse("notification sounds are off already", notificationsOff())
        assumeFalse("this phone's notification sound is left alone",
            notes.getString("listening.notificationsLeftAloneOn", null) == Build.FINGERPRINT)
    }

    @After
    fun tearDown() {
        main { RecognizerBeep.of(context).over(now = true) }
        if (audio.isStreamMute(AudioManager.STREAM_NOTIFICATION)) {
            audio.adjustStreamVolume(AudioManager.STREAM_NOTIFICATION, AudioManager.ADJUST_UNMUTE, 0)
        }
    }

    @Test
    fun notificationSoundsAreOffWhileTheGameListensAndComeBackAfter() {
        val musicMuted = audio.isStreamMute(AudioManager.STREAM_MUSIC)
        val ringMuted = audio.isStreamMute(AudioManager.STREAM_RING)
        main { RecognizerBeep.of(context).listen() }
        assertTrue("not muted while listening", audio.isStreamMute(AudioManager.STREAM_NOTIFICATION))
        assertTrue("no note of it", notes.getBoolean(HOLDING, false))
        // Only the notification sound: the ringer, the game's own sounds (the music stream) and TalkBack's are as
        // they were.
        assertEquals(AudioManager.RINGER_MODE_NORMAL, audio.ringerMode)
        assertEquals(musicMuted, audio.isStreamMute(AudioManager.STREAM_MUSIC))
        assertEquals(ringMuted, audio.isStreamMute(AudioManager.STREAM_RING))
        if (Build.VERSION.SDK_INT >= 26) assertFalse(audio.isStreamMute(AudioManager.STREAM_ACCESSIBILITY))
        // Over: still off for a moment, for the recogniser's closing sound, then back.
        main { RecognizerBeep.of(context).over() }
        assertTrue(audio.isStreamMute(AudioManager.STREAM_NOTIFICATION))
        waitFor("notification sounds back", 10_000) { !audio.isStreamMute(AudioManager.STREAM_NOTIFICATION) }
        assertFalse(notes.getBoolean(HOLDING, true))
    }

    @Test
    fun aMuteLeftByAnAppStoppedMidListenComesBackAsTheAppStarts() {
        // What an app stopped mid-listen leaves: notification sounds muted, and the note that the mute was the game's.
        notes.edit().putBoolean(HOLDING, true).commit()
        audio.adjustStreamVolume(AudioManager.STREAM_NOTIFICATION, AudioManager.ADJUST_MUTE, 0)
        assertTrue(audio.isStreamMute(AudioManager.STREAM_NOTIFICATION))
        main { RecognizerBeep.recover(context) }
        assertFalse(audio.isStreamMute(AudioManager.STREAM_NOTIFICATION))
        assertFalse(notes.getBoolean(HOLDING, true))
    }

    private fun notificationsOff() = audio.isStreamMute(AudioManager.STREAM_NOTIFICATION) ||
        audio.getStreamVolume(AudioManager.STREAM_NOTIFICATION) == 0

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

    private companion object {
        const val HOLDING = "listening.notificationsMuted"
    }
}
