package com.epicaudiogames.wear

import androidx.annotation.DrawableRes
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.TransformingLazyColumn
import androidx.wear.compose.foundation.lazy.TransformingLazyColumnScope
import androidx.wear.compose.foundation.lazy.rememberTransformingLazyColumnState
import androidx.wear.compose.material3.AppScaffold
import androidx.wear.compose.material3.Button
import androidx.wear.compose.material3.ButtonDefaults
import androidx.wear.compose.material3.ColorScheme
import androidx.wear.compose.material3.Icon
import androidx.wear.compose.material3.MaterialTheme
import androidx.wear.compose.material3.OutlinedButton
import androidx.wear.compose.material3.ScreenScaffold
import androidx.wear.compose.material3.Text
import com.epicaudiogames.wearlink.WearAction
import com.epicaudiogames.wearlink.WearCommand
import com.epicaudiogames.wearlink.WearState

// The Wear OS app's one screen (docs/DESIGN.md › Watches): the game on the phone, its big button and Pause. The phone's
// own one button is the talking circle (android/app's ui/GameScreen.kt); iOS's watch screen is ios/EpicWatch's
// WatchView.swift.

/**
 * The game on the phone ([state], PhoneLink): its title, a heading; what it's doing, in words; the big button, named as
 * on the phone (the talking circle's CircleAction: "Skip", "Talk", "Stop listening", "Carry on"), which does what
 * tapping the picture does; and Pause, while there's something to pause. At an end, nothing to press: what's next is
 * chosen on the phone, and the watch says so. With no game open on the phone: "Open a game on your phone". A press that
 * couldn't reach the phone says so under it ([trouble]).
 *
 * Compose for Wear OS's type, so the text follows the watch's font size (it wraps, never cut short, and the list
 * scrolls, by touch or the crown); the phone's Dark colours ([WatchColors]); each state in words, the big button's in
 * an icon too, never by colour alone. TalkBack reads the title as a heading, the state, then the buttons; what's
 * happening isn't announced as it changes, as the phone is speaking the game and listening. In [ambient] mode (the
 * wrist down) the screen is black and nothing is filled: the big button is drawn outlined.
 */
@Composable
fun WatchScreen(state: WearState, trouble: Boolean, ambient: Boolean, onPress: (WearCommand) -> Unit) {
    val c = if (ambient) WatchColors.ambient else WatchColors.dark
    MaterialTheme(colorScheme = c.scheme()) {
        // The test tags (docs/WEAR_OS.md's identifiers) as resource ids, so UI Automator and the screenshot tools find
        // them, as the phone app's.
        AppScaffold(
            modifier = Modifier.semantics { testTagsAsResourceId = true },
            containerColor = c.background,
            contentColor = c.text,
        ) {
            val list = rememberTransformingLazyColumnState()
            ScreenScaffold(scrollState = list) { padding ->
                TransformingLazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    state = list,
                    contentPadding = padding,
                    verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterVertically),
                ) {
                    if (state.gameOpen) gameItems(state, c, ambient, onPress) else noGameItem(c)
                    if (trouble) troubleItem(c)
                }
            }
        }
    }
}

private fun TransformingLazyColumnScope.gameItems(
    state: WearState,
    c: WatchColors,
    ambient: Boolean,
    onPress: (WearCommand) -> Unit,
) {
    item {
        Text(
            state.title,
            Modifier.fillMaxWidth().semantics { heading() }.testTag("watch-title"),
            color = c.heading,
            textAlign = TextAlign.Center,
            maxLines = Int.MAX_VALUE,
            style = MaterialTheme.typography.titleLarge,
        )
    }
    item {
        Text(
            state.state,
            Modifier.fillMaxWidth().testTag("watch-state"),
            color = c.text,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            maxLines = Int.MAX_VALUE,
            style = MaterialTheme.typography.displaySmall,
        )
    }
    if (state.label.isEmpty()) {
        // At an end there's nothing to press here: the phone's end panel has Next chapter, Play again and Back to
        // games, as the line says.
        item {
            Text(
                stringResource(R.string.end_hint),
                Modifier.fillMaxWidth().testTag("watch-end-hint"),
                color = c.textMuted,
                textAlign = TextAlign.Center,
                maxLines = Int.MAX_VALUE,
                style = MaterialTheme.typography.bodyLarge,
            )
        }
    } else {
        item { BigButton(state, c, ambient) { onPress(WearCommand.PRIMARY) } }
    }
    // Paused, or at an end, there's nothing to pause: the big button carries on (or the phone's end panel has what's
    // next).
    if (state.canPause) {
        item {
            OutlinedButton(
                onClick = { onPress(WearCommand.PAUSE) },
                modifier = Modifier.fillMaxWidth().testTag("watch-pause"),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = c.text, iconColor = c.text),
                border = BorderStroke(EDGE, c.outline),
                icon = { Icon(painterResource(R.drawable.ic_pause), contentDescription = null) },
            ) {
                Text(
                    stringResource(R.string.pause),
                    maxLines = Int.MAX_VALUE,
                    style = MaterialTheme.typography.labelLarge,
                )
            }
        }
    }
}

/**
 * The big button, in the phone's colours (its primary button's): filled gold, its words dark. Dimmed when it can't do
 * anything: its words muted, no fill but the surface's, a faint edge (TalkBack says "disabled"). Ambient mode draws it
 * outlined, so the screen isn't left bright.
 */
@Composable
private fun BigButton(state: WearState, c: WatchColors, ambient: Boolean, onClick: () -> Unit) {
    val filled = state.enabled && !ambient
    Button(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth().heightIn(min = BIG_BUTTON_HEIGHT).testTag("watch-primary"),
        enabled = state.enabled,
        colors = ButtonDefaults.buttonColors(
            containerColor = if (filled) c.primary else c.background,
            contentColor = if (filled) c.onPrimary else c.text,
            disabledContainerColor = c.surface,
            disabledContentColor = c.textMuted,
        ),
        border = when {
            filled -> null
            state.enabled -> BorderStroke(EDGE, c.primary)
            else -> BorderStroke(EDGE, c.outlineSubtle)
        },
    ) {
        Column(
            Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            icon(state.action)?.let { Icon(painterResource(it), contentDescription = null, Modifier.size(28.dp)) }
            Text(
                state.label,
                textAlign = TextAlign.Center,
                maxLines = Int.MAX_VALUE,
                style = MaterialTheme.typography.labelLarge,
            )
        }
    }
}

private fun TransformingLazyColumnScope.noGameItem(c: WatchColors) {
    item {
        Column(
            Modifier.fillMaxWidth().padding(top = 8.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(painterResource(R.drawable.ic_phone), contentDescription = null, tint = c.heading)
            Text(
                stringResource(R.string.no_game),
                Modifier.fillMaxWidth().testTag("watch-no-game"),
                color = c.text,
                textAlign = TextAlign.Center,
                maxLines = Int.MAX_VALUE,
                style = MaterialTheme.typography.titleLarge,
            )
        }
    }
}

/**
 * A press that couldn't reach the phone: in words, with an icon (the watch buzzed a failure as it happened). TalkBack
 * says it as it appears: the press it answers did nothing on the phone.
 */
private fun TransformingLazyColumnScope.troubleItem(c: WatchColors) {
    item {
        Row(
            Modifier
                .fillMaxWidth()
                .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite }
                .testTag("watch-trouble"),
            horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
            verticalAlignment = Alignment.Top,
        ) {
            Icon(painterResource(R.drawable.ic_warning), contentDescription = null, tint = c.error)
            Text(
                stringResource(R.string.unreachable),
                color = c.error,
                maxLines = Int.MAX_VALUE,
                style = MaterialTheme.typography.bodyLarge,
            )
        }
    }
}

/**
 * The big button's icon, what a press does, as the phone's talking circle and notification have theirs: play to carry
 * on, skip, stop, the mic to talk, the mic struck through when it can't open, an hourglass while there's nothing to do
 * yet.
 */
@DrawableRes
fun icon(action: WearAction?): Int? = when (action) {
    WearAction.CARRY_ON -> R.drawable.ic_play
    WearAction.SKIP -> R.drawable.ic_skip
    WearAction.STOP_LISTENING -> R.drawable.ic_stop
    WearAction.TALK -> R.drawable.ic_mic
    WearAction.MIC_REFUSED, WearAction.NO_RECOGNITION -> R.drawable.ic_mic_off
    WearAction.WAIT -> R.drawable.ic_hourglass
    null -> null
}

/** The buttons' edges, as the phone's (2 dp). */
private val EDGE = 2.dp

/** The big button's least height: as big as a watch allows, under the title and the state. */
private val BIG_BUTTON_HEIGHT = 80.dp

/**
 * The colours the watch uses, by their names in the phone's palettes (android/app's ui/theme/Tokens.kt; docs/DESIGN.md
 * › Colour): Dark's, as iOS's watch has them (WatchView.swift's WatchColors), and the same on black in ambient mode.
 * Every text colour is at least 7:1 on what it's drawn on (WatchColorsTest).
 */
@Immutable
data class WatchColors(
    val background: Color,
    val surface: Color,
    val text: Color,
    val textMuted: Color,
    val heading: Color,
    val primary: Color,
    val onPrimary: Color,
    val outline: Color,
    val outlineSubtle: Color,
    val error: Color,
) {
    /** Compose for Wear OS's colours, for what it draws itself: the time at the top, the scroll indicator. */
    fun scheme() = ColorScheme(
        primary = primary,
        onPrimary = onPrimary,
        surfaceContainer = surface,
        onSurface = text,
        onSurfaceVariant = textMuted,
        outline = outline,
        outlineVariant = outlineSubtle,
        background = background,
        onBackground = text,
        error = error,
    )

    companion object {
        /** The phone's Dark palette. */
        val dark = WatchColors(
            background = Color(0xFF0B1430),
            surface = Color(0xFF16275E),
            text = Color(0xFFF6F8FF),
            textMuted = Color(0xFFC9D2F0),
            heading = Color(0xFFFFD54F),
            primary = Color(0xFFFFD54F),
            onPrimary = Color(0xFF1A1400),
            outline = Color(0xFF8E9CCB),
            outlineSubtle = Color(0xFF2C3D7A),
            error = Color(0xFFFFB4AB),
        )

        /** Ambient mode (the wrist down): the same words on black, as an always-on screen should be. */
        val ambient = dark.copy(background = Color.Black, surface = Color.Black)
    }
}
