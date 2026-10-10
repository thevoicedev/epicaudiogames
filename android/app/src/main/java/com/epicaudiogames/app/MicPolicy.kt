package com.epicaudiogames.app

import androidx.annotation.StringRes

/**
 * Whether the game opens the mic by itself once a question is asked (Settings › Microphone › Open the microphone by
 * itself). By default it doesn't with a screen reader on, as on iOS: the recogniser would hear the screen being read,
 * so the player opens it (the talking circle, the mic button, the headphones' button). iOS: MicPolicy in A11y.swift.
 */
fun listensByItself(policy: MicAuto, screenReaderOn: Boolean): Boolean = when (policy) {
    MicAuto.NOT_WITH_SCREEN_READER -> !screenReaderOn
    MicAuto.ALWAYS -> true
    MicAuto.NEVER -> false
}

/**
 * What the game's one button does now, with the name and state a screen reader says for it (docs/DESIGN.md's table):
 * the talking circle, the notification's button, and Magic Tap on iOS (CircleAction in A11y.swift); the mic button
 * takes its name from the same table ([mic]). [label] and [state] are the words' strings (res/values/strings.xml).
 * [enabled] is false while there's nothing to do yet.
 */
enum class CircleAction(@StringRes val label: Int, @StringRes val state: Int, val enabled: Boolean = true) {
    CARRY_ON(R.string.carry_on, R.string.paused),
    SKIP(R.string.circle_skip, R.string.state_speaking),
    STOP_LISTENING(R.string.circle_stop_listening, R.string.state_listening),
    TALK(R.string.circle_talk, R.string.state_your_turn),
    /** The mic isn't allowed: a tap asks for it, or leads to the phone's settings, as the mic button does. */
    MIC_REFUSED(R.string.circle_talk_mic_off, R.string.state_your_turn),
    /** No speech recogniser that works (none on the phone, or it needs a network there isn't): a tap tries again. */
    NO_RECOGNITION(R.string.circle_talk_no_recognition, R.string.state_your_turn),
    /** A turn being worked out, with no question yet. */
    WAIT(R.string.circle_talk, R.string.state_wait, enabled = false),
    ;

    companion object {
        /**
         * The first that applies: carry on when paused, skip while the game speaks, stop while it listens; at an
         * end, nothing (null: the circle is just a picture, and the notification has no button); then talk once a
         * question is asked, or the reason it can't.
         */
        fun of(
            paused: Boolean,
            speaking: Boolean,
            listening: Boolean,
            end: Boolean,
            ask: Boolean,
            micAllowed: Boolean,
            micWorks: Boolean,
        ): CircleAction? = when {
            paused -> CARRY_ON
            speaking -> SKIP
            listening -> STOP_LISTENING
            end -> null
            !ask -> WAIT
            !micAllowed -> MIC_REFUSED
            !micWorks -> NO_RECOGNITION
            else -> TALK
        }

        /**
         * The mic button's: what the circle does once a question is asked, whatever the voice is doing (while it
         * speaks, the mic cuts it short and listens, so it's Talk, never Skip). It's under the pause when paused, and
         * gone at an end.
         */
        fun mic(listening: Boolean, micAllowed: Boolean, micWorks: Boolean): CircleAction = checkNotNull(
            of(
                paused = false, speaking = false, listening = listening, end = false, ask = true,
                micAllowed = micAllowed, micWorks = micWorks,
            ),
        )
    }
}
