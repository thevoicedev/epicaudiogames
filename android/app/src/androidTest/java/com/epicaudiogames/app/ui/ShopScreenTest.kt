package com.epicaudiogames.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToKey
import androidx.compose.ui.test.performScrollToNode
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.epicaudiogames.app.Catalog
import com.epicaudiogames.app.PackInfo
import com.epicaudiogames.app.Packs
import com.epicaudiogames.app.R
import com.epicaudiogames.app.Store
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.ClassRule
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The Shop as TalkBack meets it (docs/DESIGN.md › Shop and the store sheet): its heading and what buying is like; each
 * game with packs a level-2 section of pack rows, every state in words with an icon and each button named with its
 * words first (and read once); the store's messages said, and scrolled to, as they come; Restore purchases, and who
 * handles the payments; the purchases read again as it shows. In every look. The build's own catalog, and a Store that
 * never talks to Play: the test says what it knows.
 */
@RunWith(AndroidJUnit4::class)
open class ShopScreenTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val games = Catalog.load(InstrumentationRegistry.getInstrumentation().targetContext.assets)
    private val forSale = games.filter { it.packs.isNotEmpty() }
    private lateinit var scope: CoroutineScope
    private lateinit var store: Store
    private val bought = mutableListOf<String>()
    @Volatile private var shown = 0
    private val looks by lazy { Looks(compose) }

    @Before
    fun setUp() {
        compose.enableEpicChecks()
        scope = MainScope()
        store = Store(compose.activity, games, Packs(compose.activity), scope)
        looks.show {
            ShopScreen(games, store, installed = { it.id == INSTALLED }, onBuy = { bought += it.id }, onShown = { shown++ })
        }
    }

    @After
    fun tearDown() {
        store.close()
        scope.cancel()
    }

    @Test
    fun theHeadingAndWhatBuyingIsLike() {
        compose.onNodeWithTag("shop-heading").assert(isHeading()).assert(hasText("Shop"))
        compose.onNodeWithText("One-time purchases. No ads and no subscriptions. Packs download once, then play offline.")
            .assertExists()
        // Showing, it read the purchases again.
        compose.runOnIdle { assertEquals(1, shown) }
    }

    @Test
    fun eachGameWithPacksIsASectionWithItsRows() {
        for (game in forSale) {
            list().performScrollToKey(game.id)
            compose.onNode(isHeading() and hasText(game.title) and hasAnyAncestor(hasTestTag("shop-game-${game.id}")))
                .assertExists()
            for (pack in game.packs) list().performScrollToNode(hasTestTag("pack-${pack.id}"))
        }
    }

    @Test
    fun eachStateInWordsAndEachButtonNamedWithItsWordsFirst() {
        val (installed, priced, owned) = states()
        val game = { p: PackInfo -> games.single { it.id == p.game } }
        // Installed: a tick and the word.
        list().performScrollToNode(hasTestTag("pack-${installed.id}"))
        compose.onNode(hasText("Installed") and hasAnyAncestor(hasTestTag("pack-${installed.id}"))).assertExists()
        // For sale: the store's price, the game and the pack in its name.
        list().performScrollToNode(hasTestTag("buy-${priced.id}"))
        compose.onNodeWithTag("buy-${priced.id}")
            .assert(named("Buy for £1.99: ${game(priced).title}, ${priced.title}"))
            .assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.Text))
            .performClick()
        compose.runOnIdle { assertEquals(listOf(priced.id), bought) }
        // Bought on another phone: Download, named with its game.
        list().performScrollToNode(hasTestTag("download-${owned.id}"))
        compose.onNodeWithTag("download-${owned.id}").assert(named("Download ${owned.title} for ${game(owned).title}"))
        // Its payment pending: the clock, and why it waits, in place of the price.
        compose.runOnIdle { store.pending[priced.product] = true }
        list().performScrollToNode(hasTestTag("pack-${priced.id}"))
        compose.onNode(hasText("Payment pending") and hasAnyAncestor(hasTestTag("pack-${priced.id}"))).assertExists()
        compose.onNodeWithTag("buy-${priced.id}").assertDoesNotExist()
    }

    @Test
    fun whatTheStoreSaysIsSaidAndScrolledTo() {
        val failed = compose.activity.getString(R.string.store_purchase_failed)
        compose.runOnIdle { store.message = failed }
        // Without a screen reader, the list goes to it; TalkBack says it as it comes (a live region).
        compose.onNode(hasText(failed) and SemanticsMatcher.keyIsDefined(SemanticsProperties.LiveRegion)).assertIsDisplayed()
    }

    @Test
    fun aPurchaseThatDidntGoThroughIsSaidUnderItsRow() {
        // Buy pressed, and the purchase can't go through (this Store has no prices from Play; a build with no pack
        // server sells nothing): why, under that pack's row, where the player and TalkBack's focus are. The list
        // draws only what's in sight, so a message at its foot couldn't be said (docs/DESIGN.md › Shop: failures
        // under the row).
        val pack = forSale.flatMap { it.packs }.first { it.id != INSTALLED }
        compose.runOnIdle { store.buy(compose.activity, pack) }
        val why = compose.runOnIdle { store.failed[pack.id] }
        val reasons = listOf(R.string.store_unavailable, R.string.store_no_server).map { compose.activity.getString(it) }
        assertTrue("$why", why in reasons)
        list().performScrollToNode(hasTestTag("pack-${pack.id}"))
        compose.onNode(
            hasText(why!!) and hasAnyAncestor(hasTestTag("pack-${pack.id}")) and
                SemanticsMatcher.keyIsDefined(SemanticsProperties.LiveRegion),
        ).assertExists()
        compose.runOnIdle { assertNull(store.message) }
    }

    @Test
    fun restorePurchasesAndWhoHandlesThePayments() {
        list().performScrollToKey("restore")
        compose.onNodeWithTag("restore").assert(hasText("Restore purchases")).assertHasClickAction()
        compose.onNodeWithText("Bought a pack on another phone? Restore it here.").assertExists()
        compose.onNodeWithText("Payments are handled by Google Play.").assertExists()
    }

    @Test
    fun inEveryLook() {
        val (_, _, owned) = states()
        compose.runOnIdle {
            // A download under way, beside the installed pack and the one for sale.
            store.downloading[owned.id] = 0.4f
            store.note = compose.activity.getString(R.string.store_restored)
        }
        looks.each { look -> compose.checkAll("the Shop, $look") }
    }

    /**
     * The packs on sale in the states the Shop shows, in this order: installed ([INSTALLED]), for £1.99, and bought on
     * another phone (the rest, if the catalog has more, still asking for their price).
     */
    private fun states(): List<PackInfo> {
        val packs = forSale.flatMap { it.packs }
        val (_, priced, owned) = packs
        compose.runOnIdle {
            store.prices[priced.product] = "£1.99"
            store.owned[owned.product] = true
        }
        compose.waitForIdle()
        return packs.take(3)
    }

    /** The Shop's list. */
    private fun list() = compose.onNode(SemanticsMatcher.keyIsDefined(SemanticsProperties.IndexForKey))

    /** What TalkBack calls a button: that name, and nothing else. */
    private fun named(name: String) = SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf(name))

    private companion object {
        /** The pack the test has on the phone: the first one on sale (states()'s first). */
        val INSTALLED: String = Catalog.load(InstrumentationRegistry.getInstrumentation().targetContext.assets)
            .flatMap { it.packs }.first().id
    }
}

/** The Shop on a tablet turned sideways: the same rows, at most 640 dp wide, centred beside the rail. */
class ShopScreenTabletTest : ShopScreenTest() {
    companion object {
        @get:ClassRule
        @JvmStatic
        val tablet = TabletScreen()
    }
}
