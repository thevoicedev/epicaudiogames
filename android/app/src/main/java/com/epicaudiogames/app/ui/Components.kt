package com.epicaudiogames.app.ui

import androidx.compose.foundation.BorderStroke
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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.currentWindowSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.window.core.layout.WindowWidthSizeClass
import com.epicaudiogames.app.R
import com.epicaudiogames.app.Words
import com.epicaudiogames.app.rememberWords
import com.epicaudiogames.app.ui.theme.EpicTheme
import kotlinx.coroutines.delay
import kotlin.math.abs

// The app's building blocks, on the theme's tokens (docs/DESIGN.md; iOS's UI/Design/Components.swift has the same
// ones): headings, buttons, settings rows and status text. Everything that can be touched is at least 48 dp, shows a
// 3 dp focus ring when a keyboard moves to it, and says in words what its colour shows.

/** The widest the content gets on a big screen (600 dp and wider), centred, so lines stay a readable length. */
val MAX_CONTENT_WIDTH = 640.dp

/** As wide as there's room for, up to [MAX_CONTENT_WIDTH]: in a centred column, the content of a big screen. */
fun Modifier.readableWidth(): Modifier = widthIn(max = MAX_CONTENT_WIDTH).fillMaxWidth()

/**
 * What stays put just above content that scrolls (a sheet's Close, onboarding's Skip, the game's header and circle),
 * put over that content, for TalkBack too. Compose keeps a button scrolled almost out of sight touchable as 48 dp,
 * reaching up to 24 dp past the edge of what scrolls; drawn under it, the button just above would lose that much of
 * itself to TalkBack (touch exploration there finds the one out of sight, and the accessibility checks see a 24 dp
 * button). Drawing and TalkBack's reading order don't change: nothing overlaps, and it reads top to bottom.
 */
fun Modifier.aboveScrollingContent(): Modifier = zIndex(1f)

/**
 * How wide the window is (docs/DESIGN.md › Tablets…): compact under 600 dp (a phone), medium to 839 (a small tablet, a
 * foldable open, a phone's window in split screen), expanded from 840 (a tablet in landscape, a Chromebook). The
 * window's, not the screen's, so split screen and freeform windows get the layout that fits them. iOS: the
 * horizontal size class and the window's width.
 */
enum class WidthClass { COMPACT, MEDIUM, EXPANDED }

@Composable
fun windowWidthClass(): WidthClass = when (currentWindowAdaptiveInfo().windowSizeClass.windowWidthSizeClass) {
    WindowWidthSizeClass.EXPANDED -> WidthClass.EXPANDED
    WindowWidthSizeClass.MEDIUM -> WidthClass.MEDIUM
    else -> WidthClass.COMPACT
}

/**
 * The game in two panes, its transcript beside the rest (docs/DESIGN.md › The game on wide windows): an expanded window,
 * or a medium one in landscape. A phone (compact) has the one column.
 */
@Composable
fun gameHasTwoPanes(): Boolean {
    val size = currentWindowSize()
    return twoPanes(windowWidthClass(), landscape = size.width > size.height)
}

/** [gameHasTwoPanes], from the window's width class and shape. */
fun twoPanes(width: WidthClass, landscape: Boolean): Boolean =
    width == WidthClass.EXPANDED || (width == WidthClass.MEDIUM && landscape)

/**
 * A popup, a dialog or a sheet is a window of its own, which doesn't take the test tags as resource ids from the app's
 * (MainActivity's Screens): its content says so again, so UI tests and the screenshot scripts find them.
 */
fun Modifier.windowTestTags(): Modifier = semantics { testTagsAsResourceId = true }

/** A screen's title: the level-1 heading ("Games", "Shop"). */
@Composable
fun ScreenHeader(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        modifier.semantics { heading() },
        style = EpicTheme.type.title,
        color = EpicTheme.colors.heading,
    )
}

/** A section's title: a level-2 heading (a game in the Shop, a group of settings). */
@Composable
fun SectionHeading(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        modifier.semantics { heading() },
        style = EpicTheme.type.headline,
        color = EpicTheme.colors.heading,
    )
}

/** What a button is for: the one thing to do (filled), another choice (outlined), or a quiet one (words only). */
enum class ButtonKind { Primary, Secondary, Text }

/**
 * A button: its words (sentence case, wrapping onto more lines rather than cut short), after an [icon] if it has one.
 * [description] is what a screen reader says when it needs more than the words, and it starts with them, so Voice
 * Access still finds the button by what it shows ("Buy for £1.99: The Werewolf, 45 more mysteries"). [busy] shows a
 * spinner in the icon's place; the button still works.
 *
 * With a [description], the words on the button aren't read as well: Compose gives TalkBack a merged button's
 * description and its text both (the description first), so they'd be heard twice ("Get Stories 2 to 5 for The
 * Kingdom of Frootopia, Get Stories 2 to 5"). The spinner is only a picture: the description says the price is loading.
 */
@Composable
fun EpicButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: ButtonKind = ButtonKind.Primary,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    description: String? = null,
    busy: Boolean = false,
) {
    val c = EpicTheme.colors
    val shape = RoundedCornerShape(14.dp)
    val filled = kind == ButtonKind.Primary
    val content = when {
        !enabled -> c.textMuted
        kind == ButtonKind.Primary -> c.onPrimary
        kind == ButtonKind.Secondary -> c.text
        else -> c.heading
    }
    // Disabled, a button keeps its words at full strength (text never fades): it loses its fill instead.
    val colors = ButtonDefaults.buttonColors(
        containerColor = if (filled) c.primary else Color.Transparent,
        contentColor = content,
        disabledContainerColor = Color.Transparent,
        disabledContentColor = content,
    )
    val border = when {
        kind == ButtonKind.Secondary || (filled && !enabled) -> BorderStroke(2.dp, c.outline)
        else -> null
    }
    Button(
        onClick = onClick,
        modifier = modifier
            .heightIn(min = 48.dp)
            .focusRing(shape)
            .then(if (description != null) Modifier.semantics { contentDescription = description } else Modifier),
        enabled = enabled,
        shape = shape,
        colors = colors,
        border = border,
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 12.dp),
    ) {
        if (busy) {
            CircularProgressIndicator(Modifier.size(22.dp).clearAndSetSemantics {}, color = content, strokeWidth = 2.5.dp)
            Spacer(Modifier.width(10.dp))
        } else if (icon != null) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(24.dp))
            Spacer(Modifier.width(8.dp))
        }
        // Centred on each line, when it wraps (large text).
        Text(
            text,
            if (description != null) Modifier.clearAndSetSemantics {} else Modifier,
            style = EpicTheme.type.label,
            textAlign = TextAlign.Center,
        )
    }
}

/** A button that's only an icon (Back, ⋮, Send): 48 dp, named by [description]. */
@Composable
fun IconActionButton(
    icon: ImageVector,
    description: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    tint: Color = EpicTheme.colors.text,
) {
    IconButton(
        onClick = onClick,
        modifier = modifier.size(48.dp).focusRing(CircleShape),
        enabled = enabled,
        colors = IconButtonDefaults.iconButtonColors(contentColor = tint, disabledContentColor = EpicTheme.colors.textMuted),
    ) {
        Icon(icon, contentDescription = description)
    }
}

/**
 * A setting that's on or off: the whole row is the switch (TalkBack: "Listening sounds, switch, on"), with a [hint]
 * under its title. Disabled, it says why in the hint ("On in your phone's settings").
 */
@Composable
fun SwitchRow(
    title: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    hint: String? = null,
    enabled: Boolean = true,
) {
    val c = EpicTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .focusRing()
            .toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onChange)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = EpicTheme.type.body, color = if (enabled) c.text else c.textMuted)
            if (hint != null) Text(hint, style = EpicTheme.type.secondary, color = c.textMuted)
        }
        Spacer(Modifier.width(16.dp))
        Switch(
            checked = checked,
            onCheckedChange = null,
            enabled = enabled,
            colors = SwitchDefaults.colors(
                checkedThumbColor = c.onPrimary,
                checkedTrackColor = c.primary,
                checkedBorderColor = c.primary,
                uncheckedThumbColor = c.outline,
                uncheckedTrackColor = c.surface,
                uncheckedBorderColor = c.outline,
                disabledCheckedThumbColor = c.surface,
                disabledCheckedTrackColor = c.textMuted,
                disabledCheckedBorderColor = c.textMuted,
                disabledUncheckedThumbColor = c.textMuted,
                disabledUncheckedTrackColor = c.surface,
                disabledUncheckedBorderColor = c.textMuted,
            ),
        )
    }
}

/**
 * One of a few choices (a theme, a text size): radio buttons, a whole row each, in a group TalkBack counts ("Dark,
 * radio button, 3 of 4, selected"). [hint] adds a line under a choice, [decoration] a picture after it (a theme's
 * swatch; TalkBack doesn't read it), and [tag] its test tag.
 */
@Composable
fun <T> ChoiceGroup(
    choices: List<T>,
    selected: T,
    onSelect: (T) -> Unit,
    label: (T) -> String,
    modifier: Modifier = Modifier,
    hint: (T) -> String? = { null },
    enabled: Boolean = true,
    tag: (T) -> String? = { null },
    decoration: (@Composable (T) -> Unit)? = null,
) {
    val c = EpicTheme.colors
    Column(modifier.selectableGroup()) {
        for (choice in choices) {
            val on = choice == selected
            Row(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .then(tag(choice)?.let { Modifier.testTag(it) } ?: Modifier)
                    .focusRing()
                    .selectable(selected = on, enabled = enabled, role = Role.RadioButton) { onSelect(choice) }
                    .padding(vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(
                    selected = on,
                    onClick = null,
                    enabled = enabled,
                    colors = RadioButtonDefaults.colors(
                        selectedColor = c.primary,
                        unselectedColor = c.outline,
                        disabledSelectedColor = c.textMuted,
                        disabledUnselectedColor = c.textMuted,
                    ),
                )
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(label(choice), style = EpicTheme.type.body, color = if (enabled) c.text else c.textMuted)
                    hint(choice)?.let { Text(it, style = EpicTheme.type.secondary, color = c.textMuted) }
                }
                if (decoration != null) {
                    Spacer(Modifier.width(12.dp))
                    decoration(choice)
                }
            }
        }
    }
}

/**
 * A value moved a step at a time (the voice speed): Slower, the value in words ([describe]; by default the voice
 * speed's), Faster. Each button stops at its end; the value is a polite live region, so TalkBack says the new one after
 * a tap. While every value's longest word fits between the buttons they're on one row; with less room (large text)
 * the value has a line of its own, and the buttons share the row under it, so no word is ever broken.
 */
@Composable
fun SpeedStepper(
    value: Float,
    steps: List<Float>,
    onChange: (Float) -> Unit,
    modifier: Modifier = Modifier,
    describe: ((Float) -> String)? = null,
) {
    val i = steps.indexOfFirst { abs(it - value) < 0.001f }.coerceAtLeast(0)
    val label = EpicTheme.type.label
    val measurer = rememberTextMeasurer()
    val words = rememberWords()
    val say = describe ?: { speed: Float -> words.speedWords(speed) }
    val slowerText = stringResource(R.string.speed_slower)
    val fasterText = stringResource(R.string.speed_faster)
    val slower = @Composable { m: Modifier ->
        EpicButton(slowerText, { onChange(steps[i - 1]) }, m, kind = ButtonKind.Secondary, enabled = i > 0)
    }
    val faster = @Composable { m: Modifier ->
        EpicButton(fasterText, { onChange(steps[i + 1]) }, m, kind = ButtonKind.Secondary, enabled = i < steps.lastIndex)
    }
    val shown = @Composable { m: Modifier ->
        Text(
            say(value),
            m.semantics { liveRegion = LiveRegionMode.Polite },
            style = label,
            color = EpicTheme.colors.text,
            textAlign = TextAlign.Center,
        )
    }
    BoxWithConstraints(modifier.fillMaxWidth()) {
        val width = { text: String -> measurer.measure(text, label).size.width }
        val oneRow = with(LocalDensity.current) {
            // A secondary button is its words, 20 dp each side and its 2 dp edge; 12 dp between the three.
            val buttons = width(slowerText) + width(fasterText) + (44.dp * 2 + 24.dp).roundToPx()
            val longestWord = steps.flatMap { say(it).split(' ') }.maxOf(width)
            buttons + longestWord <= constraints.maxWidth
        }
        if (oneRow) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                slower(Modifier)
                shown(Modifier.weight(1f))
                faster(Modifier)
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                shown(Modifier.fillMaxWidth())
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    slower(Modifier.weight(1f))
                    faster(Modifier.weight(1f))
                }
            }
        }
    }
}

/**
 * Buttons sharing a row, each an equal part of it and as tall as the tallest, while each one's longest word fits in
 * its part (their words wrap onto more lines rather than shrink); with less room (large text, a long label), one under
 * another, each the whole width, so no word is ever broken. Read in the same order either way.
 */
@Composable
fun SharedRow(modifier: Modifier = Modifier, gap: Dp = 8.dp, content: @Composable () -> Unit) {
    Layout(content, modifier) { measurables, constraints ->
        val space = gap.roundToPx()
        val width = if (constraints.hasBoundedWidth) {
            constraints.maxWidth
        } else {
            measurables.maxOf { it.maxIntrinsicWidth(Constraints.Infinity) }
        }
        val part = (width - space * (measurables.size - 1)) / measurables.size
        if (measurables.all { it.minIntrinsicWidth(Constraints.Infinity) <= part }) {
            val height = measurables.maxOf { it.maxIntrinsicHeight(part) }
            val placeables = measurables.map { it.measure(Constraints(part, part, height, height)) }
            layout(width, height) {
                placeables.forEachIndexed { i, p -> p.placeRelative(i * (part + space), 0) }
            }
        } else {
            val placeables = measurables.map { it.measure(Constraints(minWidth = width, maxWidth = width)) }
            layout(width, placeables.sumOf { it.height } + space * (placeables.size - 1)) {
                var y = 0
                for (p in placeables) {
                    p.placeRelative(0, y)
                    y += p.height + space
                }
            }
        }
    }
}

/** A voice speed in words: "Normal speed", "1.25 times". */
fun Words.speedWords(speed: Float): String = if (abs(speed - 1f) < 0.001f) {
    text(R.string.speed_normal)
} else {
    text(R.string.speed_times, speed.toString().removeSuffix(".0"))
}

/** What a status message is about: its colour, always with an icon and words too. */
enum class StatusKind { Info, Success, Error }

/**
 * A status message (a purchase done, a download failed, restored): shown, and said by TalkBack as it appears or
 * changes (a polite live region; Android 16 deprecates announceForAccessibility). Never while the mic listens: these
 * come from the store, which pauses the game.
 */
@Composable
fun StatusText(text: String, modifier: Modifier = Modifier, kind: StatusKind = StatusKind.Info) {
    val c = EpicTheme.colors
    val (color, icon) = when (kind) {
        StatusKind.Info -> c.text to null
        StatusKind.Success -> c.success to Icons.Filled.CheckCircle
        StatusKind.Error -> c.error to Icons.Outlined.ErrorOutline
    }
    Row(modifier.semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = color, modifier = Modifier.padding(top = 1.dp).size(24.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(text, style = EpicTheme.type.body, color = color)
    }
}

/** A web page to open in the browser (the privacy policy): underlined, as links always are, with an "opens" icon. */
@Composable
fun LinkRow(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val c = EpicTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .focusRing()
            .clickable(role = Role.Button, onClick = onClick)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text,
            Modifier.weight(1f),
            style = EpicTheme.type.body.copy(textDecoration = TextDecoration.Underline),
            color = c.heading,
        )
        Spacer(Modifier.width(8.dp))
        Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = null, tint = c.heading)
    }
}

/**
 * A page of the app to go to (Settings › Licences, How to play): a whole-row button, its words in the body style and
 * a chevron, so it doesn't look like a web link (those are underlined, LinkRow).
 */
@Composable
fun PageRow(text: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val c = EpicTheme.colors
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .focusRing()
            .clickable(role = Role.Button, onClick = onClick)
            .padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text, Modifier.weight(1f), style = EpicTheme.type.body, color = c.text)
        Spacer(Modifier.width(8.dp))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = c.text)
    }
}

/** A small label with an icon ("In progress"): words, so it isn't colour alone. */
@Composable
fun Badge(text: String, icon: ImageVector?, modifier: Modifier = Modifier) {
    val c = EpicTheme.colors
    Row(
        modifier
            .background(c.primary, RoundedCornerShape(8.dp))
            .padding(horizontal = 10.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = c.onPrimary, modifier = Modifier.size(20.dp))
            Spacer(Modifier.width(6.dp))
        }
        Text(text, style = EpicTheme.type.speaker, color = c.onPrimary)
    }
}

/**
 * The 3 dp focus ring (the theme's focus colour), drawn while what follows it in the chain has the keyboard's focus
 * (a keyboard, a D-pad: Compose's keyboard input mode). Focus moved there for TalkBack, which draws its own, doesn't
 * show it; nor does touch, which doesn't move the focus.
 */
fun Modifier.focusRing(shape: Shape = RoundedCornerShape(12.dp), width: Dp = 3.dp): Modifier = composed {
    var focused by remember { mutableStateOf(false) }
    val color = EpicTheme.colors.focus
    val keyboard = LocalInputModeManager.current.inputMode == InputMode.Keyboard
    onFocusChanged { focused = it.isFocused }
        .then(if (focused && keyboard) Modifier.border(width, color, shape) else Modifier)
}

/**
 * Takes the focus, and TalkBack's with it, a moment ([FOCUS_DELAY_MS]) after it appears, and again for a new [key]:
 * the end panel's and the pause's headings, a sheet's heading (docs/DESIGN.md › Everywhere › Focus). By then the pane
 * has been laid out and announced. Makes what it's on [focusable], with the focus ring a keyboard sees there, so put
 * it on a heading merged into one element; on a button, which has its own focus (and ring), say not. Only while
 * [enabled] (as it appears).
 */
fun Modifier.focusOnAppear(key: Any? = Unit, focusable: Boolean = true, enabled: Boolean = true): Modifier = composed {
    val requester = remember { FocusRequester() }
    LaunchedEffect(key) {
        if (!enabled) return@LaunchedEffect
        delay(FOCUS_DELAY_MS)
        // A requester that isn't on anything throws: then there's nothing to move the focus to.
        runCatching { requester.requestFocus() }
    }
    focusRequester(requester).then(if (focusable) Modifier.focusRing(RoundedCornerShape(8.dp)).focusable() else Modifier)
}

/** How long after a pane (the end panel, the pause) appears the focus moves to its heading. */
const val FOCUS_DELAY_MS = 300L
