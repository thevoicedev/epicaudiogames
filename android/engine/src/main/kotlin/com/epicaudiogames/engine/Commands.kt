package com.epicaudiogames.engine

/**
 * Words the app handles itself, before the game's answers: "stop", "cancel" and "pause" pause the game, the way
 * Alexa's Stop and Cancel end a skill (docs/MAP_FORMAT.md, "App commands").
 */
object Commands {
    private val PAUSE = setOf("stop", "cancel", "pause")

    fun isPause(said: String): Boolean = Text.normalise(said) in PAUSE
}
