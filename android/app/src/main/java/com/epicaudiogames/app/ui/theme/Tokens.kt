package com.epicaudiogames.app.ui.theme

import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.epicaudiogames.app.ThemeChoice

/**
 * The app's colours by what they're for (docs/DESIGN.md › Colour; the same names as iOS's UI/Design/Tokens.swift),
 * in four palettes: [dark], [light], [contrast] (black, white and yellow) and [lightIncreased] (Light when the phone
 * asks for more contrast). Every text colour is at least 7:1 on the backgrounds it's used on, everything else that
 * means something at least 3:1 (ContrastTest checks each pair). Text never takes an alpha: a fainter word is a
 * harder one to read.
 */
@Immutable
data class EpicColors(
    /** Dark palettes have light status and navigation bar icons. */
    val isDark: Boolean,
    /** Screens. */
    val background: Color,
    /** Cards, transcript bubbles, chips, the text field. */
    val surface: Color,
    /** Headers, the tab bar, sheets, the end panel. */
    val surfaceRaised: Color,
    /** The player's own replies ("You said"). */
    val replySurface: Color,
    /** All body text. */
    val text: Color,
    /** Secondary text and placeholders: still 7:1, never pale. */
    val textMuted: Color,
    /** Headings, and links (always underlined). */
    val heading: Color,
    /** Primary buttons, the mic, the tab indicator; [onPrimary] is what's on them. */
    val primary: Color,
    val onPrimary: Color,
    /** The current line's bar and the speaking ring: never text. */
    val accent: Color,
    /** 2 dp borders: chips, the text field, secondary buttons. */
    val outline: Color,
    /** Decorative edges: bubbles, cards, dividers ([edgeWidth] wide). */
    val outlineSubtle: Color,
    /** "Installed", "Microphone allowed": always with an icon. */
    val success: Color,
    /** Failures: always with an icon and words. */
    val error: Color,
    /** The talking circle's ring, by state (each also has its own icon and ring style). */
    val ringSpeaking: Color,
    val ringListening: Color,
    val ringIdle: Color,
    /** The word being spoken, in inverse colours. */
    val highlightBg: Color,
    val highlightText: Color,
    /** The 3 dp keyboard focus ring. */
    val focus: Color,
    /** The download bar, 8 dp tall. */
    val progressFill: Color,
    val progressTrack: Color,
    /** The download bar's border, where its track is the same as the background (the contrast palettes). */
    val progressEdge: Color?,
    /** The reply bubble's edge: High contrast gives it a 2 dp yellow border, as its fill is black. */
    val replyEdge: Color,
    /** How wide decorative edges are: 2 dp in the contrast palettes, where they're all that separates a bubble. */
    val edgeWidth: Dp,
    /**
     * How much of what's under it the Paused and loading scrim hides: all of it, in every palette (iOS's
     * scrimOpacity). Words showing through faintly behind the buttons are hard to read with low vision.
     */
    val scrimAlpha: Float,
) {
    /** The Paused and loading overlay: the background, solid. */
    val scrim: Color get() = background.copy(alpha = scrimAlpha)

    companion object {
        val dark = EpicColors(
            isDark = true,
            background = Color(0xFF0B1430),
            surface = Color(0xFF16275E),
            surfaceRaised = Color(0xFF1B2D66),
            replySurface = Color(0xFF2E2A12),
            text = Color(0xFFF6F8FF),
            textMuted = Color(0xFFC9D2F0),
            heading = Color(0xFFFFD54F),
            primary = Color(0xFFFFD54F),
            onPrimary = Color(0xFF1A1400),
            accent = Color(0xFFFFD54F),
            outline = Color(0xFF8E9CCB),
            outlineSubtle = Color(0xFF2C3D7A),
            success = Color(0xFF8FE3B0),
            error = Color(0xFFFFB4AB),
            ringSpeaking = Color(0xFFFFD54F),
            ringListening = Color(0xFF8FE3B0),
            ringIdle = Color(0xFF8E9CCB),
            highlightBg = Color(0xFFFFD54F),
            highlightText = Color(0xFF0B1430),
            focus = Color(0xFFFFD54F),
            progressFill = Color(0xFFFFD54F),
            progressTrack = Color(0xFF3A4A86),
            progressEdge = null,
            replyEdge = Color(0xFF2C3D7A),
            edgeWidth = 1.dp,
            scrimAlpha = 1f,
        )

        val light = EpicColors(
            isDark = false,
            background = Color(0xFFF3F5FB),
            surface = Color(0xFFFFFFFF),
            surfaceRaised = Color(0xFFFFFFFF),
            replySurface = Color(0xFFFFF3C4),
            text = Color(0xFF0B1430),
            textMuted = Color(0xFF3B4566),
            heading = Color(0xFF16275E),
            primary = Color(0xFF16275E),
            onPrimary = Color(0xFFFFFFFF),
            accent = Color(0xFF8A6100),
            outline = Color(0xFF6B7699),
            outlineSubtle = Color(0xFFD5DAEA),
            success = Color(0xFF0F5C33),
            error = Color(0xFFA4161A),
            ringSpeaking = Color(0xFF8A6100),
            ringListening = Color(0xFF0F5C33),
            ringIdle = Color(0xFF6B7699),
            highlightBg = Color(0xFF16275E),
            highlightText = Color(0xFFFFFFFF),
            focus = Color(0xFF16275E),
            progressFill = Color(0xFF16275E),
            progressTrack = Color(0xFFC9CFE3),
            progressEdge = null,
            replyEdge = Color(0xFFD5DAEA),
            edgeWidth = 1.dp,
            scrimAlpha = 1f,
        )

        /** High contrast: black, white and yellow, whatever the phone's dark mode. */
        val contrast = EpicColors(
            isDark = true,
            background = Color(0xFF000000),
            surface = Color(0xFF000000),
            surfaceRaised = Color(0xFF000000),
            replySurface = Color(0xFF000000),
            text = Color(0xFFFFFFFF),
            textMuted = Color(0xFFFFFFFF),
            heading = Color(0xFFFFFF00),
            primary = Color(0xFFFFFF00),
            onPrimary = Color(0xFF000000),
            accent = Color(0xFFFFFF00),
            outline = Color(0xFFFFFFFF),
            outlineSubtle = Color(0xFFFFFFFF),
            success = Color(0xFF7CFF9B),
            error = Color(0xFFFF9E9E),
            ringSpeaking = Color(0xFFFFFF00),
            ringListening = Color(0xFF7CFF9B),
            ringIdle = Color(0xFFFFFFFF),
            highlightBg = Color(0xFFFFFF00),
            highlightText = Color(0xFF000000),
            focus = Color(0xFFFFFF00),
            progressFill = Color(0xFFFFFF00),
            progressTrack = Color(0xFF000000),
            progressEdge = Color(0xFFFFFFFF),
            replyEdge = Color(0xFFFFFF00),
            edgeWidth = 2.dp,
            scrimAlpha = 1f,
        )

        /** Light when the phone asks for more contrast: pure white, black text, navy for what was gold. */
        val lightIncreased = EpicColors(
            isDark = false,
            background = Color(0xFFFFFFFF),
            surface = Color(0xFFFFFFFF),
            surfaceRaised = Color(0xFFFFFFFF),
            replySurface = Color(0xFFFFF3C4),
            text = Color(0xFF000000),
            textMuted = Color(0xFF000000),
            heading = Color(0xFF0B1430),
            primary = Color(0xFF0B1430),
            onPrimary = Color(0xFFFFFFFF),
            accent = Color(0xFF0B1430),
            outline = Color(0xFF000000),
            outlineSubtle = Color(0xFF000000),
            success = Color(0xFF0B4D2A),
            error = Color(0xFF8B0000),
            ringSpeaking = Color(0xFF0B1430),
            ringListening = Color(0xFF0B4D2A),
            ringIdle = Color(0xFF000000),
            highlightBg = Color(0xFF0B1430),
            highlightText = Color(0xFFFFFFFF),
            focus = Color(0xFF000000),
            progressFill = Color(0xFF0B1430),
            progressTrack = Color(0xFFFFFFFF),
            progressEdge = Color(0xFF000000),
            replyEdge = Color(0xFF000000),
            edgeWidth = 2.dp,
            scrimAlpha = 1f,
        )

        /**
         * The palette for Settings › Theme, the phone's dark mode and whether the phone asks for more contrast
         * (docs/DESIGN.md › Colour): Light becomes [lightIncreased] and Dark becomes [contrast] then. Match my phone
         * follows dark mode.
         */
        fun of(theme: ThemeChoice, systemDark: Boolean, moreContrast: Boolean): EpicColors {
            val wantsDark = when (theme) {
                ThemeChoice.SYSTEM -> systemDark
                ThemeChoice.LIGHT -> false
                ThemeChoice.DARK -> true
                ThemeChoice.CONTRAST -> return contrast
            }
            return when {
                wantsDark && moreContrast -> contrast
                wantsDark -> dark
                moreContrast -> lightIncreased
                else -> light
            }
        }
    }
}

/** The palette in use, provided by EpicTheme. */
val LocalEpicColors = staticCompositionLocalOf { EpicColors.dark }
