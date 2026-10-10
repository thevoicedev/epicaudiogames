package com.epicaudiogames.app.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.testTag
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.epicaudiogames.app.R
import com.epicaudiogames.app.ui.theme.EpicColors
import com.epicaudiogames.app.ui.theme.EpicTheme
import com.epicaudiogames.app.ui.theme.LocalReduceMotion
import com.epicaudiogames.app.ui.theme.setBarIcons

/**
 * The intro (docs/DESIGN.md › Intro): it takes over from the system's splash (Theme.EpicAudioGames.Starting, navy with
 * the emblem) with the emblem in exactly the same place and size, then the circle round it and the "Epic Audio Games"
 * wordmark fade in (at once with Reduce Motion). Navy in every theme, with light bar icons over it while it shows.
 * The sting is the model's (AppModel.startIntro: it starts as this appears, or a moment later with TalkBack on).
 *
 * The whole screen is one element for TalkBack, "Epic Audio Games", whose action is "Skip intro" ([onSkip]); a tap
 * anywhere, Escape and Space skip it too. iOS: IntroView.swift.
 */
@Composable
fun IntroScreen(onSkip: () -> Unit) {
    val c = EpicColors.dark
    val reduceMotion = LocalReduceMotion.current
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val fade by animateFloatAsState(
        if (shown) 1f else 0f,
        if (reduceMotion) snap() else tween(IntroTimes.FADE_IN),
        label = "intro",
    )
    // The bars' icons light over the navy; the theme's again as the intro goes (EpicTheme sets them as it changes).
    val view = LocalView.current
    val themeDark by rememberUpdatedState(EpicTheme.colors.isDark)
    SideEffect { setBarIcons(view, dark = true) }
    DisposableEffect(view) { onDispose { setBarIcons(view, themeDark) } }
    KeyShortcuts { shortcut ->
        (shortcut == Shortcut.Escape || shortcut == Shortcut.OneButton).also { skip -> if (skip) onSkip() }
    }
    val insets = WindowInsets.safeDrawing
    val name = stringResource(R.string.app_name)
    val skip = stringResource(R.string.intro_skip)
    Layout(
        content = {
            // The circle, the size of the one the splash shows its icon in (docs/STORE_ART.md: 192 dp).
            Box(
                Modifier
                    .size(CIRCLE)
                    .graphicsLayer { alpha = fade }
                    .background(c.surface, CircleShape),
            )
            // The splash's own icon (splash_emblem, a 288 dp canvas), drawn at its size: the emblem stays put.
            Image(painterResource(R.drawable.splash_emblem), contentDescription = null, Modifier.size(SPLASH_ICON))
            Text(
                name,
                Modifier.graphicsLayer { alpha = fade },
                style = EpicTheme.type.display,
                color = c.text,
                textAlign = TextAlign.Center,
            )
        },
        modifier = Modifier
            .fillMaxSize()
            .background(c.background)
            .pointerInput(Unit) { detectTapGestures { onSkip() } }
            .clearAndSetSemantics {
                testTag = "intro"
                contentDescription = name
                onClick(label = skip) {
                    onSkip()
                    true
                }
            },
    ) { measurables, constraints ->
        val width = constraints.maxWidth
        val height = constraints.maxHeight
        val loose = Constraints(maxWidth = width, maxHeight = height)
        val circle = measurables[0].measure(loose)
        val emblem = measurables[1].measure(loose)
        val side = SIDE.roundToPx()
        val wordmark = measurables[2].measure(Constraints(maxWidth = (width - side * 2).coerceAtLeast(0)))
        val gap = GAP.roundToPx()
        val bottom = height - insets.getBottom(this)
        layout(width, height) {
            // The emblem in the middle of the window, where the splash had it (both are drawn under the system's
            // bars). Without room for the wordmark under the circle (a short window, very large text), all three move
            // up as far as they need, the circle's top at most to the window's.
            val middle = height / 2
            val overflow = middle + circle.height / 2 + gap + wordmark.height - bottom
            val up = overflow.coerceIn(0, (middle - circle.height / 2).coerceAtLeast(0))
            circle.place((width - circle.width) / 2, middle - circle.height / 2 - up)
            emblem.place((width - emblem.width) / 2, middle - emblem.height / 2 - up)
            wordmark.place((width - wordmark.width) / 2, middle + circle.height / 2 + gap - up)
        }
    }
}

/** The splash's icon: the canvas of splash_emblem.png, as Android 12+ draws it (and core-splashscreen before 12). */
private val SPLASH_ICON = 288.dp

/** The circle the splash shows its icon in, the emblem 128 dp across inside it. */
private val CIRCLE = 192.dp

private val GAP = 24.dp
private val SIDE = 24.dp
