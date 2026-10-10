package com.epicaudiogames.app

import androidx.activity.ComponentActivity
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.epicaudiogames.app.analytics.Event
import com.epicaudiogames.app.analytics.Events
import com.epicaudiogames.app.analytics.MicAsked
import com.epicaudiogames.engine.Button
import com.epicaudiogames.engine.GameMap
import com.epicaudiogames.engine.Play
import com.epicaudiogames.engine.Session
import com.epicaudiogames.engine.Turn
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CopyOnWriteArrayList

/**
 * What a game tells the usage data (GameController's onEvent; docs/DESIGN.md › Usage data): opened (and whether where
 * it was left), each end reached once (not again when it opens at one), the free part's end with the pack that has
 * what's next, the next chapter, a restart, the mic's answer, the game going wrong, and as it closes how it went: its
 * turns and time, and how many answers were typed, tapped and spoken (counts, never the answers). Every event is one
 * the whitelist takes. A small game with no audio, so each turn's lines are over at once.
 */
@RunWith(AndroidJUnit4::class)
class GameEventsTest {
    /** A screen of the app's showing: the game's service may only start in the foreground. */
    @get:Rule
    val screen = ActivityScenarioRule(ComponentActivity::class.java)

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext.applicationContext
    private val saves = Saves(context)
    private val events = CopyOnWriteArrayList<Event>()
    private val games = CopyOnWriteArrayList<GameController>()
    @Volatile private var left = false

    @Before
    fun setUp() = saves.clear(ID)

    @After
    fun tearDown() {
        main { games.forEach { it.close() } }
        saves.clear(ID)
    }

    /** Closes a game, as the app does as it's left. */
    private fun close(game: GameController) {
        main { game.close() }
        games -= game
    }

    @Test
    fun aPlayOfTheGameAsUsageData() {
        val game = open(MAP)
        assertEquals(listOf(Events.gameOpen(ID, resumed = false)), taken())
        main { game.answer("yes") }                       // typed
        assertEquals(listOf(Events.gameEnd(ID, "chapter", "c1end")), taken())
        main { game.nextChapter() }
        assertEquals(listOf(Events.chapterNext(ID, "c2")), taken())
        Thread.sleep(600)                                 // (a tap this soon after a question is a double tap's)
        main { game.tap(Button("Yes", "yes")) }           // tapped
        assertEquals(listOf(Events.gameEnd(ID, "gameover", "over")), taken())
        main { game.playAgain() }
        assertEquals(listOf(Events.gameRestart(ID)), taken())
        main {
            game.answer("stop")                           // a pause, not an answer
            game.micAnswered(false)
        }
        assertEquals(listOf(Events.micPermission(false, MicAsked.GAME)), taken())
        close(game)
        val leave = taken().single()
        assertEquals("game_leave", leave.name)
        assertEquals(ID, leave.props["game"])
        assertEquals("q1", leave.props["node"])
        assertEquals(5, leave.props["turns"])             // q1, c1end, c2, over, q1 again
        assertEquals(1, leave.props["answers_typed"])
        assertEquals(1, leave.props["answers_tapped"])
        assertEquals(0, leave.props["answers_voice"])
        assertEquals(0, leave.props["silences"])
        assertTrue((leave.props["seconds"] as Long) in 0..60)
        // Closed again: it's said once.
        main { game.close() }
        assertEquals(emptyList<Event>(), taken())
    }

    @Test
    fun openedAtAnEndReachedBeforeItIsntReachedAgain() {
        val first = open(MAP)
        main { first.answer("yes") }
        close(first)
        events.clear()
        // Opened again, at the chapter's end with its next chapter here: picked up, but no second game_end.
        val again = open(MAP)
        assertEquals(listOf(Events.gameOpen(ID, resumed = true)), taken())
        main { again.nextChapter() }
        assertEquals(listOf(Events.chapterNext(ID, "c2")), taken())
    }

    @Test
    fun theFreePartsEndSaysWhichPackHasWhatsNext() {
        val game = open(LOCKED)
        taken()
        main { game.answer("yes") }
        assertEquals(
            listOf(Events.gameEnd(ID, "chapter", "free_end"), Events.lockedEnd(ID, "test-cake-more")),
            taken(),
        )
    }

    @Test
    fun aGameThatGoesWrongSaysWhere() {
        val map = GameMap.parse(MAP)
        // A game whose answers break it.
        val broken = object : Play by Session(map) {
            override fun answer(said: String): Turn = throw IllegalStateException("broken")
        }
        val game = open(broken)
        taken()
        main { game.answer("yes") }
        assertEquals(listOf(Events.gameError(ID, "q1")), taken())
        assertTrue(left)
    }

    /** A game on [map] (or [play]), opened, its first turn over. */
    private fun open(map: String) = open(Session(GameMap.parse(map)))

    private fun open(play: Play): GameController {
        lateinit var game: GameController
        main {
            game = GameController(
                context, GameInfo(ID, "Cake", "", "", emptyList()), play, saves, emptyList(),
                onLeave = { left = true },
                listensByItself = { false },
                onEvent = { name, props -> events += Event(name, props) },
            )
            games += game
            game.micAllowed = false
            game.open()
        }
        instrumentation.waitForIdleSync()
        return game
    }

    /** The events since the last call, once what's posted to the main thread is done; each one the whitelist takes. */
    private fun taken(): List<Event> {
        instrumentation.waitForIdleSync()
        val got = events.toList()
        events.clear()
        for (e in got) assertNull("$e", Events.problem(e.name, e.props))
        return got
    }

    private fun main(block: () -> Unit) {
        instrumentation.runOnMainSync(block)
        instrumentation.waitForIdleSync()
    }

    private companion object {
        const val ID = "test-cake"

        /** A question, a chapter end, a second chapter, a game over (GameScreenTest's game). */
        val MAP = """
            {
             "format": 1, "id": "test-cake", "title": "Cake", "start": "q1",
             "who": { "NARRATOR": "Narrator", "PIP": "Pip" },
             "words": { "yes": ["=yes"], "no": ["=no"], "repeat": ["say that again"] },
             "nodes": {
              "q1": {
               "say": [ { "play": "scenes/q1", "dur": 2, "lines": [
                 { "at": 0, "len": 2, "who": "PIP", "text": "Do you want cake?" } ] } ],
               "ask": {
                "reprompt": [ { "play": "prompts/q1", "dur": 1, "lines": [
                  { "at": 0, "len": 1, "who": "NARRATOR", "text": "Cake? Say yes or no." } ] } ],
                "answers": [ { "yes": true, "go": "c1end" }, { "no": true, "go": "over" } ],
                "else": "c1end",
                "buttons": [ { "label": "Yes please, cake", "value": "yes" }, { "label": "No", "value": "no" } ]
               }
              },
              "c1end": {
               "say": [ { "play": "scenes/c1end", "dur": 2, "lines": [
                 { "at": 0, "len": 2, "who": "NARRATOR", "text": "Cake for everyone." } ] } ],
               "end": { "kind": "chapter", "title": "Chapter One", "next": "c2" }
              },
              "c2": {
               "say": [ { "play": "scenes/c2", "dur": 2, "lines": [
                 { "at": 0, "len": 2, "who": "PIP", "text": "More cake?" } ] } ],
               "ask": {
                "reprompt": [ { "play": "prompts/c2", "dur": 1, "lines": [
                  { "at": 0, "len": 1, "who": "PIP", "text": "More? Yes or no." } ] } ],
                "answers": [ { "yes": true, "go": "over" } ],
                "else": "over",
                "buttons": [ { "label": "Yes", "value": "yes" } ]
               }
              },
              "over": {
               "say": [ { "play": "scenes/over", "dur": 2, "lines": [
                 { "at": 0, "len": 2, "who": "NARRATOR", "text": "Too much cake." } ] } ],
               "end": { "kind": "gameover", "title": "Oh no", "retry": "q1" }
              }
             }
            }
        """.trimIndent()

        /** A free part that ends where a pack (not installed) carries on. */
        val LOCKED = """
            {
             "format": 1, "id": "test-cake", "title": "Cake", "start": "q1",
             "nodes": {
              "q1": {
               "say": [ { "play": "scenes/q1", "dur": 1, "lines": [
                 { "at": 0, "len": 1, "who": "NARRATOR", "text": "Ready?" } ] } ],
               "ask": { "answers": [ { "yes": true, "go": "free_end" } ], "else": "free_end" }
              },
              "free_end": {
               "say": [],
               "end": { "kind": "chapter", "title": "Part one", "next": "more1", "locked": "test-cake-more" }
              }
             }
            }
        """.trimIndent()
    }
}
