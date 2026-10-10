package com.epicaudiogames.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.adaptive.currentWindowSize
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.epicaudiogames.app.GameInfo
import com.epicaudiogames.app.Packs
import com.epicaudiogames.app.R
import com.epicaudiogames.app.Store
import com.epicaudiogames.app.findActivity
import com.epicaudiogames.app.ui.theme.EpicTheme
import com.epicaudiogames.app.ui.theme.LocalReduceMotion
import com.epicaudiogames.app.ui.theme.SheetBarIcons
import kotlinx.coroutines.launch

/**
 * One game's packs, over the game or the list (docs/DESIGN.md › Shop and the store sheet): the heading "More from
 * <game>", the Shop's own rows for its packs (PackRows.kt), the store's messages, Restore purchases, and Close. A pane
 * named by its heading, opened all the way; its heading takes the focus as it opens, and Escape closes it, as Close,
 * Back and a swipe down do. iOS: StoreSheet.swift.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StoreSheet(game: GameInfo, store: Store, packs: Packs, onClose: () -> Unit) {
    val c = EpicTheme.colors
    val activity = LocalContext.current.findActivity()
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val reduceMotion = LocalReduceMotion.current
    val heading = stringResource(R.string.store_heading, game.title)
    // Close slides the sheet away first (at once with Reduce Motion), as a swipe down does.
    val close: () -> Unit = {
        if (reduceMotion) {
            onClose()
        } else {
            scope.launch { sheet.hide() }.invokeOnCompletion { onClose() }
        }
    }
    val shape = BottomSheetDefaults.ExpandedShape
    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = sheet,
        // The pane's name, said as it opens: on the sheet itself, where it takes the place of Material's own ("Bottom
        // Sheet"), so it's the one pane TalkBack hears.
        modifier = Modifier.semantics { paneTitle = heading },
        shape = shape,
        containerColor = c.surfaceRaised,
        contentColor = c.text,
        // Its handle is drawn below, inside the edge: Close and Back close it, as a swipe down does.
        dragHandle = null,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                // Taller than the screen (large text), it stops under the status bar, and scrolls.
                .heightIn(max = sheetMaxHeight())
                .windowTestTags()
                .testTag("store-sheet")
                // Escape, from within the sheet (its heading has the focus): Android's own handling of it in a
                // sheet's window varies by version.
                .onPreviewKeyEvent {
                    if (it.key != Key.Escape) return@onPreviewKeyEvent false
                    if (it.type == KeyEventType.KeyUp) close()
                    true
                }
                .sheetEdge(shape, c.edgeWidth, c.outlineSubtle)
                .verticalScroll(rememberScrollState())
                .padding(start = 20.dp, end = 20.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            SheetBarIcons()
            // The handle, as a picture only.
            Spacer(
                Modifier
                    .align(Alignment.CenterHorizontally)
                    .padding(top = 16.dp)
                    .size(width = 32.dp, height = 4.dp)
                    .background(c.textMuted, RoundedCornerShape(2.dp)),
            )
            ShopGameSection(
                game, store, packs::isInstalled,
                onBuy = { pack -> activity?.let { store.buy(it, pack) } },
                title = heading,
                cover = false,
                headingModifier = Modifier.focusOnAppear(),
            )
            ShopDivider()
            StoreMessages(store)
            RestoreSection(store)
            EpicButton(stringResource(R.string.close), close, Modifier.fillMaxWidth().testTag("store-close"),
                kind = ButtonKind.Secondary)
        }
    }
}

/**
 * The tallest a sheet gets: the window's height but the status bar (or the cut-out), and a little room under that, so
 * it's seen to be a sheet. Material's would reach the top of the screen, its top under the status bar's icons, when
 * what it holds is that tall (large text). The help sheet is this tall; the store sheet at most.
 */
@Composable
internal fun sheetMaxHeight(): Dp {
    val density = LocalDensity.current
    val top = WindowInsets.safeDrawing.getTop(density)
    return with(density) { (currentWindowSize().height - top).toDp() } - SHEET_GAP
}

/** The room a sheet leaves between its top and the status bar. */
private val SHEET_GAP = 12.dp

/**
 * The sheet's edge, round its top and down its sides (its bottom is the screen's): in the contrast palettes the sheet
 * is the colour of the pause under it, and without an edge its top would be lost. The outer half of the stroke falls
 * outside the sheet, which cuts it off, so what shows is [width] wide. The help sheet (HelpScreen.kt) has it too.
 */
internal fun Modifier.sheetEdge(shape: Shape, width: Dp, color: Color) = drawWithContent {
    drawContent()
    val stroke = width.toPx()
    // The shape made taller than the sheet, so its bottom edge is below it.
    val outline = shape.createOutline(Size(size.width, size.height + stroke + 1000f), layoutDirection, this)
    drawOutline(outline, color, style = Stroke(stroke * 2))
}
