package com.epicaudiogames.app.analytics

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * The usage data waiting to be sent (analytics/EventQueue.kt): kept on the phone between runs, at most 1,000 events
 * and none older than a week (the oldest go first), and sent in batches the server takes: at most 100 events and
 * 64 KB.
 */
class EventQueueTest {
    @get:Rule
    val folder = TemporaryFolder()

    private var now = 1_791_538_860_000L
    private val file by lazy { File(folder.root, "analytics/queue.jsonl") }

    private fun queue() = EventQueue(file, { now })

    /** A small event, numbered. */
    private fun event(n: Int, padding: Int = 0) = """{"name":"tab_view","n":$n,"pad":"${"x".repeat(padding)}"}"""

    /** The numbers of the events in a batch. */
    private fun numbers(batch: Batch?): List<Int> =
        (Json.parseToJsonElement(batch!!.body.toString(Charsets.UTF_8)) as JsonArray)
            .map { it.jsonObject.getValue("n").jsonPrimitive.int }

    @Test
    fun itKeepsAtMostAThousandEventsTheOldestGoingFirst() {
        val q = queue()
        repeat(1_005) { q.add(event(it)) }
        assertEquals(1_000, q.size)
        assertEquals((5 until 105).toList(), numbers(q.batch()))
        // So does the file: read again, it's the same thousand.
        val again = queue()
        assertEquals(1_000, again.size)
        assertEquals(5, numbers(again.batch()).first())
    }

    @Test
    fun itKeepsNothingOlderThanAWeek() {
        val q = queue()
        q.add(event(0))
        now += 24 * 60 * 60 * 1000L
        q.add(event(1))
        now += EventQueue.MAX_AGE_MS - 24 * 60 * 60 * 1000L        // the first is a week old, to the millisecond
        assertEquals(listOf(0, 1), numbers(q.batch()))
        now += 1
        assertEquals(listOf(1), numbers(q.batch()))
        assertEquals(1, queue().size)
        now += 24 * 60 * 60 * 1000L
        assertNull(q.batch())
        assertTrue(q.isEmpty())
        assertFalse(file.exists())
    }

    @Test
    fun itKeepsItsEventsBetweenRunsAndSkipsALineCutShort() {
        val q = queue()
        repeat(3) { q.add(event(it)) }
        // The app stopped as it wrote a fourth.
        file.appendText("${now}\t{\"name\":\"tab_vi")
        val again = queue()
        assertEquals(3, again.size)
        assertEquals(listOf(0, 1, 2), numbers(again.batch()))
        // Its file is tidied as it's read.
        assertEquals(3, file.readLines().size)
        again.add(event(3))
        assertEquals(listOf(0, 1, 2, 3), numbers(queue().batch()))
    }

    @Test
    fun aBatchIsAtMostAHundredEvents() {
        val q = queue()
        repeat(250) { q.add(event(it)) }
        val sizes = mutableListOf<Int>()
        while (true) {
            val batch = q.batch() ?: break
            sizes += batch.count
            assertEquals(batch.count, numbers(batch).size)
            q.removeThrough(batch.last)
        }
        assertEquals(listOf(100, 100, 50), sizes)
        assertTrue(q.isEmpty())
    }

    @Test
    fun aBatchIsAtMost64KB() {
        val q = queue()
        // Events of 1,000 bytes: 65 fit in 64 KB with the brackets and commas (65 × 1,001 + 1 = 65,066), 66 don't.
        val bytes = event(0).length
        repeat(150) { q.add(event(it, padding = 1_000 - bytes - (if (it >= 10) 1 else 0) - (if (it >= 100) 1 else 0))) }
        assertEquals(1_000, event(5, 1_000 - bytes).length)
        val batch = q.batch()!!
        assertEquals(65, batch.count)
        assertTrue(batch.body.size <= EventQueue.BATCH_BYTES)
        assertEquals(65 * 1_000 + 64 + 2, batch.body.size)
        assertEquals((0 until 65).toList(), numbers(batch))
    }

    @Test
    fun anEventTooBigToSendEvenAloneGoes() {
        val q = queue()
        q.add(event(0, padding = 70_000))
        q.add(event(1))
        assertEquals(listOf(1), numbers(q.batch()))
        assertEquals(1, q.size)
    }

    @Test
    fun whatJoinedWhileABatchWasOnItsWayStays() {
        val q = queue()
        repeat(10) { q.add(event(it)) }
        val batch = q.batch()!!
        repeat(5) { q.add(event(10 + it)) }
        q.removeThrough(batch.last)
        assertEquals((10 until 15).toList(), numbers(q.batch()))
        // And past the thousand meanwhile, the batch's own events having gone: nothing else goes with them.
        repeat(1_000) { q.add(event(100 + it)) }
        val next = q.batch()!!
        q.removeThrough(batch.last)
        assertEquals(1_000, q.size)
        q.removeThrough(next.last)
        assertEquals(900, q.size)
    }

    @Test
    fun clearedNothingIsLeftOnThePhone() {
        val q = queue()
        repeat(3) { q.add(event(it)) }
        assertTrue(file.exists())
        q.clear()
        assertTrue(q.isEmpty())
        assertFalse(file.exists())
        assertTrue(queue().isEmpty())
    }
}
