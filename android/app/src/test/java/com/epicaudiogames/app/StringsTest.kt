package com.epicaudiogames.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Every word the app shows or says is in res/values/strings.xml, so it can be translated and docs/DESIGN.md's wording
 * is in one place: no screen, and no label made in plain Kotlin, has words of its own in its code. Each string there is
 * used, and each is in sentence case (docs/DESIGN.md › Principles: no ALL CAPS). (The tests run in android/app.)
 */
class StringsTest {
    private val sources = File("src/main/java").walkTopDown().filter { it.isFile && it.extension == "kt" }.toList()

    /**
     * The code whose words could reach the player: all of it but the usage data's (analytics/), which shows nothing;
     * its words are event names, the server's headers and its log.
     */
    private val shown = sources.filter { it.parentFile?.name != "analytics" }

    /**
     * Literals that look like words but aren't for the player: the media session's and the wake lock's names (the
     * system's own lists show them as the app's tag).
     */
    private val notWords = setOf("EpicAudioGames", "EpicAudioGames:game")

    @Test
    fun theCodeHasNoWordsOfItsOwn() {
        val found = mutableListOf<String>()
        for (file in shown) {
            for ((i, line) in file.readLines().withIndex()) {
                val code = line.trim()
                if (code.startsWith("//") || code.startsWith("*") || code.startsWith("/*")) continue
                // What only a developer reads: the log and its tags, a failed check's message, an annotation.
                if (Regex("""\bLog\.[vdiwe]\(|\bTAG = |\brequire\(|\bcheck\(|\berror\(|Exception\(|^@""").containsMatchIn(code)) {
                    continue
                }
                for (literal in Regex(""""((?:[^"\\]|\\.)*)"""").findAll(code.substringBefore(" // "))) {
                    val text = literal.groupValues[1]
                    if (text in notWords) continue
                    // What's left once the values put in it are taken out.
                    val bare = text.replace(Regex("""\$\{[^}]*}|\$[A-Za-z_]+"""), "")
                    val words = Regex("""[A-Za-z]+ +[A-Za-z]+""").containsMatchIn(bare) ||
                        Regex("""^[A-Z][a-z]+""").containsMatchIn(bare)
                    if (words) found += "${file.name}:${i + 1}: \"$text\""
                }
            }
        }
        assertEquals("words in the code, not in strings.xml:\n${found.joinToString("\n")}", emptyList<String>(), found)
    }

    @Test
    fun everyStringIsUsed() {
        val code = sources.joinToString("\n") { it.readText() } +
            File("src/main").walkTopDown().filter { it.isFile && it.extension == "xml" }.joinToString("\n") { it.readText() }
        val unused = TestWords.strings.keys.filter { name ->
            !Regex("""R\.(string|plurals)\.$name\b|@string/$name\b""").containsMatchIn(code)
        }
        assertEquals("strings nothing uses", emptyList<String>(), unused)
    }

    @Test
    fun everyStringIsInSentenceCase() {
        for ((name, text) in TestWords.strings) {
            // A word of four or more capitals is shouting (an initialism like MB, ID or SIL is shorter).
            val shouted = Regex("""\b[A-Z]{4,}\b""").find(text)
            assertTrue("$name: \"$text\" has ${shouted?.value} in capitals", shouted == null)
        }
    }

    @Test
    fun theStringsFileHasTheWordsTheTestsUse() {
        // A string read back as Android reads it: escapes undone, placeholders filled.
        assertEquals("Talk (speech recognition isn't available)", TestWords.text(R.string.circle_talk_no_recognition))
        assertEquals("Downloading, 40%", TestWords.text(R.string.pack_downloading, 40))
        assertEquals("“yes please”", TestWords.text(R.string.status_heard, "yes please"))
    }
}
