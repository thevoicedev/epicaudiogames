package com.epicaudiogames.app.analytics

import java.io.File
import java.util.UUID

/**
 * The random ID usage data is sent under (docs/DESIGN.md › Usage data): a UUID made the first time an event needs
 * it, and kept in [file] (no_backup/analytics/install_id). Never in a backup, so a phone restored from one, or the
 * app installed again, starts with a new one; no ID of the phone's, the player's or their Google account's, so nothing
 * else knows it. Forgotten when usage data is turned off or deleted; the next event then makes a new one.
 *
 * Not thread-safe: only the usage data's own thread uses it. iOS: Analytics/InstallId.swift (Application Support,
 * excluded from backups, never the keychain).
 */
class InstallId(private val file: File, private val make: () -> UUID = UUID::randomUUID) {
    private var id: String? = null
    private var read = false

    /** The ID, if there is one; a damaged file is none. */
    fun peek(): String? {
        if (!read) {
            id = runCatching { file.readText().trim().lowercase() }.getOrNull()?.takeIf { Events.fits("uuid", it) }
            read = true
        }
        return id
    }

    /**
     * The ID, made now if there isn't one. A file that can't be written (a full phone) leaves it in memory, for as
     * long as the app runs.
     */
    fun get(): String = peek() ?: make().toString().also { made ->
        id = made
        runCatching {
            file.parentFile?.mkdirs()
            val tmp = File(file.path + ".tmp")
            tmp.writeText(made)
            if (!tmp.renameTo(file)) {
                // (A file in the way: Android's rename replaces it; other systems' may not.)
                file.delete()
                tmp.renameTo(file)
            }
        }
    }

    /** Forgets it: the file goes, and the next [get] makes another. */
    fun forget() {
        file.delete()
        File(file.path + ".tmp").delete()
        id = null
        read = true
    }
}
