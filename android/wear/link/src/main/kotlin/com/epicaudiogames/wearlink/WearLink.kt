package com.epicaudiogames.wearlink

// What the phone tells the Wear OS app about its game, and what the watch's two buttons ask of it, as Wear OS's Data
// Layer carries them: the phone's side is android/app's WearBridge.kt, the watch's android/wear's PhoneLink.kt. iOS has
// the same for the Apple Watch, through WatchConnectivity: ios/EpicEngine/Sources/EpicAppCore/WatchLink.swift (the
// same keys and names).

/**
 * The game on the phone, as the watch shows it (docs/DESIGN.md › Watches): its title, what it's doing in words, its one
 * button named as on the phone (the talking circle's CircleAction), whether the microphone is open (the watch buzzes
 * as it opens and as it closes), and whether Pause can do anything. The phone makes it (WearBridge.kt) and the watch
 * shows it (PhoneLink.kt, WatchScreen.kt). The Data Layer carries it as a data item's plain values ([toMap]); [from]
 * reads them back.
 */
data class WearState(
    /** The open game's title; empty when no game is open (the watch then says to open one on the phone). */
    val title: String,
    /**
     * What the game is doing, in words: "Speaking", "Your turn", "Listening…", "Paused" or "Wait for the question"; at
     * an end, its heading ("Chapter complete"); empty when no game is open.
     */
    val state: String,
    /**
     * What the big button does, for its icon; null when there's nothing to press (no game, an end), or the phone named
     * something this watch app doesn't know (its button still shows, by [label]).
     */
    val action: WearAction?,
    /**
     * The big button's name, the same words as on the phone: "Skip", "Talk", "Stop listening", "Carry on", "Talk (the
     * microphone is off)"; empty when there's no button.
     */
    val label: String,
    /** The big button can do something now. */
    val enabled: Boolean,
    /** The microphone is open. */
    val listening: Boolean,
    /** Pause can do something: a game is open, and it's neither paused nor at an end. */
    val canPause: Boolean,
) {
    /** A game is open on the phone. */
    val gameOpen: Boolean get() = title.isNotEmpty()

    /**
     * As the Data Layer carries it (strings, booleans and a long), with [at]: when the phone made it, in milliseconds
     * since 1970, so that one read late (the watch reads the latest as it opens, while changes come in) is let go
     * ([WearInbox]).
     */
    fun toMap(at: Long): Map<String, Any> = mapOf(
        WearKey.TITLE to title,
        WearKey.STATE to state,
        WearKey.ACTION to (action?.key ?: ""),
        WearKey.LABEL to label,
        WearKey.ENABLED to enabled,
        WearKey.LISTENING to listening,
        WearKey.CAN_PAUSE to canPause,
        WearKey.AT to at,
    )

    companion object {
        /** No game open. */
        val NONE = WearState(
            title = "", state = "", action = null, label = "", enabled = false, listening = false, canPause = false,
        )

        /**
         * The state in [values] (a data item's, [toMap]'s keys), and when the phone made it; null for anything else (a
         * value missing or of another type).
         */
        fun from(values: Map<String, Any?>): Stamped? {
            val title = values[WearKey.TITLE] as? String ?: return null
            val state = values[WearKey.STATE] as? String ?: return null
            val action = values[WearKey.ACTION] as? String ?: return null
            val label = values[WearKey.LABEL] as? String ?: return null
            val enabled = values[WearKey.ENABLED] as? Boolean ?: return null
            val listening = values[WearKey.LISTENING] as? Boolean ?: return null
            val canPause = values[WearKey.CAN_PAUSE] as? Boolean ?: return null
            val at = values[WearKey.AT] as? Long ?: return null
            return Stamped(WearState(title, state, WearAction.of(action), label, enabled, listening, canPause), at)
        }
    }
}

/** A [state] and when the phone made it ([at], milliseconds since 1970). */
data class Stamped(val state: WearState, val at: Long)

/**
 * What the big button does, as the phone's CircleAction says (MicPolicy.kt: the same names, and iOS's): the watch picks
 * its icon by it, as the phone's talking circle and notification pick theirs. [key] is the name the Data Layer carries.
 */
enum class WearAction(val key: String) {
    /** Paused: the game carries on. */
    CARRY_ON("carryOn"),
    /** Speaking: the voice is cut short. */
    SKIP("skip"),
    /** Listening: the microphone closes. */
    STOP_LISTENING("stopListening"),
    /** The player's turn: the microphone opens. */
    TALK("talk"),
    /** The microphone isn't allowed on the phone, and only the phone can ask for it. */
    MIC_REFUSED("micRefused"),
    /** No speech recognition on the phone just now: a press tries again. */
    NO_RECOGNITION("noRecognition"),
    /** Nothing to do until the question is asked. */
    WAIT("wait"),
    ;

    companion object {
        /** The action named [key]; null for one this app doesn't know (a newer phone app's) or none. */
        fun of(key: String): WearAction? = entries.firstOrNull { it.key == key }
    }
}

/**
 * What the watch's buttons ask of the phone, as a message: the big button ([PRIMARY]: what the headphones' button does
 * on the phone) or Pause. [key] is the message's text.
 */
enum class WearCommand(val key: String) {
    PRIMARY("primary"),
    PAUSE("pause"),
    ;

    /** The message's bytes. */
    val payload: ByteArray get() = key.encodeToByteArray()

    companion object {
        /** The command in a message to [path] with [payload]; null for anything else. */
        fun from(path: String, payload: ByteArray?): WearCommand? {
            if (path != WearLink.COMMAND_PATH || payload == null) return null
            val key = payload.decodeToString()
            return entries.firstOrNull { it.key == key }
        }
    }
}

/**
 * The watch's buzz as the microphone opens or closes (docs/DESIGN.md › Watches): the cue for a player who can't hear
 * the listening sound. A strong one, then a different one (the Wear OS app's Buzz.kt).
 */
enum class WearHaptic {
    LISTENING_STARTED,
    LISTENING_STOPPED,
}

/**
 * The phone's states as the watch takes them in: the newest shows, and one the phone made before it, read late (the
 * watch reads the latest as it opens, while changes come in), is let go; unless it's older by more than
 * [CLOCK_JUMP_MS], which only the phone's clock being put back can do. The microphone opening or closing buzzes
 * ([WearHaptic]), except in the first state the watch has (as its screen opens, nothing has just happened), in a state
 * it catches up with (coming back to its screen: whatever changed meanwhile isn't news now), and as the game closes
 * (leaving a game plays no sound on the phone either). iOS: WatchLink.swift's WatchInbox.
 */
class WearInbox {
    /** What shows: no game, until the phone says. */
    var state: WearState = WearState.NONE
        private set

    /** When the phone made [state]; null until it has said. */
    var at: Long? = null
        private set

    /**
     * Takes [new], made [at]: whether it shows now, and the buzz it calls for. [catchingUp]: read as the watch's screen
     * comes back, so it doesn't buzz.
     */
    fun take(new: WearState, at: Long, catchingUp: Boolean = false): Taken {
        val last = this.at
        if (last != null && at < last && last - at < CLOCK_JUMP_MS) return Taken(shown = false, haptic = null)
        val first = last == null
        val wasListening = state.listening
        state = new
        this.at = at
        val quiet = first || catchingUp || !new.gameOpen || wasListening == new.listening
        if (quiet) return Taken(shown = true, haptic = null)
        val haptic = if (new.listening) WearHaptic.LISTENING_STARTED else WearHaptic.LISTENING_STOPPED
        return Taken(shown = true, haptic = haptic)
    }

    /** What [take] made of a state: whether it shows now, and the buzz it calls for. */
    data class Taken(val shown: Boolean, val haptic: WearHaptic?)

    companion object {
        /** A state this much older than the one showing (ms) is the phone's clock put back, not a late one. */
        const val CLOCK_JUMP_MS = 60_000L
    }
}

/** Where things are on Wear OS's network, the same in both apps. */
object WearLink {
    /** The data item with the game's state (the phone's, one for all its watches). */
    const val STATE_PATH = "/game-state"

    /** The messages with the watch's buttons. The phone's manifest has it too (WearCommands' intent filter). */
    const val COMMAND_PATH = "/game-command"

    /**
     * What the phone app says it can do on Wear OS's network (android/app's res/values/wear.xml): the watch sends its
     * buttons to the phone that has it.
     */
    const val PHONE_CAPABILITY = "epic_audio_games_phone"
}

/** The data item's keys (iOS's WatchKey, the same names). */
object WearKey {
    const val TITLE = "title"
    const val STATE = "state"
    const val ACTION = "action"
    const val LABEL = "label"
    const val ENABLED = "enabled"
    const val LISTENING = "listening"
    const val CAN_PAUSE = "canPause"
    const val AT = "at"
}
