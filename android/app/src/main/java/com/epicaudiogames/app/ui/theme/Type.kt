package com.epicaudiogames.app.ui.theme

import androidx.compose.material3.Typography
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import com.epicaudiogames.app.FontChoice
import com.epicaudiogames.app.R

/**
 * Atkinson Hyperlegible Next (Braille Institute, SIL Open Font License 1.1): letters made to be told apart, for low
 * vision. The static Regular, Bold and ExtraBold files, unmodified (their licence is content/app/licences/); iOS
 * bundles the same three (ios/scripts/bundle_content.sh).
 *
 * Bold Text (Android 12+, Configuration.fontWeightAdjustment) needs nothing here: Compose's font resolver adds the
 * phone's adjustment (300) to every weight it's asked for, so Regular (400 + 300) draws Bold, and Bold (700 + 300,
 * held at 900) draws ExtraBold, the heaviest face there is: docs/DESIGN.md's mapping, which iOS's Typography.swift
 * makes by hand from legibilityWeight. Adding it here as well would add it twice.
 */
val AtkinsonHyperlegibleNext = FontFamily(
    Font(R.font.atkinson_hyperlegible_next_regular, FontWeight.Normal),
    Font(R.font.atkinson_hyperlegible_next_bold, FontWeight.Bold),
    Font(R.font.atkinson_hyperlegible_next_extrabold, FontWeight.ExtraBold),
)

/** Settings › Appearance › Font: Atkinson Hyperlegible, or the phone's own font (Roboto) at the same sizes. */
fun fontFamily(choice: FontChoice): FontFamily = when (choice) {
    FontChoice.ATKINSON -> AtkinsonHyperlegibleNext
    FontChoice.SYSTEM -> FontFamily.Default
}

/**
 * The type styles (docs/DESIGN.md › Type; iOS's Typography.swift has the same names). Sizes are in sp, so the phone's
 * font size applies on top (Android 14's non-linear scaling included), and line heights in em, so they grow with the
 * text. Nothing is under 16 sp but the tab labels; there are no maxLines anywhere but the one-line answer field.
 */
@Immutable
data class EpicType(
    /** The intro's wordmark. */
    val display: TextStyle,
    /** Tab headings, onboarding and help topic headings. */
    val title: TextStyle,
    /** Section headings, the end and pause headings, sheet titles. */
    val headline: TextStyle,
    /** Game and pack titles, help list items, the game's header. */
    val itemTitle: TextStyle,
    /** Transcript lines and replies. */
    val transcript: TextStyle,
    /** Paragraphs. */
    val body: TextStyle,
    /** Buttons, chips, the status line. */
    val label: TextStyle,
    /** Speaker names, "You", badges. */
    val speaker: TextStyle,
    /** Download sizes, notes, setting hints. */
    val secondary: TextStyle,
    /** The navigation bar's labels (iOS uses the system's tab bar). */
    val tab: TextStyle,
) {
    /**
     * The same styles for Material's own components (dialogs, menus, sheets, the text field), so they're in the same
     * font and never under 16 sp either; the navigation bar's labels (labelMedium) are the one exception, at 14.
     */
    fun toMaterial() = Typography(
        displayLarge = display,
        displayMedium = display,
        displaySmall = display,
        headlineLarge = title,
        headlineMedium = title,
        headlineSmall = headline,
        titleLarge = headline,
        titleMedium = itemTitle,
        titleSmall = label,
        bodyLarge = body,
        bodyMedium = body,
        bodySmall = secondary,
        labelLarge = label,
        labelMedium = tab,
        labelSmall = speaker,
    )
}

/**
 * The type styles in [family], at [scale] times their size: Settings › Appearance › Text size (Standard 1, Large
 * 1.15, Larger 1.3), on top of the phone's own font size.
 */
fun epicType(family: FontFamily, scale: Float = 1f): EpicType {
    fun style(size: Int, weight: FontWeight, lineHeight: Double) =
        TextStyle(fontFamily = family, fontWeight = weight, fontSize = (size * scale).sp, lineHeight = lineHeight.em)
    return EpicType(
        display = style(34, FontWeight.ExtraBold, 1.2),
        title = style(30, FontWeight.Bold, 1.25),
        headline = style(22, FontWeight.Bold, 1.3),
        itemTitle = style(20, FontWeight.Bold, 1.3),
        transcript = style(20, FontWeight.Normal, 1.5),
        body = style(18, FontWeight.Normal, 1.45),
        label = style(18, FontWeight.Bold, 1.25),
        speaker = style(16, FontWeight.Bold, 1.3),
        secondary = style(16, FontWeight.Normal, 1.4),
        tab = style(14, FontWeight.Bold, 1.2),
    )
}

/** The type styles in use, provided by EpicTheme. */
val LocalEpicType = staticCompositionLocalOf { epicType(AtkinsonHyperlegibleNext) }

/**
 * The phone's text is at an accessibility size (font scale 1.6 or more; iOS: dynamicTypeSize.isAccessibilitySize):
 * game covers are hidden and the game takes its compact layout (docs/DESIGN.md › Type), so the words have the room.
 */
@Composable
@ReadOnlyComposable
fun isAccessibilityTextSize(): Boolean = LocalDensity.current.fontScale >= ACCESSIBILITY_FONT_SCALE

/** The font scale from which the text counts as accessibility sized (Android's 160%). */
const val ACCESSIBILITY_FONT_SCALE = 1.6f
