package com.epicaudiogames.engine

/**
 * Words the app handles itself, before the game's answers: "stop" and "cancel" pause the game, the way Alexa's Stop
 * and Cancel end a skill (docs/MAP_FORMAT.md, "App commands"). "Pause" is not one: Leaning Tower of Pizza hears it
 * as a mishear of "false".
 */
object Commands {
    private val PAUSE = setOf("stop", "cancel")

    fun isPause(said: String): Boolean = Text.normalise(said) in PAUSE
}
