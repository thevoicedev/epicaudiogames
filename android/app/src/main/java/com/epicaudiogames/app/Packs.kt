package com.epicaudiogames.app

import android.content.Context
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipInputStream

/**
 * The packs on this phone, each unpacked in files/packs/<id>/: its pack.json (the nodes it adds to its game's map)
 * and its audio, under the same paths as the game's own. A pack is installed only from a zip whose size and SHA-256
 * are the catalog's, and replaces any older version of itself.
 */
class Packs(context: Context) {
    private val root = File(context.filesDir, "packs")

    /** A game's installed packs, in the catalog's order, with their folders. */
    fun installed(game: GameInfo): List<Pair<PackInfo, File>> = game.packs.mapNotNull { p ->
        folder(p)?.let { p to it }
    }

    fun isInstalled(pack: PackInfo) = folder(pack) != null

    private fun folder(pack: PackInfo): File? {
        val dir = File(root, pack.id)
        val version = File(dir, VERSION).takeIf { it.isFile }?.readText()?.trim()?.toIntOrNull()
        return dir.takeIf { version == pack.version && File(it, "pack.json").isFile }
    }

    /** Unpacks a downloaded zip, after checking it is the catalog's. */
    fun install(pack: PackInfo, zip: File) {
        require(zip.length() == pack.size) { "the download is ${zip.length()} bytes, not ${pack.size}" }
        require(sha256(zip) == pack.sha256) { "the download's checksum isn't the pack's" }
        val tmp = File(root, "${pack.id}.new").apply {
            deleteRecursively()
            mkdirs()
        }
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
