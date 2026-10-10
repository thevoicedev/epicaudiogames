package com.epicaudiogames.app.ui.theme

import androidx.compose.ui.graphics.Color
import com.epicaudiogames.app.ThemeChoice
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow

/**
 * docs/DESIGN.md › Colour, checked from the tokens themselves: every pair in its contrast table meets its minimum (7:1
 * for text, 3:1 for the rest) in every palette, at the ratio the table gives, and no colour is see-through (text never
 * takes an alpha). Material's own components are held to the same: their text on their containers is 7:1 too. The
 * contrast is WCAG 2.x's, from relative luminance. iOS: ThemeContrastTests.swift.
 */
class ContrastTest {
    private val palettes = listOf(
        "dark" to EpicColors.dark,
        "light" to EpicColors.light,
        "contrast" to EpicColors.contrast,
        "lightIncreased" to EpicColors.lightIncreased,
    )

    /** A pair from DESIGN.md's table: what's drawn on what, its minimum, and its ratio in each palette (in order). */
    private class ContrastPair(
        val name: String,
        val minimum: Double,
        val front: (EpicColors) -> Color,
        val back: (EpicColors) -> Color,
        vararg val ratios: Double,
    )

    private val pairs = listOf(
        ContrastPair("text / background", 7.0, { it.text }, { it.background }, 17.10, 16.65, 21.00, 21.00),
        ContrastPair("text / surface", 7.0, { it.text }, { it.surface }, 13.32, 18.15, 21.00, 21.00),
        ContrastPair("text / surfaceRaised", 7.0, { it.text }, { it.surfaceRaised }, 12.26, 18.15, 21.00, 21.00),
        ContrastPair("text / replySurface", 7.0, { it.text }, { it.replySurface }, 13.59, 16.31, 21.00, 18.87),
        ContrastPair("textMuted / background", 7.0, { it.textMuted }, { it.background }, 12.07, 8.64, 21.00, 21.00),
        ContrastPair("textMuted / surface", 7.0, { it.textMuted }, { it.surface }, 9.39, 9.42, 21.00, 21.00),
        ContrastPair("textMuted / surfaceRaised", 7.0, { it.textMuted }, { it.surfaceRaised }, 8.65, 9.42, 21.00, 21.00),
        ContrastPair("textMuted / replySurface", 7.0, { it.textMuted }, { it.replySurface }, 9.59, 8.47, 21.00, 18.87),
        ContrastPair("heading / background", 7.0, { it.heading }, { it.background }, 12.86, 12.96, 19.56, 18.15),
        ContrastPair("heading / surfaceRaised", 7.0, { it.heading }, { it.surfaceRaised }, 9.22, 14.13, 19.56, 18.15),
        ContrastPair("onPrimary / primary", 7.0, { it.onPrimary }, { it.primary }, 13.01, 14.13, 19.56, 18.15),
        ContrastPair("highlightText / highlightBg", 7.0, { it.highlightText }, { it.highlightBg }, 12.86, 14.13, 19.56, 18.15),
        ContrastPair("success / surface", 7.0, { it.success }, { it.surface }, 9.28, 8.08, 16.63, 9.96),
        ContrastPair("error / surface", 7.0, { it.error }, { it.surface }, 8.32, 7.75, 10.64, 10.01),
        ContrastPair("error / surfaceRaised", 7.0, { it.error }, { it.surfaceRaised }, 7.66, 7.75, 10.64, 10.01),
        ContrastPair("outline / background", 3.0, { it.outline }, { it.background }, 6.71, 4.12, 21.00, 21.00),
        ContrastPair("outline / surface", 3.0, { it.outline }, { it.surface }, 5.23, 4.49, 21.00, 21.00),
        ContrastPair("accent / surface", 3.0, { it.accent }, { it.surface }, 10.02, 5.54, 19.56, 18.15),
        ContrastPair("ringSpeaking / background", 3.0, { it.ringSpeaking }, { it.background }, 12.86, 5.08, 19.56, 18.15),
        ContrastPair("ringListening / background", 3.0, { it.ringListening }, { it.background }, 11.91, 7.41, 16.63, 9.96),
        ContrastPair("ringIdle / background", 3.0, { it.ringIdle }, { it.background }, 6.71, 4.12, 21.00, 21.00),
        ContrastPair("highlightBg / surface", 3.0, { it.highlightBg }, { it.surface }, 10.02, 14.13, 19.56, 18.15),
        ContrastPair("progressFill / progressTrack", 3.0, { it.progressFill }, { it.progressTrack }, 5.94, 9.10, 19.56, 18.15),
    )

    @Test
    fun everyPairMeetsItsMinimumInEveryPalette() {
        val failures = pairs.flatMap { pair ->
            palettes.mapNotNull { (name, colors) ->
                val ratio = contrast(pair.front(colors), pair.back(colors))
                "${pair.name} in $name: ${"%.2f".format(ratio)}, under ${pair.minimum}".takeIf { ratio < pair.minimum }
            }
        }
        assertTrue(failures.joinToString("\n"), failures.isEmpty())
    }

    @Test
    fun eachPairHasTheRatioDesignMdGives() {
        for (pair in pairs) {
            palettes.forEachIndexed { i, (name, colors) ->
                assertEquals("${pair.name} in $name", pair.ratios[i], contrast(pair.front(colors), pair.back(colors)), 0.005)
            }
        }
    }

    @Test
    fun noColourIsSeeThrough() {
        // Text above all: a fainter word is a harder one to read (the old "words still to come" were ink at 35%,
        // 1.96:1). The scrim is made from the background, not a token (theScrimHidesWhatsUnderIt).
        for ((name, c) in palettes) {
            val text = listOf(
                "text" to c.text, "textMuted" to c.textMuted, "heading" to c.heading, "onPrimary" to c.onPrimary,
                "highlightText" to c.highlightText, "success" to c.success, "error" to c.error, "primary" to c.primary,
            )
            val others = listOf(
                "background" to c.background, "surface" to c.surface, "surfaceRaised" to c.surfaceRaised,
                "replySurface" to c.replySurface, "accent" to c.accent, "outline" to c.outline,
                "outlineSubtle" to c.outlineSubtle, "ringSpeaking" to c.ringSpeaking, "ringListening" to c.ringListening,
                "ringIdle" to c.ringIdle, "highlightBg" to c.highlightBg, "focus" to c.focus,
                "progressFill" to c.progressFill, "progressTrack" to c.progressTrack, "replyEdge" to c.replyEdge,
            ) + listOfNotNull(c.progressEdge?.let { "progressEdge" to it })
            for ((token, colour) in text + others) assertEquals("$token in $name", 1f, colour.alpha)
        }
    }

    @Test
    fun theScrimHidesWhatsUnderIt() {
        // All of it, in every palette (docs/DESIGN.md › Colour): the Paused and loading screens are the background,
        // solid. Words showing through faintly behind the buttons are hard to read with low vision.
        for ((name, c) in palettes) {
            assertEquals("scrim's alpha in $name", 1f, c.scrim.alpha)
            assertEquals("scrim in $name", c.background, c.scrim)
        }
    }

    @Test
    fun materialsTextIsAsReadableAsTheAppsOwn() {
        // Dialogs (surfaceContainerHigh) and their buttons (primary), menus (surfaceContainer), sheets
        // (surfaceContainerLow), the text field (surfaceContainerHighest), the navigation bar's indicator
        // (secondaryContainer), snackbars (inverseSurface).
        for ((name, colors) in palettes) {
            val m = colors.toMaterial()
            val roles = listOf(
                "onBackground / background" to (m.onBackground to m.background),
                "onSurface / surface" to (m.onSurface to m.surface),
                "onSurfaceVariant / surface" to (m.onSurfaceVariant to m.surface),
                "onSurface / surfaceContainerHigh" to (m.onSurface to m.surfaceContainerHigh),
                "onSurfaceVariant / surfaceContainerHigh" to (m.onSurfaceVariant to m.surfaceContainerHigh),
                "primary / surfaceContainerHigh" to (m.primary to m.surfaceContainerHigh),
                "onSurface / surfaceContainer" to (m.onSurface to m.surfaceContainer),
                "primary / surfaceContainerLow" to (m.primary to m.surfaceContainerLow),
                "onSurface / surfaceContainerHighest" to (m.onSurface to m.surfaceContainerHighest),
                "onSurfaceVariant / surfaceContainerHighest" to (m.onSurfaceVariant to m.surfaceContainerHighest),
                "onPrimary / primary" to (m.onPrimary to m.primary),
                "onPrimaryContainer / primaryContainer" to (m.onPrimaryContainer to m.primaryContainer),
                "onSecondaryContainer / secondaryContainer" to (m.onSecondaryContainer to m.secondaryContainer),
                "onError / error" to (m.onError to m.error),
                "onErrorContainer / errorContainer" to (m.onErrorContainer to m.errorContainer),
                "inverseOnSurface / inverseSurface" to (m.inverseOnSurface to m.inverseSurface),
                "inversePrimary / inverseSurface" to (m.inversePrimary to m.inverseSurface),
            )
            for ((role, colours) in roles) {
                val ratio = contrast(colours.first, colours.second)
                assertTrue("$role in $name: ${"%.2f".format(ratio)}", ratio >= 7.0)
            }
            assertEquals("surfaceTint in $name", Color.Transparent, m.surfaceTint)
        }
    }

    @Test
    fun thePaletteFollowsTheThemeDarkModeAndContrast() {
        fun of(theme: ThemeChoice, dark: Boolean, more: Boolean) = EpicColors.of(theme, dark, more)
        // Match my phone: light or dark as the phone is, each with its stronger version when it asks for contrast.
        assertEquals(EpicColors.light, of(ThemeChoice.SYSTEM, dark = false, more = false))
        assertEquals(EpicColors.dark, of(ThemeChoice.SYSTEM, dark = true, more = false))
        assertEquals(EpicColors.lightIncreased, of(ThemeChoice.SYSTEM, dark = false, more = true))
        assertEquals(EpicColors.contrast, of(ThemeChoice.SYSTEM, dark = true, more = true))
        for (dark in listOf(false, true)) {
            assertEquals(EpicColors.light, of(ThemeChoice.LIGHT, dark, more = false))
            assertEquals(EpicColors.lightIncreased, of(ThemeChoice.LIGHT, dark, more = true))
            assertEquals(EpicColors.dark, of(ThemeChoice.DARK, dark, more = false))
            assertEquals(EpicColors.contrast, of(ThemeChoice.DARK, dark, more = true))
            for (more in listOf(false, true)) assertEquals(EpicColors.contrast, of(ThemeChoice.CONTRAST, dark, more))
        }
    }

    /** WCAG 2.x contrast ratio: (lighter + 0.05) / (darker + 0.05), from relative luminance. */
    private fun contrast(a: Color, b: Color): Double {
        val la = luminance(a)
        val lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private fun luminance(c: Color): Double {
        fun linear(channel: Float): Double {
            val s = channel.toDouble()
            return if (s <= 0.04045) s / 12.92 else ((s + 0.055) / 1.055).pow(2.4)
        }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }
}
