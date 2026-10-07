package com.epicaudiogames.app

import android.content.Context
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipInputStream

/**
 * The packs on this phone, each unpacked in no_backup/packs/<id>/: its pack.json (the nodes it adds to its game's map)
 * and its audio, under the same paths as the game's own. A pack is installed only from a zip whose size and SHA-256
 * are the catalog's, and replaces any older version of itself. The packs are kept out of backups: they download
 * again, and they would take a backup over its 25 MB, saves and all.
 */
class Packs(context: Context) {
    private val noBackup = context.noBackupFilesDir
    private val root = File(noBackup, "packs")

    init {
        // Packs from before they moved out of the backups (files/packs).
        val old = File(context.filesDir, "packs")
        if (old.isDirectory && !root.exists()) old.renameTo(root)
        // An unpacking that didn't finish (the app stopped, the phone full).
        root.listFiles { f -> f.name.endsWith(".new") }?.forEach { it.deleteRecursively() }
    }

    /**
     * A game's installed packs, in the catalog's order, with their folders. Each is as it is on the phone: an older
     * version stays in use (a save in it plays on) until its update replaces it, and its version is the one on disk.
     */
    fun installed(game: GameInfo): List<Pair<PackInfo, File>> = game.packs.mapNotNull { p ->
        val dir = File(root, p.id)
        version(dir)?.let { p.copy(version = it) to dir }
    }

    /** Installed at the catalog's version (an older one is downloaded again). */
    fun isInstalled(pack: PackInfo) = version(File(root, pack.id)) == pack.version

    /** The version in a pack's folder, if it's there with its pack.json. */
    private fun version(dir: File): Int? {
        val version = File(dir, VERSION).takeIf { it.isFile }?.readText()?.trim()?.toIntOrNull()
        return version?.takeIf { File(dir, "pack.json").isFile }
    }

    /** Whether there's room for a pack: its zip and the pack unpacked from it (2.2 times its size, as on iOS). */
    fun hasRoom(pack: PackInfo): Boolean = noBackup.usableSpace >= pack.size * 22 / 10

    /** Unpacks a downloaded zip, after checking it is the catalog's. A failed unpacking leaves nothing behind. */
    fun install(pack: PackInfo, zip: File) {
        require(zip.length() == pack.size) { "the download is ${zip.length()} bytes, not ${pack.size}" }
        require(sha256(zip) == pack.sha256) { "the download's checksum isn't the pack's" }
        val tmp = File(root, "${pack.id}.new").apply {
            deleteRecursively()
            mkdirs()
        }
        try {
            val top = tmp.canonicalPath + File.separator
            ZipInputStream(zip.inputStream().buffered()).use { zin ->
                while (true) {
                    val e = zin.nextEntry ?: break
                    val out = File(tmp, e.name).canonicalFile
                    require(out.path.startsWith(top)) { "a path outside the pack: ${e.name}" }
                    if (e.isDirectory) {
                        out.mkdirs()
                        continue
                    }
                    out.parentFile?.mkdirs()
                    out.outputStream().use { zin.copyTo(it) }
                }
            }
            require(File(tmp, "pack.json").isFile) { "no pack.json in ${pack.id}" }
            File(tmp, VERSION).writeText(pack.version.toString())
            val dir = File(root, pack.id)
            dir.deleteRecursively()
            check(tmp.renameTo(dir)) { "couldn't put ${pack.id} in place" }
        } catch (e: Throwable) {
            tmp.deleteRecursively()
            throw e
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buf = ByteArray(1 shl 16)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                digest.update(buf, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private companion object {
        const val VERSION = ".version"
    }
}
