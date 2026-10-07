package com.epicaudiogames.engine

/**
 * A game being played, as the app drives it: a map's [Session], or a game written in code (Nuclear War). Each call
 * returns the [Turn] to play next.
 */
interface Play {
    /** Speaker keys to the names shown in the transcript. */
    val who: Map<String, String>

    /** The question waiting for an answer, if there is one. */
    val ask: Ask?

    fun start(): Turn

    /** Whether a save can be picked up again: it waits at a question (or, in a map game, at a chapter end). */
    fun canResume(saved: Saved): Boolean

    fun resume(saved: Saved): Turn

    /** The game from a save (or from the start): picked up again where it can be, else started. */
    fun open(saved: Saved?): Turn = if (saved != null && canResume(saved)) resume(saved) else start()

    fun answer(said: String): Turn

    /** The player said nothing: the reprompt, and the same question again. */
    fun silence(): Turn

    /** Starts again, at [at] (or the start). */
    fun restart(at: String? = null): Turn

    /** After a chapter's end: its next chapter. */
    fun nextChapter(): Turn

    /** Whether a chapter end's next chapter is in this game (its pack installed). */
    fun hasChapter(next: String): Boolean

    fun save(): Saved

    /**
     * Whether the question takes this answer, or hears it as one that doesn't count ("I'm not sure", "of course
     * not"): to choose among the recogniser's guesses.
     */
    fun understands(said: String): Boolean
}
