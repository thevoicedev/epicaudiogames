package com.epicaudiogames.app.analytics

import com.epicaudiogames.app.ui.Tab
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * The app's usage data as a whole (analytics/Analytics.kt's UsageData), on a test's clock with a stand-in server:
 * app_open and app_background, sessions and their numbered events under one random ID, sending every minute on screen
 * and as the app goes, waiting after a failure (the same events, the same numbers, again), the network coming back,
 * nothing sent before the welcome, turning off (nothing left on the phone, a new ID after), Delete my usage data, a
 * mistake in the app's own events, and a build with no server. Every event sent is checked against the server's own
 * whitelist (web/analytics/events.json).
 */
class UsageDataTest {
    @get:Rule
    val folder = TemporaryFolder()

    /** The test's clocks: milliseconds since the phone started, and since 1970. */
    private var clock = 50_000_000L
    private var wall = 1_791_538_860_000L
    private val worker = TestWorker()
    /** Every request: its URL, and its body. */
    private val requests = mutableListOf<Pair<String, ByteArray>>()
    private var answer: (String) -> Response = { Response(202) }
    private val post = Post { url, body ->
        requests += url to body
        answer(url)
    }
    private var formFactor = "phone"
    private val dir by lazy { File(folder.root, "analytics") }
    private val idFile by lazy { File(dir, UsageData.INSTALL_ID) }
    private val queueFile by lazy { File(dir, UsageData.QUEUE) }

    private fun usage(
        sharing: Boolean = true,
        waitForWelcome: Boolean = false,
        strict: Boolean = true,
        server: String? = "https://epicaudiogames.com",
    ) = UsageData(
        dir, server, post, worker,
        about = { About("1.0", "3", "15", "en-GB", formFactor) },
        clock = { clock },
        wallClock = { wall },
        strict = strict,
        log = {},
        sharing = sharing,
        waitForWelcome = waitForWelcome,
    )

    /** The events sent so far, each checked against the server's whitelist, in the order they went. */
    private fun sent(): List<JsonObject> =
        requests.filter { it.first.endsWith("/api/events") }.flatMap { Whitelist.batch(it.second) }

    private fun JsonObject.text(key: String) = getValue(key).jsonPrimitive.content
    private fun JsonObject.prop(key: String) = (getValue("props") as JsonObject).getValue(key).jsonPrimitive.content

    @Test
    fun aSessionsEventsAreNumberedUnderOneRandomID() {
        val u = usage()
        u.foreground()
        u.track(Events.tabView(Tab.SHOP))
        worker.advance(30_000)
        u.background()
        val first = sent()
        assertEquals(listOf("app_open", "tab_view", "app_background"), first.map { it.text("name") })
        assertEquals(listOf("0", "1", "2"), first.map { it.text("seq") })
        assertEquals(1, first.map { it.text("session_id") }.toSet().size)
        val id = first.map { it.text("install_id") }.toSet().single()
        assertEquals(id, idFile.readText())
        assertEquals("true", first[0].prop("cold"))
        assertEquals("true", first[0].prop("first"))
        assertEquals("30", first[2].prop("seconds"))
        assertEquals("phone", first[0].text("form_factor"))
        assertFalse("nothing left waiting", queueFile.exists())

        // Back ten minutes later: the same session, numbered on.
        worker.advance(10 * 60_000)
        u.foreground()
        worker.advance(5_000)
        u.background()
        val again = sent().drop(3)
        assertEquals(listOf("app_open", "app_background"), again.map { it.text("name") })
        assertEquals(listOf("3", "4"), again.map { it.text("seq") })
        assertEquals("false", again[0].prop("cold"))
        assertEquals("false", again[0].prop("first"))
        assertEquals(first[0].text("session_id"), again[0].text("session_id"))

        // Back after half an hour away: a new session, the same ID.
        worker.advance(30 * 60_000)
        formFactor = "tablet"           // (a foldable, opened)
        u.foreground()
        u.background()
        val later = sent().drop(5)
        assertEquals(listOf("0", "1"), later.map { it.text("seq") })
        assertNotEquals(first[0].text("session_id"), later[0].text("session_id"))
        assertEquals(id, later[0].text("install_id"))
        assertEquals("tablet", later[0].text("form_factor"))

        // The app started again (a new process): cold, a new session, not the first time.
        val next = usage()
        next.foreground()
        next.background()
        val restarted = sent().drop(7)
        assertEquals("true", restarted[0].prop("cold"))
        assertEquals("false", restarted[0].prop("first"))
        assertEquals("0", restarted[0].text("seq"))
        assertEquals(id, restarted[0].text("install_id"))
    }

    @Test
    fun onScreenWhatsWaitingGoesEveryMinute() {
        val u = usage()
        u.foreground()
        u.track(Events.introFinished(skipped = true))
        worker.advance(59_999)
        assertTrue(requests.isEmpty())
        worker.advance(1)
        assertEquals(listOf("app_open", "intro_finished"), sent().map { it.text("name") })
        u.track(Events.tabView(Tab.HELP))
        worker.advance(60_000)
        assertEquals(2, requests.size)
        // Nothing waiting: nothing sent.
        worker.advance(60_000)
        assertEquals(2, requests.size)
        // Off screen, the minutes stop.
        u.background()
        assertEquals(3, requests.size)
        u.track(Events.gameOpen("noodle-rush", resumed = false))
        worker.advance(10 * 60_000)
        assertEquals(3, requests.size)
        // A game left: what's waiting goes then.
        u.flush()
        assertEquals("game_open", sent().last().text("name"))
    }

    @Test
    fun nothingIsSentUntilThePlayerHasHadTheWelcome() {
        val u = usage(waitForWelcome = true)
        u.foreground()
        u.track(Events.introFinished(skipped = false))
        u.track(Events.onboardingFinished(completed = true))
        worker.advance(5 * 60_000)
        u.background()
        assertTrue(requests.isEmpty())
        assertEquals(4, queueFile.readLines().size)
        u.waitForWelcome = false
        assertEquals(
            listOf("app_open", "intro_finished", "onboarding_finished", "app_background"),
            sent().map { it.text("name") },
        )
    }

    @Test
    fun turnedOffNothingIsLeftOnThePhoneAndNothingIsSent() {
        answer = { Response(503, retryAfterSeconds = 60) }
        val u = usage()
        u.foreground()
        u.track(Events.tabView(Tab.SETTINGS))
        u.background()                      // the server's down: kept for later
        val oldId = idFile.readText()
        val oldSession = Whitelist.batch(requests.last().second).first().text("session_id")
        assertTrue(queueFile.exists())
        u.sharing = false
        assertFalse(idFile.exists())
        assertFalse(queueFile.exists())
        // No more events, and the retry that was waiting doesn't happen.
        answer = { Response(202) }
        u.track(Events.tabView(Tab.GAMES))
        u.foreground()
        worker.advance(10 * 60_000)
        u.background()
        assertEquals(1, requests.size)
        assertFalse(dir.listFiles().orEmpty().any { it.isFile && it.length() > 0 })

        // Turned on again: a new ID, a new session, nothing to link them.
        u.sharing = true
        u.foreground()
        u.background()
        val now = sent().drop(3)            // (after the three the server couldn't take)
        assertEquals(listOf("app_open", "app_background"), now.map { it.text("name") })
        assertNotEquals(oldId, now[0].text("install_id"))
        assertNotEquals(oldSession, now[0].text("session_id"))
        assertEquals("0", now[0].text("seq"))
    }

    @Test
    fun startedTurnedOffNothingFromBeforeIsLeft() {
        dir.mkdirs()
        idFile.writeText("4b0c8a8e-4f3d-4c6e-9a51-3b8a7f0f2d10")
        queueFile.writeText("$wall\t{\"name\":\"tab_view\"}\n")
        val u = usage(sharing = false)
        assertFalse(idFile.exists())
        assertFalse(queueFile.exists())
        u.foreground()
        u.track(Events.tabView(Tab.SHOP))
        u.background()
        assertTrue(requests.isEmpty())
        assertFalse(idFile.exists())
    }

    @Test
    fun deleteMyUsageDataAsksTheServerThenForgets() {
        val u = usage()
        u.foreground()
        u.background()
        val id = idFile.readText()
        val session = sent().first().text("session_id")

        // The server can't be reached: nothing changes, so it can be asked again.
        answer = { Response(null) }
        u.track(Events.tabView(Tab.SETTINGS))
        assertEquals(UsageDeletion.FAILED, runBlocking { u.delete() })
        assertEquals(id, idFile.readText())
        assertTrue(queueFile.exists())

        answer = { Response(202) }
        assertEquals(UsageDeletion.DELETED, runBlocking { u.delete() })
        val forget = requests.last()
        assertEquals("https://epicaudiogames.com/api/forget", forget.first)
        assertEquals("""{"install_id":"$id"}""", forget.second.toString(Charsets.UTF_8))
        assertFalse(idFile.exists())
        assertFalse("what was waiting went too", queueFile.exists())

        // Still sharing: the next events are under a new ID, in a new session.
        u.foreground()
        u.background()
        val after = sent().drop(2)
        assertEquals(listOf("app_open", "app_background"), after.map { it.text("name") })
        assertNotEquals(id, after[0].text("install_id"))
        assertNotEquals(session, after[0].text("session_id"))

        // Turned off, the ID is forgotten already: nothing can be found to delete, and nothing is asked.
        u.sharing = false
        val asked = requests.size
        assertEquals(UsageDeletion.NOTHING_SENT, runBlocking { u.delete() })
        assertEquals(asked, requests.size)
    }

    @Test
    fun whatCouldntGoGoesLaterWithTheSameNumbers() {
        answer = { Response(503, retryAfterSeconds = 60) }
        val u = usage()
        u.foreground()
        u.track(Events.helpViewed(HelpSource.TAB))
        u.background()
        assertEquals(1, requests.size)
        val failed = requests.single().second.toString(Charsets.UTF_8)
        answer = { Response(202) }
        worker.advance(59_000)
        assertEquals(1, requests.size)
        worker.advance(1_000)
        assertEquals(2, requests.size)
        assertEquals(failed, requests.last().second.toString(Charsets.UTF_8))
        assertFalse(queueFile.exists())
        // And the next event is numbered on, never again from a number already used.
        u.foreground()
        u.background()
        assertEquals(listOf("3", "4"), sent().drop(6).map { it.text("seq") })
    }

    @Test
    fun theNetworkComingBackSendsAtOnce() {
        answer = { Response(null) }
        val u = usage()
        u.foreground()
        u.background()
        assertEquals(1, requests.size)
        answer = { Response(202) }
        u.networkBack()
        assertEquals(2, requests.size)
        assertFalse(queueFile.exists())
        // With nothing waiting for the network, its coming and going sends nothing.
        u.networkBack()
        assertEquals(2, requests.size)
        // Nor does it hurry a server that asked to wait (it answered: the network wasn't the trouble).
        answer = { Response(503, retryAfterSeconds = 3600) }
        u.foreground()
        u.background()
        assertEquals(3, requests.size)
        u.networkBack()
        assertEquals(3, requests.size)
    }

    @Test
    fun aNumberIsNeverUsedForTwoEventsInASession() {
        // Answers of every kind, as a phone could get in a day.
        val kinds = listOf(Response(202), Response(503), Response(null), Response(400), Response(429), Response(202))
        var n = 0
        answer = { kinds[n++ % kinds.size] }
        val u = usage()
        val seen = mutableMapOf<Pair<String, String>, String>()
        repeat(30) { round ->
            u.foreground()
            repeat(7) { u.track(Events.tabView(Tab.entries[(round + it) % 4])) }
            u.track(Events.gameLeave("noodle-rush", "Page1", round, round * 10L, 1, 2, 3, 0))
            worker.advance(61_000)
            u.background()
            u.networkBack()
            worker.advance(if (round % 3 == 0) 31 * 60_000L else 90_000L)
        }
        for (request in requests.filter { it.first.endsWith("/api/events") }) {
            for (e in Whitelist.batch(request.second)) {
                val key = e.text("session_id") to e.text("seq")
                val event = e.toString()
                // Sent again (its answer lost or refused), it's the same event; never another under its number.
                assertEquals("$key", seen.getOrPut(key) { event }, event)
            }
        }
        assertTrue(seen.size > 100)
    }

    @Test
    fun aMistakeInTheAppsOwnEventsIsCaught() {
        // A debug build: at once.
        val strict = usage()
        assertThrows(IllegalArgumentException::class.java) { strict.track("screen_reader_on") }
        assertThrows(IllegalArgumentException::class.java) {
            strict.track("tab_view", mapOf("tab" to "games", "theme" to "contrast"))
        }
        assertThrows(IllegalArgumentException::class.java) {
            strict.track("game_end", mapOf("game" to "noodle-rush", "kind" to "end", "node" to "yes please"))
        }
        // A release build: left out, and the rest goes as ever (the server would turn away a batch with it in).
        val release = usage(strict = false)
        release.foreground()
        release.track("screen_reader_on", mapOf("on" to true))
        release.track("tab_view", mapOf("tab" to "games", "voice_speed" to 2))
        release.track("app_open", mapOf("cold" to "yes"))
        release.background()
        assertEquals(listOf("app_open", "app_background"), sent().map { it.text("name") })
    }

    @Test
    fun withNoServerNothingIsKeptOrSent() {
        val u = usage(server = null)
        u.foreground()
        u.track(Events.tabView(Tab.SHOP))
        worker.advance(5 * 60_000)
        u.background()
        u.flush()
        u.networkBack()
        assertTrue(requests.isEmpty())
        assertFalse(dir.exists())
        assertEquals(UsageDeletion.NOTHING_SENT, runBlocking { u.delete() })
        // Its mistakes are still caught.
        assertThrows(IllegalArgumentException::class.java) {
            u.track("transcript", mapOf("text" to "Gribbo: who's there?"))
        }
    }

    /** The usage data's thread, in the test's hands: tasks done at once, timers run as [advance] passes their time. */
    private inner class TestWorker : Worker {
        private inner class Timer(var due: Long, val every: Long?, val task: () -> Unit)

        private val timers = mutableListOf<Timer>()

        override fun run(task: () -> Unit) = task()

        override fun later(ms: Long, repeat: Boolean, task: () -> Unit): () -> Unit {
            val timer = Timer(clock + ms, if (repeat) ms else null, task)
            timers += timer
            return { timers -= timer }
        }

        /** [ms] pass on both clocks, each timer due in them running in turn. */
        fun advance(ms: Long) {
            val end = clock + ms
            while (true) {
                val next = timers.filter { it.due <= end }.minByOrNull { it.due } ?: break
                wall += next.due - clock
                clock = next.due
                val every = next.every
                if (every != null) next.due += every else timers -= next
                next.task()
            }
            wall += end - clock
            clock = end
        }
    }
}
