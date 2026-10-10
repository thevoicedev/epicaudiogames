package com.epicaudiogames.app.analytics

import java.io.File
import java.io.FileOutputStream

/**
 * The usage data waiting to be sent: each event as the JSON the server takes, one a line, in [file]
 * (no_backup/analytics/queue.jsonl, out of backups as the random ID is), so nothing is lost when the app is closed or
 * the phone is offline. It keeps at most [maxEvents] events, none older than [maxAgeMs]: past either, the oldest go.
 * What's sent goes in batches the server takes ([batch]: at most 100 events and 64 KB), each taken off the queue once
 * the server has answered for it ([removeThrough]).
 *
 * Not thread-safe: only the usage data's own thread uses it, so the screen never waits for the file. iOS:
 * Analytics/EventQueue.swift.
 */
class EventQueue(
    private val file: File,
    private val now: () -> Long = System::currentTimeMillis,
    private val maxEvents: Int = MAX_EVENTS,
    private val maxAgeMs: Long = MAX_AGE_MS,
) {
    /** An event waiting: [n] counts up as events join (afresh as the file is read); [at] is when it joined. */
    private class Entry(val n: Long, val at: Long, val json: String)

    private val entries = ArrayDeque<Entry>()
    private var next = 0L
    private var loaded = false

    /** How many events are waiting. */
    val size: Int get() = load().size

    fun isEmpty() = size == 0

    /** An event joins the end of the queue (and the file), the oldest going if that's too many. */
    fun add(json: String) {
        load()
        val entry = Entry(next++, now(), json)
        entries.addLast(entry)
        if (trim()) save() else append(entry)
    }

    /**
     * The oldest events, as many as one request can carry: at most [maxEvents], their JSON array at most [maxBytes]
     * long. Null with none waiting. An event too big to go even alone (none is: they're a few hundred bytes) goes.
     */
    fun batch(maxEvents: Int = BATCH_EVENTS, maxBytes: Int = BATCH_BYTES): Batch? {
        load()
        var changed = trim()
        while (entries.isNotEmpty() && bytes(entries.first()) + 2 > maxBytes) {
            entries.removeFirst()
            changed = true
        }
        if (changed) save()
        if (entries.isEmpty()) return null
        val taken = mutableListOf<Entry>()
        var size = 2                                    // [ and ]
        for (e in entries) {
            if (taken.size == maxEvents) break
            val more = bytes(e) + if (taken.isEmpty()) 0 else 1     // and a comma
            if (size + more > maxBytes) break
            taken += e
            size += more
        }
        val body = taken.joinToString(",", "[", "]") { it.json }.toByteArray(Charsets.UTF_8)
        return Batch(body, taken.size, taken.last().n)
    }

    /** The events up to the end of a batch (by [Batch.last]) are done with: sent, or turned away. */
    fun removeThrough(last: Long) {
        load()
        var removed = false
        while (entries.isNotEmpty() && entries.first().n <= last) {
            entries.removeFirst()
            removed = true
        }
        if (removed) save()
    }

    /** Nothing waits any more, in memory or on the phone. */
    fun clear() {
        entries.clear()
        loaded = true
        file.delete()
        temp().delete()
    }

    /** The events, read from the file the first time they're needed (a line that isn't one, cut short, is skipped). */
    private fun load(): ArrayDeque<Entry> {
        if (loaded) return entries
        loaded = true
        val lines = runCatching { file.readLines(Charsets.UTF_8) }.getOrDefault(emptyList())
        var skipped = false
        for (line in lines) {
            val tab = line.indexOf('\t')
            val at = if (tab > 0) line.substring(0, tab).toLongOrNull() else null
            val json = if (tab > 0) line.substring(tab + 1) else ""
            if (at == null || !json.startsWith("{") || !json.endsWith("}")) {
                skipped = skipped || line.isNotEmpty()
                continue
            }
            entries.addLast(Entry(next++, at, json))
        }
        if (trim() || skipped) save()
        return entries
    }

    /** Drops what's too old, then the oldest past the most kept. True if any went. */
    private fun trim(): Boolean {
        val before = entries.size
        val oldest = now() - maxAgeMs
        entries.removeAll { it.at < oldest }
        while (entries.size > maxEvents) entries.removeFirst()
        return entries.size != before
    }

    /** One more line at the end of the file. */
    private fun append(entry: Entry) {
        runCatching {
            file.parentFile?.mkdirs()
            FileOutputStream(file, true).use { it.write(line(entry).toByteArray(Charsets.UTF_8)) }
        }
    }

    /** The file written again from what's in memory, whole: a new one, then put in the old one's place. */
    private fun save() {
        runCatching {
            if (entries.isEmpty()) {
                file.delete()
                return
            }
            file.parentFile?.mkdirs()
            val tmp = temp()
            tmp.outputStream().buffered().use { out ->
                for (e in entries) out.write(line(e).toByteArray(Charsets.UTF_8))
            }
            if (!tmp.renameTo(file)) {
                // (A file in the way: Android's rename replaces it; other systems' may not.)
                file.delete()
                tmp.renameTo(file)
            }
        }
    }

    private fun temp() = File(file.path + ".tmp")

    private fun line(e: Entry) = "${e.at}\t${e.json}\n"

    private fun bytes(e: Entry) = e.json.toByteArray(Charsets.UTF_8).size

    companion object {
        /** The most events kept: an offline week of steady play is a few hundred. */
        const val MAX_EVENTS = 1_000
        /** The oldest an event is kept: a week. */
        const val MAX_AGE_MS = 7L * 24 * 60 * 60 * 1000
        /** The most events the server takes in one request (web/analytics/whitelist.js's MAX_EVENTS). */
        const val BATCH_EVENTS = 100
        /** The biggest request body the server takes (web/server.js's MAX_BODY). */
        const val BATCH_BYTES = 64 * 1024
    }
}

/** Events to send together: [body] is their JSON array, [count] how many, [last] which was the last of them. */
class Batch(val body: ByteArray, val count: Int, val last: Long)
