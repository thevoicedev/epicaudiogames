package com.epicaudiogames.app.analytics

import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** Our server's answer: its HTTP status (null: none came, as with no network or a timeout), and its Retry-After. */
data class Response(val status: Int?, val retryAfterSeconds: Long? = null)

/** Sends a JSON body to a URL: [HttpPost] on the phone, a stand-in in the tests. */
fun interface Post {
    fun post(url: String, body: ByteArray): Response
}

/**
 * A POST with Android's own HttpURLConnection, nothing more (no SDK, no cookies, no cache): the body as JSON, the
 * app's name and version as its User-Agent, and the server's answer. Redirects aren't followed (the API sends none).
 */
class HttpPost(private val userAgent: String, private val timeoutMs: Int = TIMEOUT_MS) : Post {
    override fun post(url: String, body: ByteArray): Response = try {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.useCaches = false
            connection.instanceFollowRedirects = false
            connection.connectTimeout = timeoutMs
            connection.readTimeout = timeoutMs
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8")
            connection.setRequestProperty("User-Agent", userAgent)
            connection.setFixedLengthStreamingMode(body.size)
            connection.outputStream.use { it.write(body) }
            val status = connection.responseCode
            val retryAfter = connection.getHeaderField("Retry-After")?.trim()?.toLongOrNull()
            // The answer's body ({"ok":true} or why not) is read to its end and let go: nothing in it is needed.
            runCatching {
                (if (status >= 400) connection.errorStream else connection.inputStream)?.use { it.readBytes() }
            }
            Response(status, retryAfter)
        } finally {
            connection.disconnect()
        }
    } catch (e: IOException) {
        Response(null)
    }

    private companion object {
        /** How long to wait to connect, and then for the answer. */
        const val TIMEOUT_MS = 15_000
    }
}

/** What a request's answer means for what it carried. */
enum class Delivery {
    /** Stored (202): off the queue. */
    SENT,
    /** Turned away for good (400, 413, 415, any 4xx but 429): sending it again would get the same, so it goes. */
    REFUSED,
    /** Not now (no answer, 429, 503 or another 5xx): it stays, and is tried again later. */
    LATER,
}

/** What an answer's status means (web/server.js: 202, 400, 413, 415, 429, 503). */
fun delivery(status: Int?): Delivery = when {
    status == null -> Delivery.LATER
    status in 200..299 -> Delivery.SENT
    status == 429 -> Delivery.LATER
    status in 400..499 -> Delivery.REFUSED
    else -> Delivery.LATER
}

/**
 * Sends the usage data waiting in [queue] to our server ([server]/api/events, docs/DESIGN.md › Usage data): a batch
 * at a time (at most 100 events and 64 KB), oldest first, until none is left or one can't go now. What the server
 * stored, or turned away for good (a 4xx but 429: it would turn it away again), comes off the queue; otherwise it all
 * stays, and sending waits: 30 s after a first failure, then twice as long each time up to 30 minutes, and at least as
 * long as the server's Retry-After asks (a busy server's 429, a 503 while its database is down). A batch sent again
 * after its answer was lost is stored once: the server knows each event by its ID, session and number in it.
 *
 * Also asks the server to forget an install ([forget]). Runs on the usage data's own thread, never the screen's: a
 * request blocks it. [clock] is in milliseconds that keep counting while the phone sleeps (elapsedRealtime). iOS:
 * Analytics/Sender.swift.
 */
class Sender(
    private val queue: EventQueue,
    private val post: Post,
    server: String,
    private val clock: () -> Long,
    private val log: (String) -> Unit = {},
) {
    val eventsUrl = "$server/api/events"
    val forgetUrl = "$server/api/forget"

    /** Failures in a row (sending waits longer after each). */
    private var failures = 0

    /** When sending may be tried again after a failure ([clock]'s time); null: whenever. */
    var retryAt: Long? = null
        private set

    /** The last request got no answer at all: the network coming back is worth trying again for at once. */
    var offline = false
        private set

    /** Whether sending may be tried now (not waiting after a failure). */
    fun ready(): Boolean = retryAt?.let { clock() >= it } ?: true

    /**
     * Sends what's waiting, a batch at a time, while [stillOn] (usage data turned off meanwhile stops it). Stops at
     * the first batch that can't go now, which stays for later ([retryAt]). How many events the server took.
     */
    fun send(stillOn: () -> Boolean = { true }): Int {
        var sent = 0
        while (stillOn()) {
            val batch = queue.batch() ?: break
            val answer = post.post(eventsUrl, batch.body)
            offline = answer.status == null
            when (delivery(answer.status)) {
                Delivery.SENT -> {
                    queue.removeThrough(batch.last)
                    sent += batch.count
                    reset()
                }
                Delivery.REFUSED -> {
                    // Never happens with events the app checked against the whitelist; if it does, it can't be fixed
                    // by sending them again.
                    queue.removeThrough(batch.last)
                    log("usage data: ${batch.count} events turned away (HTTP ${answer.status})")
                    reset()
                }
                Delivery.LATER -> {
                    failed(answer.retryAfterSeconds)
                    log("usage data: ${batch.count} events kept for later (${answer.status ?: "no answer"})")
                    break
                }
            }
        }
        if (sent > 0) log("usage data: $sent events sent")
        return sent
    }

    /**
     * Asks the server to delete everything it has under [installId] ("Delete my usage data"): true once it says it
     * has (202, also when it had nothing), false if it couldn't be asked or said no.
     */
    fun forget(installId: String): Boolean {
        val body = "{\"install_id\":\"$installId\"}".toByteArray(Charsets.UTF_8)
        val answer = post.post(forgetUrl, body)
        offline = answer.status == null
        return delivery(answer.status) == Delivery.SENT
    }

    /** Sending can be tried whenever again (it went through, or there's nothing left to send). */
    fun reset() {
        failures = 0
        retryAt = null
    }

    /** A batch that couldn't go: sending waits ([backoffMs]). */
    private fun failed(retryAfterSeconds: Long?) {
        failures++
        retryAt = clock() + backoffMs(failures, retryAfterSeconds)
    }

    companion object {
        /** The wait after a first failure. */
        const val FIRST_WAIT_MS = 30_000L
        /** The longest the wait grows to by itself. */
        const val LONGEST_WAIT_MS = 30L * 60 * 1000
        /** The longest a server's Retry-After is followed for. */
        const val LONGEST_RETRY_AFTER_MS = 24L * 60 * 60 * 1000

        /**
         * How long to wait after [failures] failures in a row: 30 s, then twice as long each time up to 30 minutes, or
         * the server's Retry-After if that's longer (up to a day).
         */
        fun backoffMs(failures: Int, retryAfterSeconds: Long?): Long {
            val doublings = (failures - 1).coerceIn(0, 16)
            val wait = (FIRST_WAIT_MS shl doublings).coerceAtMost(LONGEST_WAIT_MS)
            val asked = retryAfterSeconds?.takeIf { it > 0 }
                ?.let { (it * 1000).coerceAtMost(LONGEST_RETRY_AFTER_MS) } ?: 0
            return maxOf(wait, asked)
        }
    }
}
