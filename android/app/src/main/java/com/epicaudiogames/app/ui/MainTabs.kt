package com.epicaudiogames.app.ui

import androidx.activity.compose.BackHandler
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Help
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material.icons.outlined.Headphones
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Storefront
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.NavigationRailItemDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.currentWindowSize
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CollectionInfo
import androidx.compose.ui.semantics.CollectionItemInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.collectionInfo
import androidx.compose.ui.semantics.collectionItemInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.epicaudiogames.app.R
import com.epicaudiogames.app.ui.theme.EpicTheme

/**
 * The app's four places, in the bar's order (docs/DESIGN.md › Structure): Games, Shop, Help and Settings. [key] is
 * the name the usage data gives it (web/analytics/events.json's tab_view), [title] its label's string. iOS:
 * MainTabs.swift.
 */
enum class Tab(val key: String, @StringRes val title: Int) {
    GAMES("games", R.string.tab_games),
    SHOP("shop", R.string.tab_shop),
    HELP("help", R.string.tab_help),
    SETTINGS("settings", R.string.tab_settings),
    ;

    /** Its icon: filled for the tab showing, outlined for the others, so which one it is isn't colour alone. */
    fun icon(selected: Boolean): ImageVector = when (this) {
        GAMES -> if (selected) Icons.Filled.Headphones else Icons.Outlined.Headphones
        SHOP -> if (selected) Icons.Filled.Storefront else Icons.Outlined.Storefront
        HELP -> if (selected) Icons.AutoMirrored.Filled.Help else Icons.AutoMirrored.Outlined.HelpOutline
        SETTINGS -> if (selected) Icons.Filled.Settings else Icons.Outlined.Settings
    }
}

/**
 * The tabs (docs/DESIGN.md › Tab bar, and › Tablets…): the [selected] tab's [content], with the bar along the bottom on
 * a phone and a rail down the side on a medium or expanded window (Material's NavigationSuiteScaffold picks). Each tab
 * is a Tab with its label always shown and its place read out ("Selected, Shop, Tab, 2 of 4"), and the bar is edged,
 * as the contrast themes give it the content's own colour. A game is shown instead of all of this, full screen.
 * When the labels don't fit four across (large text on a phone), the bar is our own [TabRows], which gives each tab
 * the room for its whole label (the rail grows to fit them by itself).
 *
 * Back on another tab goes to Games, and on Games leaves the app; a page within a tab (Settings › Licences) goes back
 * first. Ctrl with 1 to 4 picks a tab. A tab picked by hand keeps the focus on it.
 */
@Composable
fun MainTabs(selected: Tab, onSelect: (Tab) -> Unit, content: @Composable (Tab) -> Unit) {
    val c = EpicTheme.colors
    val suggested = NavigationSuiteScaffoldDefaults.calculateFromAdaptiveInfo(currentWindowAdaptiveInfo())
    val across = tabsAcross()
    val ownBar = suggested == NavigationSuiteType.NavigationBar && across < Tab.entries.size
    val layout = if (ownBar) NavigationSuiteType.None else suggested
    BackHandler(enabled = selected != Tab.GAMES) { onSelect(Tab.GAMES) }
    KeyShortcuts { shortcut ->
        if (shortcut is Shortcut.ToTab) {
            onSelect(shortcut.tab)
            true
        } else {
            false
        }
    }
    // Words at full strength whether picked or not; the one picked has the primary pill behind its filled icon.
    val itemColors = NavigationSuiteDefaults.itemColors(
        navigationBarItemColors = NavigationBarItemDefaults.colors(
            selectedIconColor = c.onPrimary,
            selectedTextColor = c.text,
            indicatorColor = c.primary,
            unselectedIconColor = c.text,
            unselectedTextColor = c.text,
        ),
        navigationRailItemColors = NavigationRailItemDefaults.colors(
            selectedIconColor = c.onPrimary,
            selectedTextColor = c.text,
            indicatorColor = c.primary,
            unselectedIconColor = c.text,
            unselectedTextColor = c.text,
        ),
    )
    val labelStyle = EpicTheme.type.tab
    NavigationSuiteScaffold(
        navigationSuiteItems = {
            for (tab in Tab.entries) {
                val on = tab == selected
                item(
                    selected = on,
                    onClick = { onSelect(tab) },
                    icon = { Icon(tab.icon(on), contentDescription = null) },
                    modifier = Modifier.testTag("tab-${tab.key}").focusRing(RoundedCornerShape(16.dp)),
                    // On one line: the rail grows to fit it, and where it wouldn't fit its quarter of the bar, the bar
                    // is TabRows instead.
                    label = { Text(stringResource(tab.title), style = labelStyle, textAlign = TextAlign.Center) },
                    colors = itemColors,
                )
            }
        },
        layoutType = layout,
        navigationSuiteColors = NavigationSuiteDefaults.colors(
            navigationBarContainerColor = c.surfaceRaised,
            navigationBarContentColor = c.text,
            navigationRailContainerColor = c.surfaceRaised,
            navigationRailContentColor = c.text,
        ),
        containerColor = c.background,
        contentColor = c.text,
    ) {
        Column(Modifier.fillMaxSize()) {
            // The tab's content keeps clear of the status bar, the cut-out and (beside the rail) the navigation bar;
            // the bar or rail has the rest. The edge is drawn within that, so the rail's starts under the status bar.
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .then(
                        if (ownBar) Modifier.consumeWindowInsets(WindowInsets.safeDrawing.only(WindowInsetsSides.Bottom))
                        else Modifier,
                    )
                    .windowInsetsPadding(WindowInsets.safeDrawing)
                    .barEdge(if (ownBar) NavigationSuiteType.NavigationBar else layout, c.edgeWidth, c.outlineSubtle),
            ) {
                content(selected)
            }
            if (ownBar) TabRows(selected, onSelect, columns = across)
        }
    }
}

/**
 * How many tabs fit across the bottom of the window with their labels whole: four, as Material's bar has them (each
 * label on one line under its icon, in a quarter of the width); else two or one, each its icon and label side by side
 * ([TabRows]). From the labels as they're drawn now: the phone's font size and Settings › Text size grow them.
 */
@Composable
private fun tabsAcross(): Int {
    val style = EpicTheme.type.tab
    val measurer = rememberTextMeasurer()
    val width = currentWindowSize().width
    val titles = Tab.entries.map { stringResource(it.title) }
    val widest = remember(style, measurer, titles) { titles.maxOf { measurer.measure(it, style).size.width } }
    with(LocalDensity.current) {
        val gap = BAR_GAP.roundToPx()
        if (widest <= (width - gap * (Tab.entries.size - 1)) / Tab.entries.size) return Tab.entries.size
        val cell = widest + (CELL_PADDING * 2 + 24.dp + ICON_GAP).roundToPx()
        return if (cell * 2 + gap <= width - (BAR_PADDING * 2).roundToPx()) 2 else 1
    }
}

/**
 * The tab bar for large text on a phone (docs/DESIGN.md › Tab bar: "if labels clip at 200% text, use a custom bar with
 * the same semantics"): the tabs [columns] to a row, each its icon and its whole label side by side, as tall as they
 * need, on the bar's colour. The tab showing is filled in the primary colour, with the filled icon. TalkBack hears the
 * same as from Material's bar: a group of tabs, each with its place ("Selected, Shop, Tab, 2 of 4").
 */
@Composable
private fun TabRows(selected: Tab, onSelect: (Tab) -> Unit, columns: Int) {
    val c = EpicTheme.colors
    Column(
        Modifier
            .fillMaxWidth()
            .background(c.surfaceRaised)
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal + WindowInsetsSides.Bottom))
            .padding(BAR_PADDING)
            .selectableGroup()
            .semantics { collectionInfo = CollectionInfo(rowCount = 1, columnCount = Tab.entries.size) },
        verticalArrangement = Arrangement.spacedBy(BAR_GAP),
    ) {
        for (row in Tab.entries.chunked(columns)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(BAR_GAP)) {
                for (tab in row) TabCell(tab, tab == selected, { onSelect(tab) }, Modifier.weight(1f))
                // A row that's short (an odd one out) keeps its tab the width of the others.
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/** A tab in [TabRows]: its icon and label, the whole cell a Tab (and the tab showing, filled). */
@Composable
private fun TabCell(tab: Tab, on: Boolean, onClick: () -> Unit, modifier: Modifier) {
    val c = EpicTheme.colors
    val shape = RoundedCornerShape(24.dp)
    val color = if (on) c.onPrimary else c.text
    Row(
        modifier
            .heightIn(min = 56.dp)
            .testTag("tab-${tab.key}")
            .focusRing(shape)
            .clip(shape)
            .background(if (on) c.primary else Color.Transparent)
            .selectable(selected = on, role = Role.Tab, onClick = onClick)
            .semantics { collectionItemInfo = CollectionItemInfo(0, 1, tab.ordinal, 1) }
            .padding(horizontal = CELL_PADDING, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Icon(tab.icon(on), contentDescription = null, tint = color)
        Spacer(Modifier.width(ICON_GAP))
        Text(stringResource(tab.title), style = EpicTheme.type.tab, color = color)
    }
}

/** The gap between the bar's tabs (Material's, between its items) and round [TabRows]' own. */
private val BAR_GAP = 8.dp
private val BAR_PADDING = 8.dp
/** A [TabCell]'s room either side, and between its icon and label. */
private val CELL_PADDING = 16.dp
private val ICON_GAP = 8.dp

/**
 * The edge between the content and the bar (its bottom) or the rail (its leading side): in the contrast palettes the
 * bar is the content's own colour, and only this tells them apart.
 */
private fun Modifier.barEdge(layout: NavigationSuiteType, width: Dp, color: Color) = drawWithContent {
    drawContent()
    val stroke = width.toPx()
    when (layout) {
        NavigationSuiteType.NavigationBar -> {
            val y = size.height - stroke / 2
            drawLine(color, Offset(0f, y), Offset(size.width, y), stroke)
        }
        NavigationSuiteType.NavigationRail -> {
            val x = if (layoutDirection == LayoutDirection.Rtl) size.width - stroke / 2 else stroke / 2
            drawLine(color, Offset(x, 0f), Offset(x, size.height), stroke)
        }
        else -> Unit
    }
}
