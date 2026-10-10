package com.epicaudiogames.app

import com.epicaudiogames.engine.Step
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The app's help and sounds as Android reads them ([AppManifest]): the real content/app/app.json (tools/app_audio.py's),
 * with this app's pages only, each paragraph read by its clip and every file it plays in the folder; and the rules for
 * what's kept, on small made-up manifests. iOS: EpicAppCore's AppManifestTests.
 */
class AppManifestTest {
    private val folder = File(System.getProperty("content.dir") ?: "../../content", "app")
    private val text by lazy { File(folder, "app.json").readText() }
    private val manifest by lazy { AppManifest.parse(text) }

    @Test
    fun theRealManifestHasAndroidsPagesInItsOrder() {
        // What the file has for Android: pages for no platform, and Android's own, in the file's order.
        val raw = Json.parseToJsonElement(text).jsonObject.getValue("help").jsonArray.map { it.jsonObject }
        val ours = raw.filter { (it["platform"] as? JsonPrimitive)?.content.let { p -> p == null || p == "android" } }
            .map { (it.getValue("id") as JsonPrimitive).content }
        assertEquals(ours, manifest.help.map { it.id })
        assertEquals("a page twice", ours.toSet().size, ours.size)
        assertTrue("no help pages", manifest.help.size >= 9)
        // A page with a version for each app is Android's here.
        val androids = raw.filter { (it["platform"] as? JsonPrimitive)?.content == "android" }
        assertTrue(androids.isNotEmpty())
        for (page in androids) {
            val id = (page.getValue("id") as JsonPrimitive).content
            val kept = manifest.topic(id)!!
            assertEquals(id, (page.getValue("title") as JsonPrimitive).content, kept.title)
            assertEquals(id, page.getValue("text").jsonArray.map { (it as JsonPrimitive).content }, kept.text)
        }
        // The screen reader's page is TalkBack's, not VoiceOver's.
        val screenReader = manifest.topic("screen-reader")
        assertNotNull(screenReader)
        assertTrue(screenReader!!.title, "TalkBack" in screenReader.title)
        assertNull(manifest.topic("no-such-topic"))
    }

    @Test
    fun theWelcomeAndTheStingAreThere() {
        val welcome = manifest.welcome
        assertNotNull(welcome)
        assertEquals("welcome", welcome!!.id)
        assertTrue(welcome.text.isNotEmpty())
        assertTrue(welcome.hasClips)
        // It plays the listening sound as an example: a clip with no words.
        assertTrue(welcome.steps.any { it is Step.Play && it.sfx && it.path.startsWith("earcons/") })
        val sting = manifest.sting
        if (sting != null) {
            assertTrue("${sting.file} is missing", File(folder, sting.file).isFile)
            assertTrue(sting.seconds in 2.5..3.8)
            assertTrue(sting.voiceAt < sting.voiceEnd && sting.voiceEnd < sting.seconds)
        }
    }

    @Test
    fun theEarconsLengthsAreTheirFiles() {
        assertEquals(Earcon.entries.map { it.file }.toSet(), manifest.earcons.keys)
        for (earcon in Earcon.entries) {
            val pcm = Wav.pcm16Mono(File(folder, "earcons/${earcon.file}.wav").readBytes())!!
            assertEquals(earcon.file, pcm.samples.size / pcm.rate.toDouble(), manifest.earcons.getValue(earcon.file), 0.001)
        }
    }

    @Test
    fun everyParagraphIsReadByItsClipAndEveryClipIsInTheFolder() {
        for (page in listOfNotNull(manifest.welcome) + manifest.help) {
            val clips = page.steps.filterIsInstance<Step.Play>()
            assertEquals("${page.id}: a paragraph for each clip", clips.size, page.clipParagraph.size)
            // Each paragraph shown has the one clip that reads it, in order.
            assertEquals(page.id, page.text.indices.toList(), page.clipParagraph.filter { it >= 0 })
            clips.forEachIndexed { i, clip ->
                assertTrue("${page.id}: ${clip.path} isn't in content/app", File(folder, "${clip.path}.m4a").isFile)
                val paragraph = page.clipParagraph[i]
                if (paragraph < 0) {
                    // An earcon, as an example: no words.
                    assertTrue(clip.sfx)
                    assertTrue(clip.lines.isEmpty())
                } else {
                    // The words shown are the words spoken.
                    assertEquals(page.id, page.text[paragraph], clip.lines.joinToString(" ") { it.text })
                    for (line in clip.lines) {
                        val words = line.words ?: continue
                        assertEquals("${page.id}: a time for each word", line.text.split(Regex("\\s+")).count { it.isNotEmpty() }, words.size)
                        assertEquals("${page.id}: word times out of order", words.sorted(), words)
                    }
                }
            }
            for (link in page.links) {
                assertTrue(link.label.isNotBlank())
                assertTrue(link.url, link.url.startsWith("https://") || link.url.startsWith("mailto:"))
            }
        }
    }

    @Test
    fun pagesForTheOtherAppAreLeftOut() {
        val m = AppManifest.parse(
            """
            {"format": 1, "earcons": {},
             "welcome": {"title": "Welcome", "text": ["Hi."], "clipParagraph": [], "steps": []},
             "help": [
              {"id": "a", "title": "Both", "text": [], "clipParagraph": [], "steps": []},
              {"id": "b", "platform": "ios", "title": "iPhone", "text": [], "clipParagraph": [], "steps": []},
              {"id": "b", "platform": "android", "title": "Android", "text": [], "clipParagraph": [], "steps": []},
              {"id": "c", "platform": "watch", "title": "Elsewhere", "text": [], "clipParagraph": [], "steps": []}
             ]}
            """.trimIndent(),
        )
        assertEquals(listOf("a" to "Both", "b" to "Android"), m.help.map { it.id to it.title })
        // No sting picked yet: the intro goes without one.
        assertNull(m.sting)
        assertEquals("", m.help.first().summary)
        assertFalse(m.welcome!!.hasClips)
        // The same file, as iOS reads it.
        assertEquals(listOf("a" to "Both", "b" to "iPhone"), AppManifest.parse(
            """{"help": [{"id": "a", "title": "Both"}, {"id": "b", "platform": "ios", "title": "iPhone"},
               {"id": "b", "platform": "android", "title": "Android"}]}""",
            platform = "ios",
        ).help.map { it.id to it.title })
    }

    @Test
    fun stepsAreReadAsTheMapsHaveThem() {
        val page = AppManifest.parse(
            """
            {"help": [{"id": "x", "title": "X", "text": ["One two."], "clipParagraph": [0, -1],
              "steps": [
               {"bed": "music/soft", "volume": 0.25, "dur": 4},
               {"play": "tts/one-two", "dur": 1.5, "lines": [{"at": 0, "len": 1.4, "who": "HOST", "text": "One two.", "w": [0, 0.5]}]},
               {"pause": 0.3},
               {"play": "earcons/listen-start-demo", "dur": 0.145, "lines": [], "sfx": true},
               {"say": "a kind of step this app doesn't know"}
              ]}]}
            """.trimIndent(),
        ).topic("x")!!
        assertEquals(4, page.steps.size)
        assertEquals(Step.Bed("music/soft", 0.25, 4.0), page.steps[0])
        val clip = page.steps[1] as Step.Play
        assertEquals("tts/one-two", clip.path)
        assertEquals(listOf(0.0, 0.5), clip.lines.single().words)
        assertEquals(Step.Pause(0.3), page.steps[2])
        assertTrue((page.steps[3] as Step.Play).sfx)
        assertEquals(listOf(clip.lines, emptyList()), page.clipLines)
    }
}
