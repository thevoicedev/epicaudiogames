package com.epicaudiogames.app

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log

/**
 * The speech recogniser's own sounds, kept from the player while the game listens (docs/DESIGN.md › Sounds, haptics
 * and the microphone): the game's listening sounds are the only ones.
 *
 * Google's recognisers (Speech Services by Google, most phones' own, and Android System Intelligence, the one on the
 * device) play a sound of their own as their mic opens, and another as a listen ends with nothing heard: after the
 * game's listening sound the player would hear Google's, and with Longer or Longest time to answer, one at each silent
 * restart. An app can't turn them off (Google's extra for it, com.google.recognition.extra.MUTE_AUDIO_BEEPS, is only
 * read for Google's own apps), and the recogniser on the device plays them too. But they play as notification sounds
 * (USAGE_NOTIFICATION_EVENT: the notification stream), so while the game listens the phone's notification sound is
 * muted, and it comes back a moment after the listen is over. The game's own sounds (the music stream, and the call
 * link's), TalkBack's (the accessibility stream) and calls are never touched. The whole listen is muted, not just its
 * ends: the closing sound can come before the app hears that the listen is over. How it's kept safe is
 * [NotificationMute]'s. Another recogniser may play sounds some other way: those stay (DESIGN.md's checklist for real
 * phones). iOS has nothing like it: SFSpeechRecognizer plays no sound of its own.
 */
object RecognizerBeep {
    private const val TAG = "RecognizerBeep"
    private var mute: NotificationMute? = null

    /** The process's mute (one for every game's listener, so a pending return is cancelled by the next listen). */
    fun of(context: Context): NotificationMute =
        mute ?: make(context.applicationContext).also { mute = it }

    /**
     * The app starting (MainActivity): a notification sound left muted by an app that was stopped mid-listen (a crash,
     * a force stop) comes back.
     */
    fun recover(context: Context) = of(context).recover()

    private fun make(context: Context): NotificationMute {
        val handler = Handler(Looper.getMainLooper())
        return NotificationMute(
            PhoneNotificationSound(context.getSystemService(AudioManager::class.java)),
            PrefsMuteNotes(context),
            build = Build.FINGERPRINT,
            later = { ms, run ->
                val r = Runnable { run() }
                handler.postDelayed(r, ms)
                val cancel: () -> Unit = { handler.removeCallbacks(r) }
                cancel
            },
            log = ::say,
        )
    }

    /** What the mute did, in the log (`adb logcat -s RecognizerBeep`). */
    private fun say(said: NotificationMute.Said) {
        when (said) {
            NotificationMute.Said.OFF -> Log.i(TAG, "notification sounds off while listening")
            NotificationMute.Said.BACK -> Log.i(TAG, "notification sounds back")
            NotificationMute.Said.LEFT_BY_A_STOPPED_APP ->
                Log.i(TAG, "notification sounds were left muted by a listen the app was stopped in")
            NotificationMute.Said.KEPT_ON_VIBRATE ->
                Log.i(TAG, "the phone went to vibrate or silent: its notification sound is left as it is")
            NotificationMute.Said.RINGERS ->
                Log.i(TAG, "this phone's notification sound is its ringer's: left alone, the recogniser's sounds stay")
            NotificationMute.Said.REFUSED ->
                Log.i(TAG, "this phone won't let its notification sound be muted: the recogniser's sounds stay")
        }
    }

    /** The phone's notification sound, through AudioManager. */
    private class PhoneNotificationSound(private val audio: AudioManager) : NotificationSound {
        override val ringerOn get() = audio.ringerMode == AudioManager.RINGER_MODE_NORMAL
        // Muted, or at no volume at all (by convention a muted stream's volume reads 0 too).
        override val muted get() = audio.isStreamMute(AudioManager.STREAM_NOTIFICATION) ||
            audio.getStreamVolume(AudioManager.STREAM_NOTIFICATION) == 0
        override val ringMuted get() = audio.isStreamMute(AudioManager.STREAM_RING)
        override val fixed get() = audio.isVolumeFixed

        override fun mute() = audio.adjustStreamVolume(AudioManager.STREAM_NOTIFICATION, AudioManager.ADJUST_MUTE, 0)

        override fun unmute() {
            runCatching { audio.adjustStreamVolume(AudioManager.STREAM_NOTIFICATION, AudioManager.ADJUST_UNMUTE, 0) }
                .onFailure { Log.w(TAG, "can't give the notification sound back", it) }
        }
    }

    /**
     * The notes, in SharedPreferences "listening": not in a backup (res/xml/backup_rules.xml takes only the saves and
     * the settings), as a note about this phone's sound means nothing on another.
     */
    private class PrefsMuteNotes(context: Context) : MuteNotes {
        private val prefs = context.getSharedPreferences("listening", Context.MODE_PRIVATE)

        override var holding: Boolean
            get() = prefs.getBoolean(HOLDING, false)
            // On the phone before the mute is made (commit, not apply): a crash just after still leaves the note.
            @SuppressLint("ApplySharedPref")
            set(value) {
                prefs.edit().putBoolean(HOLDING, value).commit()
            }

        override var leftAloneOn: String?
            get() = prefs.getString(LEFT_ALONE_ON, null)
            set(value) = prefs.edit().putString(LEFT_ALONE_ON, value).apply()

        private companion object {
            const val HOLDING = "listening.notificationsMuted"
            const val LEFT_ALONE_ON = "listening.notificationsLeftAloneOn"
        }
    }
}

/** The phone's notification sound, as [NotificationMute] sees and changes it (AudioManager; a fake in the tests). */
interface NotificationSound {
    /** The ringer is on: not on vibrate or silent. */
    val ringerOn: Boolean

    /** Notification sounds are off: muted (by the player, the ringer, Do Not Disturb or the game), or at no volume. */
    val muted: Boolean

    /** The ringer's sound is muted. */
    val ringMuted: Boolean

    /** The phone's volumes can't be changed. */
    val fixed: Boolean

    /** Mutes notification sounds. A phone that won't let it be done throws (SecurityException). */
    fun mute()

    /** Gives them back. */
    fun unmute()
}

/** What the mute writes down, kept while the app isn't running (SharedPreferences on the phone; memory in tests). */
interface MuteNotes {
    /** A mute of the game's is on (written before it's made, and cleared once it's given back). */
    var holding: Boolean

    /**
     * The Android build on which this phone wouldn't have it (its notification sound is the ringer's, or it refused):
     * it's left alone there, and tried again after an update.
     */
    var leftAloneOn: String?
}

/**
 * Mutes the notification sound while the recogniser listens ([listen]), and gives it back a moment after ([over]),
 * safely ([RecognizerBeep] says why; plain Kotlin, tested on the JVM: NotificationMuteTest):
 * - only with the ringer on, notification sounds on and volumes that can change: a player's own mute, vibrate, silent
 *   or Do Not Disturb is left as it is, and never undone;
 * - where the notification sound is the ringer's (one volume for both, as on many phones before Android 14), muting it
 *   would put the phone on vibrate: that's seen at once and undone, and the phone is left alone from then on (for
 *   that Android build), as it is if it refuses;
 * - written down before it's made ([MuteNotes.holding]), and the note goes once it's given back: one left by an app
 *   stopped mid-listen is given back as the app next starts ([recover]);
 * - given back only while the ringer is still on: a player who has put the phone on vibrate since keeps it so (and
 *   Android gives notification sounds back itself as the ringer comes on again);
 * - never more than [HOLD_LIMIT_MS] at a time, whatever becomes of the listen.
 * Everything comes on one thread (the main one); [later] runs what's due later on it.
 */
class NotificationMute(
    private val sound: NotificationSound,
    private val notes: MuteNotes,
    /** This Android build (Build.FINGERPRINT): what's learnt about the phone holds until it changes. */
    private val build: String,
    /** Runs something after a while, giving back a way to cancel it. */
    private val later: (ms: Long, run: () -> Unit) -> () -> Unit,
    /** What it does, for the log (RecognizerBeep words it). */
    private val log: (Said) -> Unit = {},
) {
    /** What the mute did, for the log. */
    enum class Said {
        /** Notification sounds muted, as a listen starts. */
        OFF,
        /** Given back after a listen. */
        BACK,
        /** A mute left by an app stopped mid-listen, found as the app starts (then given back, if it may be). */
        LEFT_BY_A_STOPPED_APP,
        /** Not given back: the phone has gone to vibrate or silent since. */
        KEPT_ON_VIBRATE,
        /** Left alone: the notification sound is the ringer's here. */
        RINGERS,
        /** Left alone: the phone won't let it be muted. */
        REFUSED,
    }

    /** A listen of this process's is on (a note left by another process isn't one). */
    var listening = false
        private set
    /** What's due next: the mute given back after a listen ([AFTER_MS]), or at the hold's limit. */
    private var due: (() -> Unit)? = null

    /** A listen starts, or goes on (a restart for more time to answer): notification sounds off, if they may be. */
    fun listen() {
        cancelDue()
        listening = true
        // However the listen goes, never longer than the limit at a time.
        due = later(HOLD_LIMIT_MS) {
            due = null
            listening = false
            giveBack()
        }
        if (notes.holding) {
            if (sound.muted) return           // the game's mute, still on (this listen's, or one from before)
            notes.holding = false             // given back meanwhile (the ringer turned off and on again)
        }
        if (notes.leftAloneOn == build || sound.fixed || !sound.ringerOn || sound.muted) return
        val ringMuted = sound.ringMuted
        notes.holding = true                  // written down first
        try {
            sound.mute()
        } catch (e: SecurityException) {
            notes.holding = false
            leaveAlone(Said.REFUSED)
            return
        }
        if (!sound.ringerOn || (sound.ringMuted && !ringMuted)) {
            // The notification sound is the ringer's here, and the phone went to vibrate with it: back at once.
            sound.unmute()
            notes.holding = false
            leaveAlone(Said.RINGERS)
            return
        }
        if (!sound.muted) {
            notes.holding = false             // it didn't take
            return
        }
        log(Said.OFF)
    }

    /**
     * The listen is over (heard, silence, stopped): notification sounds come back [AFTER_MS] later, once any closing
     * sound of the recogniser's has played, unless another listen has started; or [now] (the game closing).
     */
    fun over(now: Boolean = false) {
        listening = false
        cancelDue()
        if (!notes.holding) return
        if (now) {
            giveBack()
        } else {
            due = later(AFTER_MS) {
                due = null
                giveBack()
            }
        }
    }

    /**
     * The app starting: a mute left by an app that was stopped mid-listen is given back (unless one of this process's
     * listens holds it: the screen made again, as a tablet turns, while the game listens).
     */
    fun recover() {
        if (listening || due != null || !notes.holding) return
        log(Said.LEFT_BY_A_STOPPED_APP)
        giveBack()
    }

    private fun giveBack() {
        if (listening || !notes.holding) return
        when {
            !sound.muted -> notes.holding = false               // back already
            sound.ringerOn -> {
                sound.unmute()
                notes.holding = false
                log(Said.BACK)
            }
            // On vibrate or silent since: the player's now. The note stays, for the next time it's looked at.
            else -> log(Said.KEPT_ON_VIBRATE)
        }
    }

    private fun leaveAlone(why: Said) {
        notes.leftAloneOn = build
        log(why)
    }

    private fun cancelDue() {
        due?.invoke()
        due = null
    }

    companion object {
        /**
         * How long after a listen the notification sound comes back: the recogniser's closing sound (under half a
         * second) starts a few tenths of a second after the listen ends, later on a slow phone.
         */
        const val AFTER_MS = 1_500L

        /** The longest a mute is held at once (a listen with every restart for more time to answer is well under). */
        const val HOLD_LIMIT_MS = 60_000L
    }
}
