package com.epicaudiogames.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The recogniser's own sounds kept from the player (RecognizerBeep.kt): the notification sound, which Google's
 * recognisers play them on, muted while the game listens and given back a moment after, on every way a listen ends;
 * and never at the player's expense: their own mute, vibrate or silent left alone and never undone, a phone whose
 * notification sound is its ringer's left alone (the ringer put back at once), a mute left by an app stopped mid-listen
 * given back as it starts again. iOS has nothing like it (SFSpeechRecognizer plays no sound).
 */
class NotificationMuteTest {
    /** A phone: its ringer, its notification sound and (on [ringers]) whether the two are one. */
    private class Phone : NotificationSound {
        override var ringerOn = true
        override var muted = false
        override var ringMuted = false
        override var fixed = false
        /** The notification sound is the ringer's: muting it puts the phone on vibrate (Android's own volume rules). */
        var ringers = false
        /** The phone won't let it be muted (SecurityException, as for Do Not Disturb's rules). */
        var refuses = false
        var mutes = 0
        var unmutes = 0
        /** What the notes said as the mute was made. */
        var notedFirst: Boolean? = null
        var notes: MuteNotes? = null

        override fun mute() {
            if (refuses) throw SecurityException("Not allowed to change Do Not Disturb state")
            notedFirst = notes?.holding
            mutes++
            muted = true
            if (ringers) {
                ringerOn = false
                ringMuted = true
            }
        }

        override fun unmute() {
            unmutes++
            muted = false
            if (ringers) {
                ringerOn = true
                ringMuted = false
            }
        }
    }

    private class Notes : MuteNotes {
        override var holding = false
        override var leftAloneOn: String? = null
    }

    /** The main thread's clock: what's due runs as time is moved on. */
    private class Clock {
        var now = 0L
        val due = mutableListOf<Pair<Long, () -> Unit>>()

        fun later(ms: Long, run: () -> Unit): () -> Unit {
            val item = (now + ms) to run
            due += item
            return { due.remove(item) }
        }

        fun pass(ms: Long) {
            val until = now + ms
            while (true) {
                val next = due.filter { it.first <= until }.minByOrNull { it.first } ?: break
                due.remove(next)
                now = next.first
                next.second()
            }
            now = until
        }
    }

    private val phone = Phone()
    private val notes = Notes().also { phone.notes = it }
    private val clock = Clock()
    private val said = mutableListOf<NotificationMute.Said>()

    private fun mute(build: String = "android/15") = NotificationMute(phone, notes, build, clock::later) { said += it }

    private val beep = mute()

    @Test
    fun aListenMutesNotificationSoundsAndGivesThemBackAMomentAfter() {
        beep.listen()
        assertTrue(phone.muted)
        assertTrue(notes.holding)
        // The recogniser's closing sound comes a moment after the listen: still muted then.
        beep.over()
        clock.pass(NotificationMute.AFTER_MS - 1)
        assertTrue(phone.muted)
        clock.pass(1)
        assertFalse(phone.muted)
        assertFalse(notes.holding)
        assertEquals(1 to 1, phone.mutes to phone.unmutes)
        assertTrue(phone.ringerOn)
    }

    @Test
    fun theMuteIsWrittenDownBeforeItsMade() {
        beep.listen()
        assertEquals(true, phone.notedFirst)
    }

    @Test
    fun moreTimeToAnswerKeepsItMutedThroughEveryRestart() {
        beep.listen()
        // The recogniser gives up early and starts again, once and again: the same mute all along.
        beep.listen()
        beep.listen()
        assertEquals(1, phone.mutes)
        // A new listen soon after one's over (the next question): never given back in between.
        beep.over()
        clock.pass(500)
        beep.listen()
        clock.pass(NotificationMute.AFTER_MS * 2)
        assertTrue(phone.muted)
        assertEquals(1 to 0, phone.mutes to phone.unmutes)
        beep.over()
        clock.pass(NotificationMute.AFTER_MS)
        assertEquals(1 to 1, phone.mutes to phone.unmutes)
    }

    @Test
    fun thePlayersOwnMuteIsNeverTouched() {
        phone.muted = true
        beep.listen()
        beep.over()
        clock.pass(NotificationMute.AFTER_MS)
        beep.over(now = true)
        assertTrue(phone.muted)
        assertEquals(0 to 0, phone.mutes to phone.unmutes)
        assertFalse(notes.holding)
    }

    @Test
    fun onVibrateOrSilentOrWithFixedVolumesNothingIsMuted() {
        phone.ringerOn = false
        beep.listen()
        phone.ringerOn = true
        phone.fixed = true
        beep.listen()
        beep.over(now = true)
        assertEquals(0 to 0, phone.mutes to phone.unmutes)
        assertFalse(notes.holding)
    }

    @Test
    fun aPhoneWhoseNotificationSoundIsTheRingersIsPutBackAtOnceAndLeftAlone() {
        phone.ringers = true
        beep.listen()
        // Muting it took the ringer to vibrate: undone there and then.
        assertEquals(1 to 1, phone.mutes to phone.unmutes)
        assertTrue(phone.ringerOn)
        assertFalse(phone.muted)
        assertFalse(notes.holding)
        assertEquals("android/15", notes.leftAloneOn)
        // Never tried again on this Android build, whatever the listens.
        beep.over()
        beep.listen()
        beep.over(now = true)
        assertEquals(1 to 1, phone.mutes to phone.unmutes)
        // After an update it's tried again (Android 14 and later can keep the two apart).
        phone.ringers = false
        val updated = mute(build = "android/16")
        updated.listen()
        assertTrue(phone.muted)
        assertEquals(2, phone.mutes)
    }

    @Test
    fun aPhoneThatRefusesIsLeftAlone() {
        phone.refuses = true
        beep.listen()
        assertFalse(notes.holding)
        assertEquals("android/15", notes.leftAloneOn)
        phone.refuses = false
        beep.listen()
        assertEquals(0, phone.mutes)
    }

    @Test
    fun givenBackOnlyWhileTheRingerIsOn() {
        beep.listen()
        // The player puts the phone on vibrate mid-listen: theirs now, so it isn't undone.
        phone.ringerOn = false
        beep.over()
        clock.pass(NotificationMute.AFTER_MS)
        assertEquals(0, phone.unmutes)
        assertTrue(notes.holding)
        // The ringer back on, Android gives notification sounds back itself: the note goes as it's next looked at.
        phone.ringerOn = true
        phone.muted = false
        mute().recover()
        assertFalse(notes.holding)
        assertEquals(0, phone.unmutes)
    }

    @Test
    fun someoneElseGivingItBackMeanwhileClearsTheNote() {
        beep.listen()
        phone.muted = false
        beep.over()
        clock.pass(NotificationMute.AFTER_MS)
        assertEquals(0, phone.unmutes)
        assertFalse(notes.holding)
        // The next listen mutes it again.
        beep.listen()
        assertEquals(2, phone.mutes)
    }

    @Test
    fun aMuteLeftByAnAppStoppedMidListenIsGivenBackAsItStarts() {
        beep.listen()
        // The app is stopped (a crash, a force stop): nothing more from it. The next one starts.
        val next = mute()
        next.recover()
        assertFalse(phone.muted)
        assertFalse(notes.holding)
        assertEquals(1, phone.unmutes)
        assertEquals(listOf(NotificationMute.Said.OFF, NotificationMute.Said.LEFT_BY_A_STOPPED_APP, NotificationMute.Said.BACK),
            said)
    }

    @Test
    fun startingAgainWhileThisProcessListensChangesNothing() {
        // The screen made again (a tablet turning) while the game listens in the background.
        beep.listen()
        beep.recover()
        assertTrue(phone.muted)
        beep.over()
        beep.recover()
        assertTrue(phone.muted)
        clock.pass(NotificationMute.AFTER_MS)
        assertFalse(phone.muted)
    }

    @Test
    fun stoppedForGoodItComesBackAtOnce() {
        beep.listen()
        beep.over(now = true)
        assertFalse(phone.muted)
        assertFalse(notes.holding)
        assertTrue(clock.due.isEmpty())
    }

    @Test
    fun neverHeldLongerThanTheLimit() {
        beep.listen()
        clock.pass(NotificationMute.HOLD_LIMIT_MS - 1)
        assertTrue(phone.muted)
        clock.pass(1)
        assertFalse(phone.muted)
        assertFalse(beep.listening)
        // The listen's end, when it comes, has nothing left to do.
        beep.over()
        clock.pass(NotificationMute.AFTER_MS)
        assertEquals(1 to 1, phone.mutes to phone.unmutes)
    }

    @Test
    fun nothingIsNotedWhereNothingWasMuted() {
        phone.muted = true
        beep.listen()
        assertFalse(notes.holding)
        assertNull(notes.leftAloneOn)
        assertTrue(said.isEmpty())
    }
}
