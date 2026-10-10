package com.epicaudiogames.app.ui

import android.view.KeyEvent
import com.epicaudiogames.app.AnswerTime
import com.epicaudiogames.app.AppSettings
import com.epicaudiogames.app.R
import com.epicaudiogames.app.TestWords
import com.epicaudiogames.app.ThemeChoice
import com.epicaudiogames.app.analytics.UsageDeletion
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * The tab shell's pure parts (docs/DESIGN.md › Structure, › Tablets…): the tabs' order and the names the usage data
 * gives them and the Shop's sources (web/analytics/events.json, which the server checks every event against), the
 * keyboard's shortcuts, when the game takes two panes, and Settings' choices in words (and Delete my usage data's).
 */
class TabsTest {
    @Test
    fun theTabsAreGamesShopHelpAndSettingsInThatOrder() {
        assertEquals(listOf("Games", "Shop", "Help", "Settings"), Tab.entries.map { TestWords.text(it.title) })
    }

    @Test
    fun theTabsAndShopSourcesAreNamedAsTheUsageDataAllows() {
        assertEquals(allowed("tab_view", "tab"), Tab.entries.map { it.key })
        assertEquals(allowed("shop_view", "source"), ShopSource.entries.map { it.key })
    }

    @Test
    fun spaceAndEscapeOnTheirOwn() {
        assertEquals(Shortcut.OneButton, key(KeyEvent.KEYCODE_SPACE))
        assertEquals(Shortcut.Escape, key(KeyEvent.KEYCODE_ESCAPE))
        // With a modifier key, they're something else's (Shift+Space, Ctrl+Space for the keyboard's language).
        assertNull(key(KeyEvent.KEYCODE_SPACE, shift = true))
        assertNull(key(KeyEvent.KEYCODE_SPACE, ctrl = true))
        assertNull(key(KeyEvent.KEYCODE_ESCAPE, alt = true))
    }

    @Test
    fun ctrlAndATabsNumberPicksIt() {
        val row = listOf(KeyEvent.KEYCODE_1, KeyEvent.KEYCODE_2, KeyEvent.KEYCODE_3, KeyEvent.KEYCODE_4)
        val pad = listOf(KeyEvent.KEYCODE_NUMPAD_1, KeyEvent.KEYCODE_NUMPAD_2, KeyEvent.KEYCODE_NUMPAD_3,
            KeyEvent.KEYCODE_NUMPAD_4)
        for (keys in listOf(row, pad)) {
            assertEquals(Tab.entries.map { Shortcut.ToTab(it) }, keys.map { key(it, ctrl = true) })
        }
        // Not without Ctrl (a number typed), nor with another modifier, nor past the last tab.
        assertNull(key(KeyEvent.KEYCODE_2))
        assertNull(key(KeyEvent.KEYCODE_2, ctrl = true, shift = true))
        assertNull(key(KeyEvent.KEYCODE_2, ctrl = true, alt = true))
        assertNull(key(KeyEvent.KEYCODE_2, ctrl = true, meta = true))
        assertNull(key(KeyEvent.KEYCODE_0, ctrl = true))
        assertNull(key(KeyEvent.KEYCODE_5, ctrl = true))
        assertNull(key(KeyEvent.KEYCODE_A, ctrl = true))
    }

    @Test
    fun theNewestScreenGetsAShortcutFirstAndItsKeyIsUsedUp() {
        val shortcuts = Shortcuts()
        val heard = mutableListOf<String>()
        // The tabs, under a game that uses every shortcut but the tabs' own.
        val tabs: (Shortcut) -> Boolean = { (it is Shortcut.ToTab).also { used -> if (used) heard += "tabs" } }
        val game: (Shortcut) -> Boolean = {
            heard += "game"
            it !is Shortcut.ToTab
        }
        shortcuts.add(tabs)
        shortcuts.add(game)
        assertTrue(shortcuts.handle(Shortcut.OneButton))
        assertEquals(listOf("game"), heard)
        heard.clear()
        // One the game doesn't use goes on to the screen under it.
        assertTrue(shortcuts.handle(Shortcut.ToTab(Tab.SHOP)))
        assertEquals(listOf("game", "tabs"), heard)
        shortcuts.remove(game)
        assertFalse(shortcuts.handle(Shortcut.OneButton))
    }

    @Test
    fun aUsedKeysRepeatsAndReleaseAreUsedUpToo() {
        val shortcuts = Shortcuts()
        var presses = 0
        shortcuts.add { (it == Shortcut.OneButton).also { used -> if (used) presses++ } }
        val down = KeyEvent.ACTION_DOWN
        val up = KeyEvent.ACTION_UP
        val space = KeyEvent.KEYCODE_SPACE
        assertTrue(shortcuts.key(down, space, 0, Shortcut.OneButton))
        // Held down: used up, but done once.
        assertTrue(shortcuts.key(down, space, 1, Shortcut.OneButton))
        assertTrue(shortcuts.key(down, space, 2, Shortcut.OneButton))
        assertEquals(1, presses)
        assertTrue(shortcuts.key(up, space, 0, Shortcut.OneButton))
        // Let go, it's over: another release (or another key's) isn't a shortcut's.
        assertFalse(shortcuts.released(space))
        // A shortcut no screen uses goes on to Android, press and release.
        assertFalse(shortcuts.key(down, KeyEvent.KEYCODE_ESCAPE, 0, Shortcut.Escape))
        assertFalse(shortcuts.key(up, KeyEvent.KEYCODE_ESCAPE, 0, Shortcut.Escape))
        assertFalse(shortcuts.key(down, KeyEvent.KEYCODE_ESCAPE, 1, Shortcut.Escape))
    }

    @Test
    fun theGameTakesTwoPanesOnAWideWindow() {
        assertTrue(twoPanes(WidthClass.EXPANDED, landscape = true))
        assertTrue(twoPanes(WidthClass.EXPANDED, landscape = false))
        assertTrue(twoPanes(WidthClass.MEDIUM, landscape = true))
        assertFalse(twoPanes(WidthClass.MEDIUM, landscape = false))
        assertFalse(twoPanes(WidthClass.COMPACT, landscape = true))
        assertFalse(twoPanes(WidthClass.COMPACT, landscape = false))
    }

    @Test
    fun settingsChoicesInWords() {
        with(TestWords) {
            assertEquals(listOf("Off", "25%", "50%", "75%", "100%"), AppSettings.MUSIC_VOLUMES.map { volumeWords(it) })
            assertEquals(listOf("Standard", "Large", "Larger"), AppSettings.TEXT_SCALES.map { textSizeWords(it) })
            assertEquals(listOf("Normal", "Longer", "Longest"), AnswerTime.entries.map { answerTimeWords(it) })
            assertEquals(
                listOf("Match my phone", "Light", "Dark", "High contrast"),
                ThemeChoice.entries.map { themeWords(it) },
            )
            // Time to answer's hint is a plural: "6 seconds", and "1 second" were there one.
            assertEquals(
                listOf("6 seconds", "10 seconds", "15 seconds"),
                AnswerTime.entries.map { (it.millis / 1000).toInt().let { s -> plural(R.plurals.seconds, s, s) } },
            )
            assertEquals("1 second", plural(R.plurals.seconds, 1, 1))
            assertEquals(
                listOf("0.75 times", "Normal speed", "1.25 times", "1.5 times", "1.75 times", "2 times"),
                AppSettings.VOICE_SPEEDS.map { speedWords(it) },
            )
        }
    }

    @Test
    fun deleteMyUsageDataSaysHowItWent() {
        val done = TestWords.deletionWords(UsageDeletion.DELETED, true)
        assertEquals("Your usage data is deleted." to StatusKind.Success, done)
        assertEquals(StatusKind.Error, TestWords.deletionWords(UsageDeletion.FAILED, true).second)
        // Nothing to find: none sent under the ID; or, turned off, the ID forgotten (and what was sent goes in time).
        val none = TestWords.deletionWords(UsageDeletion.NOTHING_SENT, sharing = true).first
        val off = TestWords.deletionWords(UsageDeletion.NOTHING_SENT, sharing = false).first
        assertTrue(none, "hasn't sent any usage data" in none)
        assertTrue(off, "forgot its random ID when usage data was turned off" in off)
        assertTrue(off, "13 months" in off)
    }

    private fun key(code: Int, ctrl: Boolean = false, alt: Boolean = false, shift: Boolean = false, meta: Boolean = false) =
        Shortcut.of(code, ctrl, alt, shift, meta)

    /** An event's property's allowed values, from the whitelist: `"tab_view": { "tab": "enum:games,shop,…" }`. */
    private fun allowed(event: String, property: String): List<String> {
        val events = File("../../web/analytics/events.json").readText()
        val match = Regex("\"$event\"\\s*:\\s*\\{\\s*\"$property\"\\s*:\\s*\"enum:([^\"]+)\"").find(events)
        return checkNotNull(match) { "$event.$property isn't in events.json" }.groupValues[1].split(",")
    }
}
