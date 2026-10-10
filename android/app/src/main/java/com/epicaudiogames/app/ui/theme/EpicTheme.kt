package com.epicaudiogames.app.ui.theme

import android.app.UiModeManager
import android.content.Context
import android.database.ContentObserver
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.View
import android.view.ViewParent
import android.view.Window
import android.view.accessibility.AccessibilityManager
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import com.epicaudiogames.app.AppSettings
import com.epicaudiogames.app.MemoryPrefs
import com.epicaudiogames.app.R
import com.epicaudiogames.app.findActivity

/**
 * The app's look, from the player's settings and the phone's (docs/DESIGN.md › Everywhere; iOS's EpicTheme.swift):
 * the palette (Settings › Theme, the phone's dark mode, and on Android 14+ its contrast setting, or on 16+ its
 * high-contrast text), the type (Settings › Font and Text size; Bold Text is Compose's own, see Type.kt), the status
 * and navigation bars' icons, and Reduce Motion. Material's components take their colours and type from the same
 * tokens, so dialogs, menus and sheets meet the same contrast as everything else.
 *
 * Also provides the [settings] ([LocalAppSettings]) and whether a [screenReader] is on ([LocalScreenReader]) to
 * whatever needs them. Without [settings] (a test, a preview), the defaults.
 */
@Composable
fun EpicTheme(
    settings: AppSettings = remember { AppSettings(MemoryPrefs()) },
    screenReader: Boolean = false,
    content: @Composable () -> Unit,
) {
    val colors = EpicColors.of(settings.theme, isSystemInDarkTheme(), rememberMoreContrast())
    val font = settings.font
    val scale = settings.textScale
    val type = remember(font, scale) { epicType(fontFamily(font), scale) }
    val reduceMotion = rememberAnimationsOff() || settings.reduceMotion
    BarIcons(dark = colors.isDark)
    CompositionLocalProvider(
        LocalEpicColors provides colors,
        LocalEpicType provides type,
        LocalReduceMotion provides reduceMotion,
        LocalAppSettings provides settings,
        LocalScreenReader provides screenReader,
    ) {
        MaterialTheme(
            colorScheme = remember(colors) { colors.toMaterial() },
            typography = remember(type) { type.toMaterial() },
        ) {
            // Text and icons outside Material's surfaces (most of the app's) are the palette's text colour.
            CompositionLocalProvider(LocalContentColor provides colors.text, content = content)
        }
    }
}

/** The theme's tokens where a composable draws: `EpicTheme.colors.text`, `EpicTheme.type.body`. */
object EpicTheme {
    val colors: EpicColors
        @Composable @ReadOnlyComposable get() = LocalEpicColors.current
    val type: EpicType
        @Composable @ReadOnlyComposable get() = LocalEpicType.current
}

/**
 * Motion is reduced: the phone's animations are off (Settings › Accessibility › Remove animations) or the app's own
 * Settings › Reduce motion is on. The talking circle doesn't pulse, the mic's ring holds still, the transcript jumps
 * rather than scrolls.
 */
val LocalReduceMotion = staticCompositionLocalOf { false }

/** The player's settings (the transcript's highlight and speaker names read them as they draw). */
val LocalAppSettings = staticCompositionLocalOf<AppSettings> { error("No settings: the screen isn't in EpicTheme") }

/** A screen reader (TalkBack) is on, as it changes (ScreenReader.kt); a plain Boolean, so tests can set it. */
val LocalScreenReader = staticCompositionLocalOf { false }

/**
 * Every Material 3 colour role from the palette, so a Material component never brings a colour of its own (its
 * dialogs' buttons were 3.25:1 on their own defaults): containers are surfaces, content is text, and accents are the
 * primary colour. No tint over raised surfaces: they're exactly the palette's.
 */
internal fun EpicColors.toMaterial(): ColorScheme = lightColorScheme(
    primary = primary,
    onPrimary = onPrimary,
    primaryContainer = primary,
    onPrimaryContainer = onPrimary,
    inversePrimary = background,
    secondary = primary,
    onSecondary = onPrimary,
    secondaryContainer = primary,
    onSecondaryContainer = onPrimary,
    tertiary = primary,
    onTertiary = onPrimary,
    tertiaryContainer = primary,
    onTertiaryContainer = onPrimary,
    background = background,
    onBackground = text,
    surface = surface,
    onSurface = text,
    surfaceVariant = surface,
    onSurfaceVariant = textMuted,
    surfaceTint = Color.Transparent,
    inverseSurface = text,
    inverseOnSurface = background,
    error = error,
    onError = surface,
    errorContainer = surface,
    onErrorContainer = error,
    outline = outline,
    outlineVariant = outlineSubtle,
    scrim = background,
    surfaceBright = surfaceRaised,
    surfaceContainer = surfaceRaised,
    surfaceContainerHigh = surfaceRaised,
    surfaceContainerHighest = surface,
    surfaceContainerLow = surfaceRaised,
    surfaceContainerLowest = surface,
    surfaceDim = surface,
)

/**
 * The status and navigation bars' icons, dark on a light palette and light on a dark one (MainActivity's
 * enableEdgeToEdge only knows the phone's dark mode, not the app's theme). Set again whenever the palette changes.
 */
@Composable
private fun BarIcons(dark: Boolean) {
    val view = LocalView.current
    if (view.isInEditMode) return
    SideEffect { setBarIcons(view, dark) }
}

/**
 * The status and navigation bars' icons over [view]'s window: light on a [dark] screen, dark on a light one. EpicTheme
 * sets them for the palette; the intro, navy in every theme, sets them for itself while it shows. What's set is kept
 * on the window, for [restoreBarIcons].
 */
internal fun setBarIcons(view: View, dark: Boolean) {
    val window = view.context.findActivity()?.window ?: return
    window.decorView.setTag(R.id.bar_icons_dark, dark)
    WindowCompat.getInsetsController(window, view).run {
        isAppearanceLightStatusBars = !dark
        isAppearanceLightNavigationBars = !dark
    }
}

/**
 * The bars' icons over a sheet (the store sheet, the help sheet): a sheet is a window of its own, and Material gives it
 * the icons for the phone's dark mode, not the app's theme, so over Light with the phone dark they'd be white on white
 * (and dark on navy the other way round). The palette's, as [BarIcons] sets them for the app's window: call it in the
 * sheet's content.
 */
@Composable
fun SheetBarIcons() {
    val view = LocalView.current
    val dark = EpicTheme.colors.isDark
    SideEffect {
        val window = view.dialogWindow() ?: return@SideEffect
        WindowCompat.getInsetsController(window, window.decorView).run {
            isAppearanceLightStatusBars = !dark
            isAppearanceLightNavigationBars = !dark
        }
    }
}

/** The window of the dialog (a sheet's) that [this] view is in, or null. */
private fun View.dialogWindow(): Window? {
    var at: ViewParent? = if (this is ViewParent) this else parent
    while (at != null) {
        if (at is DialogWindowProvider) return at.window
        at = at.parent
    }
    return null
}

/**
 * The bars' icons as the app last set them over [window] ([setBarIcons]), set again: the system's splash, as it goes
 * (MainActivity), puts the theme's own back (core-splashscreen does, on Android 12 and later), which are light, and a
 * light palette's screen would have white icons on white.
 */
fun restoreBarIcons(window: Window) {
    val dark = window.decorView.getTag(R.id.bar_icons_dark) as? Boolean ?: return
    WindowCompat.getInsetsController(window, window.decorView).run {
        isAppearanceLightStatusBars = !dark
        isAppearanceLightNavigationBars = !dark
    }
}

/**
 * The phone asks for more contrast, as it changes: Android 14+'s contrast setting at "Medium" or "High"
 * (UiModeManager.getContrast() 0.5 or more), or Android 16+'s high-contrast text. Neither changes the configuration,
 * so each is followed with its listener. Before Android 14 there's no such setting: the player picks High contrast.
 */
@Composable
private fun rememberMoreContrast(): Boolean {
    val context = LocalContext.current
    var more by remember { mutableStateOf(moreContrast(context)) }
    DisposableEffect(context) {
        val stops = mutableListOf<() -> Unit>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val uiMode = context.getSystemService(UiModeManager::class.java)
            val listener = UiModeManager.ContrastChangeListener { more = moreContrast(context) }
            uiMode?.addContrastChangeListener(context.mainExecutor, listener)
            stops += { uiMode?.removeContrastChangeListener(listener) }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA) {
            val accessibility = context.getSystemService(AccessibilityManager::class.java)
            val listener = AccessibilityManager.HighContrastTextStateChangeListener { more = moreContrast(context) }
            accessibility?.addHighContrastTextStateChangeListener(context.mainExecutor, listener)
            stops += { accessibility?.removeHighContrastTextStateChangeListener(listener) }
        }
        // It may have changed while nothing was listening (the app in the background, with the theme not drawn).
        more = moreContrast(context)
        onDispose { stops.forEach { it() } }
    }
    return more
}

private fun moreContrast(context: Context): Boolean {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.BAKLAVA &&
        context.getSystemService(AccessibilityManager::class.java)?.isHighContrastTextEnabled == true
    ) return true
    return Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE &&
        (context.getSystemService(UiModeManager::class.java)?.contrast ?: 0f) >= MORE_CONTRAST
}

/** UiModeManager.getContrast() runs from -1 to 1: 0 is the standard, 0.5 Medium and 1 High. */
private const val MORE_CONTRAST = 0.5f

/**
 * The phone's animations are off (Remove animations, or the animator duration scale at 0), as it changes. It's the
 * scale ValueAnimator.areAnimatorsEnabled() follows, read from the setting itself so a change is seen at once.
 * Settings › Reduce motion shows it (on, and not to be turned off there).
 */
@Composable
internal fun rememberAnimationsOff(): Boolean {
    val context = LocalContext.current
    var off by remember { mutableStateOf(animationsOff(context)) }
    DisposableEffect(context) {
        val resolver = context.contentResolver
        val observer = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                off = animationsOff(context)
            }
        }
        resolver.registerContentObserver(Settings.Global.getUriFor(Settings.Global.ANIMATOR_DURATION_SCALE), false, observer)
        off = animationsOff(context)
        onDispose { resolver.unregisterContentObserver(observer) }
    }
    return off
}

private fun animationsOff(context: Context): Boolean =
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
