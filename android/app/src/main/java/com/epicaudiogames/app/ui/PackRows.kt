package com.epicaudiogames.app.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.ShoppingBag
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.unit.dp
import com.epicaudiogames.app.GameInfo
import com.epicaudiogames.app.PackInfo
import com.epicaudiogames.app.R
import com.epicaudiogames.app.Store
import com.epicaudiogames.app.Words
import com.epicaudiogames.app.rememberWords
import com.epicaudiogames.app.ui.theme.EpicTheme
import com.epicaudiogames.app.ui.theme.isAccessibilityTextSize

// A game's packs, as the Shop tab and the store sheet show them (docs/DESIGN.md › Shop and the store sheet): each
// pack's title, what it adds, its download's size and its state, always as words with an icon, never colour alone;
// then the store's messages and Restore purchases. Store.kt does the buying and the downloads. iOS: PackRows.swift.

/** What a pack shows: its state, from what the store knows of it (Store.kt). */
sealed interface PackUiState {
    /** On this phone: a tick and "Installed". */
    data object Installed : PackUiState

    /**
     * Downloading, [percent] done (0 to 100): the bar and "Downloading, 40%". What TalkBack says by itself changes only
     * at each [milestone] (0, 25, 50 and 75%), so it isn't talking all the way through.
     */
    data class Downloading(val percent: Int) : PackUiState {
        val milestone: Int get() = (percent / 25 * 25).coerceAtMost(75)
    }

    /** Paid for (on this phone or another) but not here: "Bought", and its Download button. */
    data object Bought : PackUiState

    /** Paid for with a payment still to be approved: a clock and "Payment pending". */
    data object Pending : PackUiState

    /** For sale: "Buy for [price]", the store's own price text ("£1.99"). */
    data class ForSale(val price: String) : PackUiState

    /** For sale, its price not known (yet): "Get", with a spinner while the store is asked ([loading]); it still works. */
    data class PriceUnknown(val loading: Boolean) : PackUiState

    companion object {
        /**
         * A pack's state: [installed] (at the catalog's version), how far its download has got ([progress], 0 to 1, or
         * null when it isn't downloading), whether it's [owned] or its payment [pending], and its [price] if the store
         * has said ([loading]: it's being asked). The first that applies, in that order.
         */
        fun of(
            installed: Boolean,
            progress: Float?,
            owned: Boolean,
            pending: Boolean,
            price: String?,
            loading: Boolean,
        ): PackUiState = when {
            installed -> Installed
            progress != null -> Downloading((progress * 100).toInt().coerceIn(0, 100))
            owned -> Bought
            pending -> Pending
            price != null -> ForSale(price)
            else -> PriceUnknown(loading)
        }
    }
}

/** The buy button's words, for a pack that's for sale: "Buy for £1.99", or "Get" until the price is known. */
fun Words.buyText(state: PackUiState): String? = when (state) {
    is PackUiState.ForSale -> text(R.string.pack_buy, state.price)
    is PackUiState.PriceUnknown -> text(R.string.pack_get)
    else -> null
}

/**
 * The buy button's name for TalkBack: its words first, so Voice Access finds it by what it shows, then which pack it
 * is ("Buy for £1.99: The Werewolf, 45 more mysteries"; "Get The Werewolf, 45 more mysteries, loading the price").
 * Null for a pack that isn't for sale.
 */
fun Words.buyLabel(state: PackUiState, gameTitle: String, packTitle: String): String? = when (state) {
    is PackUiState.ForSale -> text(R.string.pack_buy_label, state.price, gameTitle, packTitle)
    is PackUiState.PriceUnknown ->
        text(if (state.loading) R.string.pack_get_loading_label else R.string.pack_get_label, gameTitle, packTitle)
    else -> null
}

/** A bought pack's Download button's name for TalkBack, its words first: "Download 45 more mysteries for The Werewolf". */
fun Words.downloadLabel(gameTitle: String, packTitle: String): String =
    text(R.string.pack_download_label, packTitle, gameTitle)

/** What TalkBack hears of a download, at its milestones only: "45 more mysteries: downloading, 50%". */
fun Words.downloadingLabel(packTitle: String, state: PackUiState.Downloading): String =
    text(R.string.pack_downloading_label, packTitle, state.milestone)

/** A pack's download size, to the nearest megabyte: "15 MB download". */
fun Words.downloadSize(bytes: Long): String = text(R.string.pack_size, (bytes + 500_000) / 1_000_000)

/**
 * A game's packs: its [title] as a level-2 heading (in the Shop the game's, beside a small [cover] that's only a
 * picture; in the store sheet "More from …"), then a row for each pack. [installed] says which are on this phone, and
 * [onBuy] buys one.
 */
@Composable
fun ShopGameSection(
    game: GameInfo,
    store: Store,
    installed: (PackInfo) -> Boolean,
    onBuy: (PackInfo) -> Unit,
    modifier: Modifier = Modifier,
    title: String = game.title,
    cover: Boolean = true,
    headingModifier: Modifier = Modifier,
) {
    val c = EpicTheme.colors
    store.installs    // read, so a pack shows as installed once it is
    Column(modifier, verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            // At accessibility text sizes the words need the room more than the picture does.
            if (cover && !isAccessibilityTextSize()) {
                SmallCover(game.id)
                Spacer(Modifier.width(12.dp))
            }
            SectionHeading(title, headingModifier.weight(1f))
        }
        game.packs.forEachIndexed { i, pack ->
            if (i > 0) HorizontalDivider(thickness = c.edgeWidth, color = c.outlineSubtle)
            PackRow(pack, game, store, installed(pack)) { onBuy(pack) }
        }
    }
}

/** A game's cover, small and square: a picture only (the heading beside it names the game). */
@Composable
private fun SmallCover(id: String) {
    val shape = RoundedCornerShape(8.dp)
    val cover = rememberAssetImage("$id/cover.jpg")
    if (cover != null) {
        Image(cover, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(56.dp).clip(shape))
    } else {
        Spacer(Modifier.size(56.dp).background(EpicTheme.colors.surface, shape))
    }
}

/**
 * A pack: its title, what it adds, its download's size, and its state ([PackUiState]): "Installed", its download, that
 * it's bought (and its Download button), that its payment is pending, or its Buy button. A purchase or a download that
 * didn't go through says so under it, as it happens (TalkBack too: it's where the player pressed Buy). TalkBack reads
 * the title and description as text and each button by its full name.
 */
@Composable
fun PackRow(pack: PackInfo, game: GameInfo, store: Store, installed: Boolean, onBuy: () -> Unit) {
    val c = EpicTheme.colors
    val words = rememberWords()
    val state = PackUiState.of(
        installed = installed,
        progress = store.downloading[pack.id],
        owned = pack.product in store.owned,
        pending = pack.product in store.pending,
        price = store.prices[pack.product],
        loading = store.loading,
    )
    Column(Modifier.fillMaxWidth().testTag("pack-${pack.id}"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(pack.title, style = EpicTheme.type.itemTitle, color = c.text)
        if (pack.description.isNotEmpty()) {
            Text(pack.description, style = EpicTheme.type.body, color = c.text)
        }
        Text(words.downloadSize(pack.size), style = EpicTheme.type.secondary, color = c.textMuted)
        when (state) {
            PackUiState.Installed -> PackStatus(Icons.Default.CheckCircle, stringResource(R.string.pack_installed), c.success)
            is PackUiState.Downloading -> Downloading(pack, state, store.downloading[pack.id] ?: 0f)
            PackUiState.Bought -> {
                PackStatus(Icons.Outlined.ShoppingBag, stringResource(R.string.pack_bought), c.text)
                EpicButton(
                    stringResource(R.string.pack_download, pack.title),
                    store::restoreNow,
                    Modifier.fillMaxWidth().testTag("download-${pack.id}"),
                    icon = Icons.Default.Download,
                    description = words.downloadLabel(game.title, pack.title),
                )
            }
            PackUiState.Pending -> {
                PackStatus(Icons.Outlined.Schedule, stringResource(R.string.pack_pending), c.text)
                Text(stringResource(R.string.pack_pending_note), style = EpicTheme.type.secondary, color = c.textMuted)
            }
            is PackUiState.ForSale, is PackUiState.PriceUnknown -> EpicButton(
                words.buyText(state).orEmpty(),
                onBuy,
                Modifier.fillMaxWidth().testTag("buy-${pack.id}"),
                busy = state is PackUiState.PriceUnknown && state.loading,
                description = words.buyLabel(state, game.title, pack.title),
            )
        }
        store.failed[pack.id]?.let { StatusText(it, kind = StatusKind.Error) }
    }
}

/** A pack's state as an icon and words ("Installed" in the success colour). */
@Composable
private fun PackStatus(icon: ImageVector, text: String, color: Color) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(8.dp))
        Text(text, style = EpicTheme.type.label, color = color)
    }
}

/**
 * A download: the 8 dp bar (TalkBack reads its percent when it's on it) and "Downloading, 40%", which TalkBack says by
 * itself only as it passes 0, 25, 50 and 75% ("45 more mysteries: downloading, 50%").
 */
@Composable
private fun Downloading(pack: PackInfo, state: PackUiState.Downloading, progress: Float) {
    val c = EpicTheme.colors
    val label = rememberWords().downloadingLabel(pack.title, state)
    val shape = RoundedCornerShape(4.dp)
    LinearProgressIndicator(
        progress = { progress },
        modifier = Modifier
            .fillMaxWidth()
            .height(8.dp)
            .clip(shape)
            .then(c.progressEdge?.let { Modifier.border(2.dp, it, shape) } ?: Modifier),
        color = c.progressFill,
        trackColor = c.progressTrack,
        strokeCap = StrokeCap.Butt,
        gapSize = 0.dp,
        drawStopIndicator = {},
    )
    Text(
        stringResource(R.string.pack_downloading, state.percent),
        Modifier.clearAndSetSemantics {
            contentDescription = label
            liveRegion = LiveRegionMode.Polite
        },
        style = EpicTheme.type.label,
        color = c.text,
    )
}

/**
 * What the store has to say that isn't about one pack: the store not being there (an error, with its icon), or how
 * Restore purchases went. Said by TalkBack as it appears (StatusText). A purchase that didn't go through is said under
 * its pack's row ([PackRow]), where Buy was pressed.
 */
@Composable
fun StoreMessages(store: Store, modifier: Modifier = Modifier) {
    val message = store.message
    val note = store.note
    if (message == null && note == null) return
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        message?.let { StatusText(it, Modifier.testTag("store-message"), kind = StatusKind.Error) }
        note?.let { StatusText(it, Modifier.testTag("store-note")) }
    }
}

/** Restore purchases, what it's for, and who handles the payments. */
@Composable
fun RestoreSection(store: Store, modifier: Modifier = Modifier) {
    val c = EpicTheme.colors
    Column(modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(stringResource(R.string.restore_intro), style = EpicTheme.type.body, color = c.text)
        EpicButton(stringResource(R.string.restore), store::restoreNow, Modifier.fillMaxWidth().testTag("restore"),
            kind = ButtonKind.Secondary)
        Text(stringResource(R.string.restore_payments), style = EpicTheme.type.secondary, color = c.textMuted)
    }
}

/** A divider between a sheet's or the Shop's parts, in the theme's decorative edge. */
@Composable
internal fun ShopDivider(modifier: Modifier = Modifier) {
    HorizontalDivider(modifier.padding(vertical = 4.dp), thickness = EpicTheme.colors.edgeWidth,
        color = EpicTheme.colors.outlineSubtle)
}
