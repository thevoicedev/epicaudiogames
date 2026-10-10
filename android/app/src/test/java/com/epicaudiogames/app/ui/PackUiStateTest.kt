package com.epicaudiogames.app.ui

import com.epicaudiogames.app.TestWords
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * A pack's state in the Shop and the store sheet, and what its buttons are called (docs/DESIGN.md › Shop and the store
 * sheet): every state, which wins when the store knows several things at once, the download's milestones, and the
 * names TalkBack reads, each starting with the button's own words (res/values/strings.xml's). iOS: PackRowsTests.swift.
 */
class PackUiStateTest {
    private fun of(
        installed: Boolean = false,
        progress: Float? = null,
        owned: Boolean = false,
        pending: Boolean = false,
        price: String? = null,
        loading: Boolean = false,
    ) = PackUiState.of(installed, progress, owned, pending, price, loading)

    @Test
    fun eachStateOnItsOwn() {
        assertEquals(PackUiState.Installed, of(installed = true))
        assertEquals(PackUiState.Downloading(40), of(progress = 0.4f))
        assertEquals(PackUiState.Bought, of(owned = true))
        assertEquals(PackUiState.Pending, of(pending = true))
        assertEquals(PackUiState.ForSale("£1.99"), of(price = "£1.99"))
        assertEquals(PackUiState.PriceUnknown(loading = true), of(loading = true))
        assertEquals(PackUiState.PriceUnknown(loading = false), of())
    }

    @Test
    fun theFirstThatAppliesWins() {
        // Over every combination: installed, then downloading, bought, pending, a price, and last no price.
        for (installed in listOf(false, true)) for (progress in listOf(null, 0.5f)) for (owned in listOf(false, true))
            for (pending in listOf(false, true)) for (price in listOf(null, "£1.99")) for (loading in listOf(false, true)) {
                val expected = when {
                    installed -> PackUiState.Installed
                    progress != null -> PackUiState.Downloading(50)
                    owned -> PackUiState.Bought
                    pending -> PackUiState.Pending
                    price != null -> PackUiState.ForSale(price)
                    else -> PackUiState.PriceUnknown(loading)
                }
                assertEquals(
                    "installed $installed, progress $progress, owned $owned, pending $pending, price $price, " +
                        "loading $loading",
                    expected, of(installed, progress, owned, pending, price, loading),
                )
            }
    }

    @Test
    fun aDownloadIsAWholePercentFrom0To100() {
        assertEquals(0, (of(progress = 0f) as PackUiState.Downloading).percent)
        assertEquals(39, (of(progress = 0.399f) as PackUiState.Downloading).percent)
        assertEquals(100, (of(progress = 1f) as PackUiState.Downloading).percent)
        // A download that runs over its size (or a bad number) stays within the bar.
        assertEquals(100, (of(progress = 1.3f) as PackUiState.Downloading).percent)
        assertEquals(0, (of(progress = -0.2f) as PackUiState.Downloading).percent)
    }

    @Test
    fun talkBackHearsADownloadAtItsMilestonesOnly() {
        val milestones = mapOf(0 to 0, 1 to 0, 24 to 0, 25 to 25, 49 to 25, 50 to 50, 74 to 50, 75 to 75, 99 to 75, 100 to 75)
        for ((percent, milestone) in milestones) {
            assertEquals("$percent%", milestone, PackUiState.Downloading(percent).milestone)
        }
        assertEquals("45 more mysteries: downloading, 50%",
            TestWords.downloadingLabel("45 more mysteries", PackUiState.Downloading(62)))
    }

    @Test
    fun theBuyButtonsWords() {
        assertEquals("Buy for £1.99", TestWords.buyText(PackUiState.ForSale("£1.99")))
        assertEquals("Get", TestWords.buyText(PackUiState.PriceUnknown(loading = true)))
        assertEquals("Get", TestWords.buyText(PackUiState.PriceUnknown(loading = false)))
        for (state in notForSale) assertNull(state.toString(), TestWords.buyText(state))
    }

    @Test
    fun theBuyButtonsNameSaysWhichPack() {
        assertEquals("Buy for £1.99: The Werewolf, 45 more mysteries",
            TestWords.buyLabel(PackUiState.ForSale("£1.99"), "The Werewolf", "45 more mysteries"))
        assertEquals("Get The Werewolf, 45 more mysteries, loading the price",
            TestWords.buyLabel(PackUiState.PriceUnknown(loading = true), "The Werewolf", "45 more mysteries"))
        assertEquals("Get The Werewolf, 45 more mysteries",
            TestWords.buyLabel(PackUiState.PriceUnknown(loading = false), "The Werewolf", "45 more mysteries"))
        for (state in notForSale) assertNull(state.toString(), TestWords.buyLabel(state, "The Werewolf", "45 more mysteries"))
    }

    @Test
    fun eachNameStartsWithTheButtonsOwnWords() {
        // So Voice Access finds a button by what it shows (docs/DESIGN.md › Principles).
        for (state in listOf(PackUiState.ForSale("€2,29"), PackUiState.PriceUnknown(true), PackUiState.PriceUnknown(false))) {
            val label = TestWords.buyLabel(state, "Alien Customs", "10 more levels")!!
            assertTrue(label, label.startsWith(TestWords.buyText(state)!!))
        }
        val download = TestWords.downloadLabel("The Kingdom of Frootopia", "Stories 2 to 5")
        assertEquals("Download Stories 2 to 5 for The Kingdom of Frootopia", download)
        assertTrue(download.startsWith("Download Stories 2 to 5"))
    }

    @Test
    fun aDownloadsSizeToTheNearestMegabyte() {
        assertEquals("15 MB download", TestWords.downloadSize(14_558_828))
        assertEquals("26 MB download", TestWords.downloadSize(25_619_378))
        assertEquals("133 MB download", TestWords.downloadSize(133_444_602))
        assertEquals("1 MB download", TestWords.downloadSize(500_000))
    }

    private val notForSale = listOf(
        PackUiState.Installed, PackUiState.Downloading(10), PackUiState.Bought, PackUiState.Pending,
    )
}
