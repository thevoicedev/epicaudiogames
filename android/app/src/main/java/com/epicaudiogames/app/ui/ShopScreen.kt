package com.epicaudiogames.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.epicaudiogames.app.GameInfo
import com.epicaudiogames.app.PackInfo
import com.epicaudiogames.app.R
import com.epicaudiogames.app.Store
import com.epicaudiogames.app.ui.theme.EpicTheme
import com.epicaudiogames.app.ui.theme.LocalReduceMotion
import com.epicaudiogames.app.ui.theme.LocalScreenReader

/**
 * Where the Shop or a store sheet was opened from: the usage data's shop_view source (web/analytics/events.json). The
 * Shop tab, a game's card ("Get …"), a game's menu ("More stories and levels"), or a chapter's end that a pack unlocks.
 */
enum class ShopSource(val key: String) {
    TAB("tab"),
    CARD("card"),
    MENU("menu"),
    LOCKED_END("locked_end"),
}

/**
 * The Shop tab (docs/DESIGN.md › Shop and the store sheet): its heading and what buying is like, then every game with
 * packs as a section of pack rows (PackRows.kt, the store sheet's), the store's messages, and Restore purchases. Shown,
 * it reads the purchases again ([onShown], at most once a minute). A message the store has (how Restore purchases went,
 * by its button) is scrolled to as it comes, unless a screen reader is on: TalkBack says it, and the list doesn't move
 * under the player's finger. A purchase that didn't go through is said under its own row, where Buy was pressed: the
 * list draws only what's in sight, so a message at its foot may not be there for TalkBack to say. iOS: ShopView.swift.
 */
@Composable
fun ShopScreen(
    games: List<GameInfo>,
    store: Store,
    installed: (PackInfo) -> Boolean,
    onBuy: (PackInfo) -> Unit,
    onShown: () -> Unit,
) {
    val c = EpicTheme.colors
    val list = rememberLazyListState()
    val screenReader = LocalScreenReader.current
    val reduceMotion = LocalReduceMotion.current
    val forSale = games.filter { it.packs.isNotEmpty() }
    LaunchedEffect(Unit) { onShown() }
    // The messages are the item after the heading and every game's section.
    val messages = 1 + forSale.size
    LaunchedEffect(store.message, store.note) {
        if (screenReader || (store.message == null && store.note == null)) return@LaunchedEffect
        if (reduceMotion) list.scrollToItem(messages) else list.animateScrollToItem(messages)
    }
    LazyColumn(
        Modifier.fillMaxSize().background(c.background),
        state = list,
        contentPadding = PaddingValues(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 28.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item {
            Column(Modifier.readableWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ScreenHeader(stringResource(R.string.shop_heading), Modifier.testTag("shop-heading"))
                Text(
                    stringResource(R.string.shop_intro),
                    style = EpicTheme.type.body,
                    color = c.text,
                )
            }
        }
        items(forSale, key = { it.id }) { game ->
            Column(Modifier.readableWidth(), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                ShopDivider()
                ShopGameSection(game, store, installed, onBuy, Modifier.testTag("shop-game-${game.id}"))
            }
        }
        if (store.message != null || store.note != null) {
            item(key = "messages") { StoreMessages(store, Modifier.readableWidth()) }
        }
        item(key = "restore") {
            Column(Modifier.readableWidth(), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                ShopDivider()
                RestoreSection(store)
            }
        }
    }
}
