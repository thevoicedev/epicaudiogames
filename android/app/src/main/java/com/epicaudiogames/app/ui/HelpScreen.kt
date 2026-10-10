package com.epicaudiogames.app.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.core.snap
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.currentWindowSize
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffold
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldDefaults
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldRole
import androidx.compose.material3.adaptive.layout.ThreePaneScaffoldDestinationItem
import androidx.compose.material3.adaptive.layout.calculatePaneScaffoldDirective
import androidx.compose.material3.adaptive.layout.calculateThreePaneScaffoldValue
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import com.epicaudiogames.app.AppClip
import com.epicaudiogames.app.HelpHighlight
import com.epicaudiogames.app.HelpPage
import com.epicaudiogames.app.Links
import com.epicaudiogames.app.PageAudio
import com.epicaudiogames.app.R
import com.epicaudiogames.app.ui.theme.EpicTheme
import com.epicaudiogames.app.ui.theme.LocalAppSettings
import com.epicaudiogames.app.ui.theme.LocalReduceMotion
import com.epicaudiogames.app.ui.theme.LocalScreenReader
import com.epicaudiogames.app.ui.theme.SheetBarIcons
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The Help tab (docs/DESIGN.md › Help): its heading, a row per topic (its title and a line about it), Show the welcome
 * again, and how to reach us. A topic opens its page: its heading, Listen (the page read aloud in Jessica's voice, the
 * word being read marked), its paragraphs and its links. The [pages] are this app's, from content/app/app.json
 * (AppManifest), in its order: the words shown are the words spoken.
 *
 * On a phone the page takes the list's place, and Back (or Escape, or All help topics) returns to the list, with the
 * focus back on the topic's row for a keyboard or TalkBack; on an expanded window (a tablet in landscape, a Chromebook)
 * the list and the page are side by side (ListDetailPaneScaffold), the topic showing marked as selected. [topic] is the
 * one open (AppModel keeps it while other tabs show); [onTopic] opens one, or closes it (null). A topic opened here
 * takes the focus to its heading; one still open as the tab comes back doesn't (a tab picked keeps the focus). One
 * opened from elsewhere ([focusTopic]: Settings › How to play) takes it once, as one opened here does, and
 * [onTopicFocused] says so. iOS: HelpView.swift.
 */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun HelpScreen(
    pages: List<HelpPage>,
    audio: PageAudio,
    topic: String?,
    onTopic: (String?) -> Unit,
    onShowWelcome: () -> Unit,
    focusTopic: Boolean = false,
    onTopicFocused: () -> Unit = {},
) {
    val page = topic?.let { id -> pages.firstOrNull { it.id == id } }
    val directive = calculatePaneScaffoldDirective(currentWindowAdaptiveInfo())
    val twoPanes = directive.maxHorizontalPartitions > 1
    val reduceMotion = LocalReduceMotion.current
    val keyboard = LocalInputModeManager.current.inputMode == InputMode.Keyboard
    val screenReader = LocalScreenReader.current
    // Kept while the page shows in the list's place: the list comes back scrolled as it was.
    val listScroll = rememberScrollState()
    val rows = remember { mutableMapOf<String, FocusRequester>() }
    // The topic the player opened here, each time (its heading takes the focus, again if it's picked again beside the
    // list), and the one just closed (its row takes the focus back).
    var opened by remember { mutableStateOf<String?>(null) }
    var opens by remember { mutableIntStateOf(0) }
    var closed by remember { mutableStateOf<String?>(null) }
    val open = { id: String ->
        opened = id
        opens++
        onTopic(id)
    }
    val close = {
        closed = page?.id
        opened = null
        onTopic(null)
    }
    LaunchedEffect(focusTopic) {
        if (!focusTopic) return@LaunchedEffect
        if (page != null) {
            opened = page.id
            opens++
        }
        onTopicFocused()
    }
    BackHandler(enabled = page != null, onBack = close)
    KeyShortcuts { (it == Shortcut.Escape && page != null).also { escape -> if (escape) close() } }

    val value = calculateThreePaneScaffoldValue(
        directive.maxHorizontalPartitions,
        ListDetailPaneScaffoldDefaults.adaptStrategies(),
        ThreePaneScaffoldDestinationItem(
            if (page != null) ListDetailPaneScaffoldRole.Detail else ListDetailPaneScaffoldRole.List,
            page?.id,
        ),
    )
    ListDetailPaneScaffold(
        directive = directive,
        value = value,
        listPane = {
            val list = @Composable {
                HelpList(pages, beside = twoPanes, selected = page?.id, rows, listScroll, open, onShowWelcome)
                LaunchedEffect(closed) {
                    val id = closed ?: return@LaunchedEffect
                    if (keyboard || screenReader) {
                        delay(FOCUS_DELAY_MS)
                        runCatching { rows[id]?.requestFocus() }
                    }
                    closed = null
                }
            }
            val width = Modifier.preferredWidth(LIST_PANE_WIDTH)
            if (reduceMotion) {
                AnimatedPane(width, EnterTransition.None, ExitTransition.None, snap()) { list() }
            } else {
                AnimatedPane(width) { list() }
            }
        },
        detailPane = {
            val detail = @Composable {
                Row(Modifier.fillMaxSize()) {
                    // Beside the list, an edge between them (the two are the same colour).
                    val c = EpicTheme.colors
                    if (twoPanes) VerticalDivider(thickness = c.edgeWidth, color = c.outlineSubtle)
                    if (page != null) {
                        key(page.id) {
                            TopicPage(
                                page, audio,
                                focusKey = opens.takeIf { opened == page.id },
                                top = if (twoPanes) null else ({ AllTopicsButton(close) }),
                            )
                        }
                    } else {
                        NoTopic()
                    }
                }
            }
            if (reduceMotion) {
                AnimatedPane(Modifier, EnterTransition.None, ExitTransition.None, snap()) { detail() }
            } else {
                AnimatedPane { detail() }
            }
        },
        modifier = Modifier.fillMaxSize().background(EpicTheme.colors.background),
    )
}

/** The list's width beside a page on a wide window (Material's is 360 dp; the titles and lines wrap less at 400). */
private val LIST_PANE_WIDTH = 400.dp

/**
 * The list: the heading "Help", a line about Listen, a row per topic, then (in the tab, not the in-game sheet)
 * [onShowWelcome]'s row and Contact. A build with no help in it (placeholder content) has the website's instead.
 * [beside]: on a wide window, with the topic [selected] showing beside it; [rows] hold each row's focus, so a topic
 * closed gives its row the focus back.
 */
@Composable
private fun HelpList(
    pages: List<HelpPage>,
    beside: Boolean,
    selected: String?,
    rows: MutableMap<String, FocusRequester>,
    scroll: ScrollState,
    onTopic: (String) -> Unit,
    onShowWelcome: (() -> Unit)?,
    headingModifier: Modifier = Modifier,
    background: Color = EpicTheme.colors.background,
) {
    val c = EpicTheme.colors
    val context = LocalContext.current
    Column(
        Modifier
            .fillMaxSize()
            .background(background)
            .verticalScroll(scroll)
            .padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.readableWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ScreenHeader(stringResource(R.string.help_heading), headingModifier.testTag("help-heading"))
            if (pages.isEmpty()) {
                Text(stringResource(R.string.help_no_content), style = EpicTheme.type.body, color = c.text)
                LinkRow(stringResource(R.string.help_support), { Links.open(context, Links.SUPPORT) },
                    Modifier.testTag("help-support"))
            } else {
                Text(stringResource(R.string.help_list_intro), style = EpicTheme.type.body, color = c.text)
                Column {
                    for ((i, page) in pages.withIndex()) {
                        if (i > 0) HorizontalDivider(thickness = c.edgeWidth, color = c.outlineSubtle)
                        val shown = if (beside) page.id == selected else null
                        TopicRow(page, shown, rows.getOrPut(page.id) { FocusRequester() }) {
                            onTopic(page.id)
                        }
                    }
                }
            }
            if (onShowWelcome != null) {
                ShopDivider()
                PageRow(stringResource(R.string.show_welcome), onShowWelcome, Modifier.testTag("help-welcome"))
                SectionHeading(stringResource(R.string.help_contact), Modifier.padding(top = 8.dp))
                Text(stringResource(R.string.help_contact_intro), style = EpicTheme.type.body, color = c.text)
                LinkRow(stringResource(R.string.help_email, Links.EMAIL), { Links.email(context) },
                    Modifier.testTag("help-email"))
            }
        }
    }
}

/**
 * A topic in the list: its title and its line, the whole row a button, in line with the heading above (as Settings'
 * rows are). Beside its page on a wide window, the row showing is [selected] (TalkBack: "Selected"), with the accent
 * bar on its leading edge and an edge round it, so every row there is inset to make room; [selected] is null on a
 * phone, where nothing shows beside the list.
 */
@Composable
private fun TopicRow(page: HelpPage, selected: Boolean?, focus: FocusRequester, onClick: () -> Unit) {
    val c = EpicTheme.colors
    val shape = RoundedCornerShape(12.dp)
    val marked = selected == true
    val accent = c.accent
    // On a phone the row reaches past the list's edges by as much as its words are inset: they line up with the
    // heading, and the focus ring and the ripple have room round them.
    val inset = if (selected == null) ROW_OUTSET else 0.dp
    Row(
        Modifier
            .outset(inset)
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .testTag("help-topic-${page.id}")
            .focusRequester(focus)
            .focusRing(shape)
            .clip(shape)
            .then(
                if (marked) {
                    Modifier
                        .background(c.surface)
                        .border(c.edgeWidth * 2, c.outline, shape)
                        .drawBehind {
                            val width = 4.dp.toPx()
                            val x = if (layoutDirection == LayoutDirection.Rtl) size.width - width else 0f
                            drawRect(accent, topLeft = Offset(x, 0f), size = Size(width, size.height))
                        }
                } else {
                    Modifier
                },
            )
            .then(
                if (selected != null) {
                    Modifier.selectable(selected = marked, role = Role.Button, onClick = onClick)
                } else {
                    Modifier.clickable(role = Role.Button, onClick = onClick)
                },
            )
            .padding(start = if (selected != null) 16.dp else inset, top = 12.dp, end = 8.dp, bottom = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(page.title, style = EpicTheme.type.itemTitle, color = c.text)
            if (page.summary.isNotBlank()) Text(page.summary, style = EpicTheme.type.secondary, color = c.textMuted)
        }
        Spacer(Modifier.width(8.dp))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = c.text)
    }
}

/** How far a topic's row reaches past the list's edges on a phone (its words inset as much). */
private val ROW_OUTSET = 8.dp

/**
 * Wider than the room it's given by [by] on each side (drawn that far past it), and taking only that room in the
 * layout: for a row whose words keep in line with what's above it while its edges stand clear of them.
 */
private fun Modifier.outset(by: Dp): Modifier = if (by == 0.dp) this else layout { measurable, constraints ->
    val px = by.roundToPx()
    val wider = if (constraints.hasBoundedWidth) {
        constraints.copy(minWidth = constraints.minWidth + px * 2, maxWidth = constraints.maxWidth + px * 2)
    } else {
        constraints
    }
    val placeable = measurable.measure(wider)
    layout((placeable.width - px * 2).coerceAtLeast(0), placeable.height) { placeable.place(-px, 0) }
}

/** Beside the list on a wide window, before a topic is picked. */
@Composable
private fun NoTopic() {
    val c = EpicTheme.colors
    Box(Modifier.fillMaxSize().background(c.background).padding(24.dp), contentAlignment = Alignment.Center) {
        Text(stringResource(R.string.help_pick_topic), style = EpicTheme.type.body, color = c.text)
    }
}

/** Back from a topic to the list, as words: what it does, and what Voice Access hears. */
@Composable
private fun AllTopicsButton(onClick: () -> Unit) {
    EpicButton(stringResource(R.string.help_all_topics), onClick, Modifier.testTag("help-all-topics"),
        kind = ButtonKind.Text, icon = Icons.AutoMirrored.Filled.ArrowBack)
}

/**
 * A help topic's page: [top] (the way back to the list, on a phone), its heading (level 1; the focus moves to it a
 * moment after it shows, and again for a new [focusKey]; not at all with none), Listen, the paragraphs with the word
 * being read marked, and its links (a web page in the browser, an email in the mail app).
 */
@Composable
internal fun TopicPage(
    page: HelpPage,
    audio: PageAudio,
    modifier: Modifier = Modifier,
    focusKey: Any? = Unit,
    top: (@Composable () -> Unit)? = null,
    background: Color = EpicTheme.colors.background,
) {
    val c = EpicTheme.colors
    val context = LocalContext.current
    val scroll = rememberScrollState()
    val follow = remember { ReadingFollower() }
    Column(
        modifier
            .fillMaxSize()
            .background(background)
            .verticalScroll(scroll)
            .onGloballyPositioned { follow.content = it }
            .padding(start = 16.dp, top = 8.dp, end = 16.dp, bottom = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.readableWidth().testTag("help-page"), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            top?.invoke()
            ScreenHeader(
                page.title,
                Modifier
                    .padding(top = if (top == null) 8.dp else 0.dp)
                    .testTag("help-page-heading")
                    .focusOnAppear(focusKey, enabled = focusKey != null),
            )
            val clip = AppClip.Help(page.id)
            ListenButton(clip, audio, Modifier.testTag("help-listen"))
            PageParagraphs(page, reading = audio.clipPlaying == clip, highlight = audio.highlight, scroll, follow)
            for ((i, link) in page.links.withIndex()) {
                LinkRow(link.label, { Links.open(context, link.url) }, Modifier.testTag("help-link-$i"))
            }
        }
    }
}

/**
 * Listen: reads [clip] aloud, and while it's read (or about to be) it's Pause, which stops it, with the state
 * "Playing". With TalkBack on, the reading starts a moment after the tap ([LISTEN_DELAY_MS]), so TalkBack's own
 * feedback for the tap comes first, not over the voice. Not there at all when the build hasn't the clip.
 */
@Composable
internal fun ListenButton(clip: AppClip, audio: PageAudio, modifier: Modifier = Modifier) {
    if (!remember(clip) { audio.hasClip(clip) }) return
    val screenReader = LocalScreenReader.current
    val scope = rememberCoroutineScope()
    var waiting by remember { mutableStateOf<Job?>(null) }
    val reading = waiting != null || audio.clipPlaying == clip
    val playing = stringResource(R.string.playing)
    EpicButton(
        stringResource(if (reading) R.string.pause else R.string.listen),
        onClick = {
            if (reading) {
                waiting?.cancel()
                waiting = null
                if (audio.clipPlaying == clip) audio.stopClip()
            } else if (!screenReader) {
                audio.play(clip)
            } else {
                waiting = scope.launch {
                    delay(LISTEN_DELAY_MS)
                    waiting = null
                    audio.play(clip)
                }
            }
        },
        modifier.semantics { if (reading) stateDescription = playing },
        icon = if (reading) Icons.Default.Pause else Icons.Default.PlayArrow,
    )
}

/** With TalkBack on, Listen waits this long after its tap (docs/DESIGN.md › Help). */
const val LISTEN_DELAY_MS = 400L

/**
 * A page's paragraphs, the word the voice is on marked while it's [reading] ([highlight]; as the transcript marks it,
 * and not with Settings › Highlight words as they're spoken off). Without a screen reader, the paragraph being read is
 * kept in sight as the voice moves on to it (at once with Reduce Motion), so the words can be followed; with one,
 * nothing moves under the player's finger.
 */
@Composable
internal fun PageParagraphs(
    page: HelpPage,
    reading: Boolean,
    highlight: HelpHighlight?,
    scroll: ScrollState,
    follow: ReadingFollower,
) {
    val c = EpicTheme.colors
    val settings = LocalAppSettings.current
    val screenReader = LocalScreenReader.current
    val reduceMotion = LocalReduceMotion.current
    val marked = highlight?.takeIf { reading }
    for ((i, text) in page.text.withIndex()) {
        val said = marked?.takeIf { it.paragraph == i }?.chars
        Text(
            transcriptText(text, said, settings.highlightWords, wholeLine = true, c),
            Modifier.onGloballyPositioned { follow.paragraphs[i] = it },
            style = EpicTheme.type.body,
            color = c.text,
        )
    }
    val paragraph = marked?.paragraph
    LaunchedEffect(paragraph) {
        if (paragraph != null && !screenReader) follow.show(paragraph, scroll, instantly = reduceMotion)
    }
}

/**
 * Where a page's paragraphs are in its scrolling [content], so the one being read can be scrolled into sight
 * ([PageParagraphs]).
 */
internal class ReadingFollower {
    var content: LayoutCoordinates? = null
    val paragraphs = mutableMapOf<Int, LayoutCoordinates>()

    /** Scrolls [scroll] so [paragraph] is in sight, if it isn't: its top a little under the top of the view. */
    suspend fun show(paragraph: Int, scroll: ScrollState, instantly: Boolean) {
        val content = content?.takeIf { it.isAttached } ?: return
        val coords = paragraphs[paragraph]?.takeIf { it.isAttached } ?: return
        val top = content.localPositionOf(coords, Offset.Zero).y.toInt()
        val bottom = top + coords.size.height
        val seen = scroll.value..(scroll.value + scroll.viewportSize)
        if (top >= seen.first && bottom <= seen.last) return
        val target = (top - MARGIN_PX).coerceIn(0, scroll.maxValue)
        if (instantly) scroll.scrollTo(target) else scroll.animateScrollTo(target)
    }

    private companion object {
        /** Room left above a paragraph scrolled to (px: the margin needn't be exact). */
        const val MARGIN_PX = 48
    }
}

/**
 * Help in a game (docs/DESIGN.md › Help sheet): a topic's page, or the list of topics, in a sheet the full height of
 * the screen, over the game (which waits, paused). The page has All help topics, the list's rows open a topic, and Close
 * (or Back, a swipe down, Escape) closes it. A pane named by its heading, which takes the focus as it shows. [topic] is
 * the page showing (null: the list); [onTopic] changes it. iOS: HelpView.swift's HelpSheet.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HelpSheet(
    pages: List<HelpPage>,
    audio: PageAudio,
    topic: String?,
    onTopic: (String?) -> Unit,
    onClose: () -> Unit,
) {
    val c = EpicTheme.colors
    val page = topic?.let { id -> pages.firstOrNull { it.id == id } }
    val sheet = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val reduceMotion = LocalReduceMotion.current
    // Close slides the sheet away first (at once with Reduce Motion), as a swipe down does.
    val close: () -> Unit = {
        if (reduceMotion) {
            onClose()
        } else {
            scope.launch { sheet.hide() }.invokeOnCompletion { onClose() }
        }
    }
    // The list shown after a page: its heading takes the focus, as a page's does.
    var fromPage by remember { mutableStateOf(false) }
    val listScroll = rememberScrollState()
    val rows = remember { mutableMapOf<String, FocusRequester>() }
    val shape = BottomSheetDefaults.ExpandedShape
    // The screen's full height but the status bar (or the cut-out), and a little room under it, so it's seen to be a
    // sheet: Material's would otherwise reach the top of the screen, and its first row go under the status bar.
    val height = sheetMaxHeight()
    val pane = page?.title ?: stringResource(R.string.help_heading)
    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = sheet,
        // The pane's name, said as it opens and as it changes: what it shows.
        modifier = Modifier.semantics { paneTitle = pane },
        shape = shape,
        containerColor = c.surfaceRaised,
        contentColor = c.text,
        dragHandle = null,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .heightIn(max = height)
                .fillMaxHeight()
                .windowTestTags()
                .testTag("help-sheet")
                // Escape, from within the sheet: Android's own handling of it in a sheet's window varies by version.
                .onPreviewKeyEvent {
                    if (it.key != Key.Escape) return@onPreviewKeyEvent false
                    if (it.type == KeyEventType.KeyUp) close()
                    true
                }
                .sheetEdge(shape, c.edgeWidth, c.outlineSubtle),
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
            // Over the page or the list that scrolls under it, so Close stays whole for TalkBack. Close has its room
            // first: All help topics has what's left, and at the largest text wraps its words in it rather than
            // squeeze Close's.
            Row(
                Modifier.aboveScrollingContent().fillMaxWidth().padding(start = 8.dp, top = 8.dp, end = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                if (page != null) {
                    Box(Modifier.weight(1f, fill = false)) {
                        AllTopicsButton {
                            fromPage = true
                            onTopic(null)
                        }
                    }
                } else {
                    Spacer(Modifier)
                }
                EpicButton(stringResource(R.string.close), close, Modifier.padding(start = 8.dp).testTag("help-close"),
                    kind = ButtonKind.Secondary)
            }
            if (page != null) {
                key(page.id) { TopicPage(page, audio, Modifier.weight(1f), background = c.surfaceRaised) }
            } else {
                Box(Modifier.weight(1f)) {
                    HelpList(
                        pages, beside = false, selected = null, rows, listScroll, onTopic = { onTopic(it) },
                        onShowWelcome = null,
                        headingModifier = Modifier.focusOnAppear(fromPage, enabled = fromPage),
                        background = c.surfaceRaised,
                    )
                }
            }
        }
    }
}
