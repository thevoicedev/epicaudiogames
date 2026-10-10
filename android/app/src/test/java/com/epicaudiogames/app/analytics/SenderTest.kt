package com.epicaudiogames.app.analytics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.concurrent.thread

/**
 * Sending the usage data (analytics/Sender.kt): what's queued goes a batch at a time until it's all gone; what the
 * server took or turned away for good comes off the queue, and what it couldn't take now stays, sending waiting longer
 * after each failure (and as long as the server's Retry-After asks); the server is asked to forget an install. And the
 * phone's HttpURLConnection, against a real server on this computer: the request is the one web/server.js takes.
 */
class SenderTest {
    @get:Rule
    val folder = TemporaryFolder()

    private var now = 0L
    private val queue by lazy { EventQueue(File(folder.root, "queue.jsonl")) }
    /** The requests sent: their URL and body. */
    private val sent = mutableListOf<Pair<String, String>>()
    /** The answers to give, in turn; the last is given again once they're used up. */
    private var answers = mutableListOf(Response(202))

    private val post = Post { url, body ->
        sent += url to body.toString(Charsets.UTF_8)
        if (answers.size > 1) answers.removeAt(0) else answers.first()
    }

    private fun sender() = Sender(queue, post, "https://epicaudiogames.com", { now })

    private fun queueEvents(n: Int) = repeat(n) { queue.add("""{"name":"tab_view","n":$it}""") }

    @Test
    fun whatAnAnswerMeans() {
        assertEquals(Delivery.SENT, delivery(202))
        assertEquals(Delivery.SENT, delivery(200))
        for (status in listOf(400, 404, 405, 413, 415)) assertEquals("$status", Delivery.REFUSED, delivery(status))
        for (status in listOf(null, 429, 500, 502, 503, 301)) assertEquals("$status", Delivery.LATER, delivery(status))
    }

    @Test
    fun theWaitDoublesUpToHalfAnHourAndHeedsRetryAfter() {
        val waits = (1..10).map { Sender.backoffMs(it, null) / 1000 }
        assertEquals(listOf(30L, 60, 120, 240, 480, 960, 1800, 1800, 1800, 1800), waits)
        assertEquals(1800L, Sender.backoffMs(1_000, null) / 1000)
        // The server asks for longer (a 503 without its database: an hour): it gets it, up to a day.
        assertEquals(3_600_000L, Sender.backoffMs(1, 3600))
        assertEquals(60_000L, Sender.backoffMs(2, 1))
        assertEquals(24 * 3_600_000L, Sender.backoffMs(1, 1_000_000_000))
    }

    @Test
    fun itSendsABatchAtATimeUntilAllHaveGone() {
        queueEvents(250)
        val s = sender()
        assertEquals(250, s.send())
        assertEquals(3, sent.size)
        assertTrue(sent.all { it.first == "https://epicaudiogames.com/api/events" })
        assertEquals(listOf(100, 100, 50), sent.map { it.second.split("\"n\"").size - 1 })
        assertTrue(queue.isEmpty())
        assertNull(s.retryAt)
        assertTrue(s.ready())
        // Nothing left: nothing sent.
        assertEquals(0, s.send())
        assertEquals(3, sent.size)
    }

    @Test
    fun whatTheServerCantTakeNowStaysAndSendingWaits() {
        queueEvents(150)
        now = 1_000_000
        answers = mutableListOf(Response(202), Response(503, retryAfterSeconds = 60), Response(202))
        val s = sender()
        assertEquals(100, s.send())
        assertEquals(50, queue.size)
        assertEquals(1_060_000L, s.retryAt)
        assertFalse(s.ready())
        assertFalse(s.offline)
        now = 1_059_999
        assertFalse(s.ready())
        now = 1_060_000
        assertTrue(s.ready())
        assertEquals(50, s.send())
        assertTrue(queue.isEmpty())
        assertNull(s.retryAt)
        // The same events went again: the server keeps each once (by its install, session and number).
        assertEquals(sent[1].second, sent[2].second)
    }

    @Test
    fun withNoNetworkItWaitsLongerEachTime() {
        queueEvents(5)
        answers = mutableListOf(Response(null))
        val s = sender()
        assertEquals(0, s.send())
        assertTrue(s.offline)
        assertEquals(30_000L, s.retryAt)
        now = 30_000
        s.send()
        assertEquals(30_000L + 60_000, s.retryAt)
        // A busy server's 429 counts as a failure too.
        answers = mutableListOf(Response(429, retryAfterSeconds = 5))
        now = 90_000
        s.send()
        assertFalse(s.offline)
        assertEquals(90_000L + 120_000, s.retryAt)
        assertEquals(5, queue.size)
        answers = mutableListOf(Response(202))
        now = 210_000
        assertEquals(5, s.send())
        assertNull(s.retryAt)
    }

    @Test
    fun whatsTurnedAwayGoesAndTheRestIsSent() {
        queueEvents(150)
        answers = mutableListOf(Response(400), Response(202))
        assertEquals(50, sender().send())
        assertEquals(2, sent.size)
        assertTrue(queue.isEmpty())
    }

    @Test
    fun turnedOffMeanwhileItStops() {
        queueEvents(250)
        var on = true
        val s = sender()
        val got = s.send(stillOn = { on.also { on = false } })
        assertEquals(100, got)
        assertEquals(1, sent.size)
        assertEquals(150, queue.size)
    }

    @Test
    fun theServerIsAskedToForgetAnInstall() {
        val id = "4b0c8a8e-4f3d-4c6e-9a51-3b8a7f0f2d10"
        val s = sender()
        assertTrue(s.forget(id))
        assertEquals("https://epicaudiogames.com/api/forget" to """{"install_id":"$id"}""", sent.single())
        for (answer in listOf(Response(null), Response(503), Response(429), Response(400))) {
            answers = mutableListOf(answer)
            assertFalse("$answer", s.forget(id))
        }
    }

    @Test
    fun theRequestIsTheOneTheServerTakes() {
        val server = TinyServer()
        val url = "http://127.0.0.1:${server.port}/api/events"
        try {
            val http = HttpPost("EpicAudioGames/1.0 (android)", timeoutMs = 5_000)
            val body = """[{"name":"tab_view","props":{"tab":"shop"}}]"""
            assertEquals(Response(202), http.post(url, body.toByteArray()))
            val request = server.requests.single()
            assertEquals("POST /api/events HTTP/1.1", request.line)
            assertEquals("application/json; charset=utf-8", request.headers["content-type"])
            assertNull("not compressed", request.headers["content-encoding"])
            assertEquals("EpicAudioGames/1.0 (android)", request.headers["user-agent"])
            assertEquals(body, request.body)

            server.status = 429
            assertEquals(Response(429, retryAfterSeconds = 7), http.post(url, body.toByteArray()))
        } finally {
            server.close()
        }
        // Nobody there any more: no answer at all.
        val gone = HttpPost("EpicAudioGames/1.0 (android)", timeoutMs = 2_000)
        assertEquals(Response(null), gone.post(url, "[]".toByteArray()))
    }

    /** A request as [TinyServer] got it: its first line, its headers (by lower-case name), and its body. */
    private class Request(val line: String, val headers: Map<String, String>, val body: String)

    /**
     * Just enough of an HTTP server on this computer to answer the app's POSTs as web/server.js does: [status], with
     * Retry-After for a 429, one request a connection. (The JDK's own server isn't on the tests' classpath.)
     */
    private class TinyServer : AutoCloseable {
        private val socket = ServerSocket(0, 10, InetAddress.getByName("127.0.0.1"))
        val port = socket.localPort
        val requests = CopyOnWriteArrayList<Request>()
        @Volatile var status = 202

        init {
            thread(isDaemon = true) {
                while (!socket.isClosed) {
                    val client = runCatching { socket.accept() }.getOrNull() ?: break
                    client.use { answer(it) }
                }
            }
        }

        private fun answer(client: Socket) {
            val input = DataInputStream(client.getInputStream())
            val line = readLine(input)
            val headers = mutableMapOf<String, String>()
            while (true) {
                val header = readLine(input)
                if (header.isEmpty()) break
                headers[header.substringBefore(':').trim().lowercase()] = header.substringAfter(':').trim()
            }
            val body = ByteArray(headers["content-length"]?.toInt() ?: 0).also { input.readFully(it) }
            requests += Request(line, headers, body.toString(Charsets.UTF_8))
            val reply = (if (status == 202) """{"ok":true,"accepted":1}""" else """{"error":"too many requests"}""")
                .toByteArray()
            val head = buildString {
                append("HTTP/1.1 $status ${if (status == 202) "Accepted" else "Too Many Requests"}\r\n")
                append("Content-Type: application/json; charset=utf-8\r\n")
                if (status == 429) append("Retry-After: 7\r\n")
                append("Content-Length: ${reply.size}\r\nConnection: close\r\n\r\n")
            }
            client.getOutputStream().apply {
                write(head.toByteArray())
                write(reply)
                flush()
            }
        }

        /** A line of the request's head, without its CR LF. */
        private fun readLine(input: DataInputStream): String {
            val bytes = ByteArrayOutputStream()
            while (true) {
                val b = input.read()
                if (b < 0 || b == '\n'.code) break
                if (b != '\r'.code) bytes.write(b)
            }
            return bytes.toString("UTF-8")
        }

        override fun close() = socket.close()
    }
}
