package com.epicaudiogames.app.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.max
import androidx.compose.ui.unit.min
import com.epicaudiogames.app.GameInfo
import com.epicaudiogames.app.PackInfo
import com.epicaudiogames.app.R
import com.epicaudiogames.app.ui.theme.EpicTheme
import com.epicaudiogames.app.ui.theme.isAccessibilityTextSize
import kotlinx.coroutines.delay

/**
 * Games: its heading, how to play in a line, and a card per game: one column, at most [MAX_CONTENT_WIDTH] wide, or
 * on an expanded window (a tablet in landscape, a Chromebook) two, each at most [CARD_MAX_WIDTH] (docs/DESIGN.md ›
 * Tablets…). Centred, the whole width scrolls. [gridState] is kept by the app's model, so the list is where it was
 * after a game, after it's drawn again for a pack installed, and (the same game at the top) in either layout. The tab
 * keeps it clear of the system's bars (MainTabs). iOS: HomeView.swift.
 *
 * With [focusHeading] (the intro or onboarding just ended: docs/DESIGN.md › Everywhere › Focus), the heading takes the
 * focus, and TalkBack's, a moment after it shows; [onHeadingFocused] says it's done, so it isn't done again.
 */
@Composable
fun HomeScreen(
    gridState: LazyGridState,
    games: List<GameInfo>,
    inProgress: (String) -> Boolean,
    installed: (PackInfo) -> Boolean,
    onOpen: (GameInfo) -> Unit,
    onStore: (GameInfo) -> Unit,
    focusHeading: Boolean = false,
    onHeadingFocused: () -> Unit = {},
) {
    val c = EpicTheme.colors
    val columns = if (windowWidthClass() == WidthClass.EXPANDED) 2 else 1
    // Always focusable, so it doesn't stop being so under the focus once it has it.
    val heading = remember { FocusRequester() }
    if (focusHeading) {
        LaunchedEffect(Unit) {
            delay(FOCUS_DELAY_MS)
            runCatching { heading.requestFocus() }
            onHeadingFocused()
        }
    }
    BoxWithConstraints(Modifier.fillMaxSize().background(c.background)) {
        val content = if (columns == 2) CARD_MAX_WIDTH * 2 + CARD_GAP else MAX_CONTENT_WIDTH
        val side = max(16.dp, (maxWidth - content) / 2)
        LazyVerticalGrid(
            columns = GridCells.Fixed(columns),
            modifier = Modifier.fillMaxSize(),
            state = gridState,
            contentPadding = PaddingValues(start = side, top = 16.dp, end = side, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalArrangement = Arrangement.spacedBy(CARD_GAP),
        ) {
            item(key = "heading", span = { GridItemSpan(maxLineSpan) }) {
                Column(Modifier.widthIn(max = MAX_CONTENT_WIDTH), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    ScreenHeader(
                        stringResource(R.string.games_heading),
                        Modifier
                            .testTag("games-heading")
                            .focusRequester(heading)
                            .focusRing(RoundedCornerShape(8.dp))
                            .focusable(),
                    )
                    Text(stringResource(R.string.games_intro), style = EpicTheme.type.body, color = c.text)
                }
            }
            items(games, key = { it.id }) { game ->
                GameCard(game, inProgress(game.id), installed, onStore = { onStore(game) }) { onOpen(game) }
            }
        }
    }
}

/** The widest a game's card gets, two to a row on an expanded window. */
val CARD_MAX_WIDTH = 480.dp

/** The gap between two cards side by side. */
private val CARD_GAP = 16.dp

/**
 * A game's card, with two things to do. The card itself (its cover, title, blurb, what's free, "In progress", and
 * "Play ›" or "Carry on ›") opens the game: TalkBack reads it as one element ("The Werewolf. In progress. … 5 stories
 * free."), with "Carry on" as what a double tap does, and "More stories and levels" in its actions while a pack is
 * still to get. Under it, its own button gets that pack: "Get 45 more mysteries" (for TalkBack, "… for The
 * Werewolf"), or with every pack in, the words "All packs installed".
 */
@Composable
private fun GameCard(
    game: GameInfo,
    continuing: Boolean,
    installed: (PackInfo) -> Boolean,
    onStore: () -> Unit,
    onOpen: () -> Unit,
) {
    val c = EpicTheme.colors
    val shape = RoundedCornerShape(16.dp)
    val action = stringResource(if (continuing) R.string.carry_on else R.string.card_play)
    val inProgress = stringResource(R.string.card_in_progress)
    val more = stringResource(R.string.more_stories)
    val toGet = game.packs.firstOrNull { !installed(it) }
    val spoken = sentences(game.title, inProgress.takeIf { continuing }, game.blurb, game.free)
    // As wide as its column of the grid (HomeScreen keeps that within the widths for its layout).
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.surface)
            .border(c.edgeWidth, c.outlineSubtle, shape),
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .testTag("game-${game.id}")
                .focusRing(shape)
                .clickable(onClickLabel = action, role = Role.Button, onClick = onOpen)
                .clearAndSetSemantics {
                    contentDescription = spoken
                    if (toGet != null) {
                        customActions = listOf(CustomAccessibilityAction(more) { onStore(); true })
                    }
                },
        ) {
            // At accessibility text sizes the words need the room more than the picture does.
            if (!isAccessibilityTextSize()) Cover(game.id)
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (continuing) Badge(inProgress, Icons.Default.Bookmark)
                Text(game.title, style = EpicTheme.type.itemTitle, color = c.text)
                if (game.blurb.isNotBlank()) Text(game.blurb, style = EpicTheme.type.body, color = c.text)
                if (game.free.isNotBlank()) Text(game.free, style = EpicTheme.type.secondary, color = c.textMuted)
                // What the card does, as words: it looks like the button it is.
                Row(
                    Modifier
                        .align(Alignment.End)
                        .background(c.primary, RoundedCornerShape(14.dp))
                        .padding(start = 20.dp, end = 12.dp, top = 12.dp, bottom = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(action, style = EpicTheme.type.label, color = c.onPrimary)
                    Spacer(Modifier.width(4.dp))
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = c.onPrimary)
                }
            }
        }
        if (game.packs.isNotEmpty()) {
            HorizontalDivider(thickness = c.edgeWidth, color = c.outlineSubtle)
            if (toGet != null) {
                EpicButton(
                    stringResource(R.string.get_pack, toGet.title),
                    onStore,
                    Modifier.fillMaxWidth().padding(16.dp).testTag("packs-${game.id}"),
                    kind = ButtonKind.Secondary,
                    icon = Icons.Default.Add,
                    description = stringResource(R.string.get_pack_for, toGet.title, game.title),
                )
            } else {
                Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.CheckCircle, contentDescription = null, tint = c.success, modifier = Modifier.size(24.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(stringResource(R.string.card_all_installed), style = EpicTheme.type.body, color = c.text)
                }
            }
        }
    }
}

/** A game's cover, as wide as the card and at most 180 dp tall (16:9 on a phone; cropped on a wide screen). */
@Composable
private fun Cover(id: String) {
    val cover = rememberAssetImage("$id/cover.jpg")
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val height = min(maxWidth * 9 / 16, 180.dp)
        if (cover != null) {
            Image(cover, contentDescription = null, contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxWidth().height(height))
        } else {
            Spacer(Modifier.fillMaxWidth().height(height).background(EpicTheme.colors.surfaceRaised))
        }
    }
}

/** Parts read as sentences, one after another: each gets a full stop unless it ends a sentence already. */
internal fun sentences(vararg parts: String?): String =
    parts.filterNotNull().map { it.trim() }.filter { it.isNotEmpty() }
        .joinToString(" ") { if (it.last() in ".!?…") it else "$it." }

/** An image from the app's assets (a game's cover), decoded once. */
@Composable
fun rememberAssetImage(path: String): ImageBitmap? {
    val context = LocalContext.current
    return remember(path) {
        runCatching { context.assets.open(path).use { BitmapFactory.decodeStream(it)?.asImageBitmap() } }.getOrNull()
    }
}
