package com.epicaudiogames.wear

import androidx.compose.ui.graphics.Color
import com.epicaudiogames.wearlink.WearAction
import com.epicaudiogames.wearlink.WearHaptic
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * The Wear OS app's parts that need no watch (the tests run in android/wear): its icon is the phone app's, its colours
 * are the phone's Dark palette with every text pair at 7:1 or more, its buzzes are told apart, each of the big button's
 * actions has an icon, and its words are all used, in sentence case, none in its code.
 */
class WatchAppTest {
    private val phoneRes = File("../app/src/main/res")
    private val res = File("src/main/res")

    @Test
    fun theIconIsThePhoneAppsByteForByte() {
        // The adaptive icon's layers, as tools/make_art.py exports them for the phone (docs/STORE_ART.md): after a new
        // export, copy them here again (android/wear/src/main/res/mipmap-*). The adaptive icon itself is in the phone's
        // mipmap-anydpi-v26, which the watch app (Android 11 and later) needs no version for.
        val icons = res.listFiles().orEmpty().filter { it.name.startsWith("mipmap") }
            .flatMap { dir -> dir.listFiles().orEmpty().map { "${dir.name}/${it.name}" } }
        assertEquals("5 densities of 3 layers, and the adaptive icon twice", 17, icons.size)
        for (icon in icons) {
            val phone = File(phoneRes, icon.replace("mipmap-anydpi/", "mipmap-anydpi-v26/"))
            assertTrue("$phone is missing", phone.isFile)
            assertArrayEquals("$icon isn't the phone app's", phone.readBytes(), File(res, icon).readBytes())
        }
    }

    @Test
    fun theColoursAreThePhonesDarkPalette() {
        // android/app's ui/theme/Tokens.kt, EpicColors.dark.
        val tokens = File("../app/src/main/java/com/epicaudiogames/app/ui/theme/Tokens.kt").readText()
        val dark = tokens.substringAfter("val dark = EpicColors(").substringBefore("val light")
        val phone = Regex("""(\w+) = Color\(0x([0-9A-Fa-f]{8})\)""").findAll(dark)
            .associate { it.groupValues[1] to it.groupValues[2].toLong(16) }
        val c = WatchColors.dark
        val watch = mapOf(
            "background" to c.background, "surface" to c.surface, "text" to c.text, "textMuted" to c.textMuted,
            "heading" to c.heading, "primary" to c.primary, "onPrimary" to c.onPrimary, "outline" to c.outline,
            "outlineSubtle" to c.outlineSubtle, "error" to c.error,
        )
        for ((name, colour) in watch) assertEquals(name, phone[name], argb(colour))
    }

    @Test
    fun everyTextPairIsSevenToOneAndEveryEdgeThree() {
        for ((look, c) in listOf("dark" to WatchColors.dark, "ambient" to WatchColors.ambient)) {
            val text = listOf(
                "title" to (c.heading to c.background),
                "state" to (c.text to c.background),
                "end and no-game lines" to (c.textMuted to c.background),
                "big button" to (c.onPrimary to c.primary),
                "big button outlined" to (c.text to c.background),
                "big button dimmed" to (c.textMuted to c.surface),
                "pause" to (c.text to c.background),
                "trouble" to (c.error to c.background),
            )
            for ((name, pair) in text) {
                val ratio = contrast(pair.first, pair.second)
                assertTrue("$name in $look: ${"%.2f".format(ratio)}", ratio >= 7.0)
            }
            val edges = listOf(
                "pause's edge" to (c.outline to c.background),
                "outlined edge" to (c.primary to c.background),
            )
            for ((name, pair) in edges) {
                val ratio = contrast(pair.first, pair.second)
                assertTrue("$name in $look: ${"%.2f".format(ratio)}", ratio >= 3.0)
            }
        }
        assertEquals("ambient is black", Color.Black, WatchColors.ambient.background)
    }

    @Test
    fun theBuzzesAreToldApart() {
        val started = Buzz.of(WearHaptic.LISTENING_STARTED)
        val stopped = Buzz.of(WearHaptic.LISTENING_STOPPED)
        // The microphone opening: one long buzz, as strong as the motor goes.
        assertEquals(1, started.pulses)
        assertTrue(started.buzzing >= 300)
        assertEquals(255, started.amplitudes.max())
        // Closing: a different rhythm, not just a different strength.
        assertEquals(2, stopped.pulses)
        assertTrue(stopped.buzzing < started.buzzing)
        assertEquals(3, Buzz.FAILURE.pulses)
        assertNotEquals(stopped.pulses, Buzz.FAILURE.pulses)
        for (p in listOf(started, stopped, Buzz.FAILURE)) {
            assertEquals("starts at once", 0L, p.timings.first())
            assertTrue(p.amplitudes.all { it in 0..255 })
        }
    }

    @Test
    fun eachActionHasAnIcon() {
        for (action in WearAction.entries) assertTrue("$action", icon(action) != null)
        assertEquals(icon(WearAction.MIC_REFUSED), icon(WearAction.NO_RECOGNITION))
        val distinct = WearAction.entries.filter { it != WearAction.NO_RECOGNITION }.map(::icon).toSet()
        assertEquals("one icon for each thing a press does", WearAction.entries.size - 1, distinct.size)
        assertNull(icon(null))
    }

    @Test
    fun everyWordIsUsedInSentenceCaseAndNoneIsInTheCode() {
        val strings = xml(File(res, "values/strings.xml")).getElementsByTagName("string")
        val names = (0 until strings.length).map { strings.item(it).attributes.getNamedItem("name").nodeValue }
        val texts = (0 until strings.length).map { strings.item(it).textContent }
        val sources = File("src").walkTopDown().filter { it.isFile && it.extension in setOf("kt", "xml") }
            .filter { it.name != "strings.xml" }.toList()
        val code = sources.joinToString("\n") { it.readText() }
        for (name in names) {
            assertTrue("$name isn't used", Regex("""R\.string\.$name\b|@string/$name\b""").containsMatchIn(code))
        }
        for (text in texts) assertNull(text, Regex("""\b[A-Z]{4,}\b""").find(text))
        // The screen's words are the strings' or the phone's: the release code has none of its own (the debug build's
        // demo states are the phone's words, for screenshots).
        // As the phone app's StringsTest looks: what only a developer reads (the log, a failed check) aside.
        val found = mutableListOf<String>()
        for (file in File("src/main/java").walkTopDown().filter { it.isFile && it.extension == "kt" }) {
            for ((i, line) in file.readLines().withIndex()) {
                val code = line.trim()
                if (code.startsWith("//") || code.startsWith("*") || code.startsWith("/*")) continue
                if (Regex("""\bLog\.[vdiwe]\(|\bTAG = |\brequire\(""").containsMatchIn(code)) continue
                for (literal in Regex(""""((?:[^"\\]|\\.)*)"""").findAll(code.substringBefore(" // "))) {
                    val text = literal.groupValues[1]
                    val words = Regex("""[A-Za-z]+ +[A-Za-z]+""").containsMatchIn(text) ||
                        Regex("""^[A-Z][a-z]+""").containsMatchIn(text)
                    if (words) found += "${file.name}:${i + 1}: \"$text\""
                }
            }
        }
        assertEquals(emptyList<String>(), found)
    }

    private fun xml(file: File) = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file).documentElement

    private fun argb(c: Color): Long {
        fun byte(f: Float) = (f * 255 + 0.5f).toInt().toLong()
        return (byte(c.alpha) shl 24) or (byte(c.red) shl 16) or (byte(c.green) shl 8) or byte(c.blue)
    }

    /** WCAG 2.x's contrast, from relative luminance (as the phone's ContrastTest). */
    private fun contrast(a: Color, b: Color): Double {
        val la = luminance(a)
        val lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private fun luminance(c: Color): Double {
        fun channel(v: Float): Double = if (v <= 0.03928) v / 12.92 else ((v + 0.055) / 1.055).pow(2.4)
        return 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
    }
}
