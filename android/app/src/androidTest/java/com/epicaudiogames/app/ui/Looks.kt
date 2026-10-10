package com.epicaudiogames.app.ui

import android.os.Build
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.Window
import android.view.inspector.WindowInspector
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.compose.ui.test.junit4.accessibility.enableAccessibilityChecks
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.tryPerformAccessibilityChecks
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import com.epicaudiogames.app.AppSettings
import com.epicaudiogames.app.MemoryPrefs
import com.epicaudiogames.app.ThemeChoice
import com.epicaudiogames.app.ui.theme.EpicTheme
import com.google.android.apps.common.testing.accessibility.framework.AccessibilityCheckResult.AccessibilityCheckResultType
import com.google.android.apps.common.testing.accessibility.framework.AccessibilityViewCheckResult
import com.google.android.apps.common.testing.accessibility.framework.AccessibilityCheckResultUtils.matchesCheck
import com.google.android.apps.common.testing.accessibility.framework.AccessibilityCheckResultUtils.matchesElements
import com.google.android.apps.common.testing.accessibility.framework.checks.TextContrastCheck
import com.google.android.apps.common.testing.accessibility.framework.checks.TouchTargetSizeCheck
import com.google.android.apps.common.testing.accessibility.framework.integrations.espresso.AccessibilityValidator
import com.google.android.apps.common.testing.accessibility.framework.uielement.ViewHierarchyElement
import org.hamcrest.CoreMatchers.allOf
import org.hamcrest.CoreMatchers.anyOf
import org.hamcrest.Description
import org.hamcrest.TypeSafeMatcher
import org.junit.rules.ExternalResource

// What every screen's test shows its screen in, and checks it with (docs/DESIGN.md › Colour, › Type, › Tablets…).

/**
 * The looks every screen is checked in: Light, Dark and High contrast (the palettes; Light + increased contrast is the
 * phone's setting, which ContrastTest covers), each at the phone's own text size and at twice it (Android's 200%, the
 * largest, where the compact layouts take over).
 */
enum class Look(val theme: ThemeChoice, val fontScale: Float) {
    LIGHT(ThemeChoice.LIGHT, 1f),
    DARK(ThemeChoice.DARK, 1f),
    CONTRAST(ThemeChoice.CONTRAST, 1f),
    LIGHT_200(ThemeChoice.LIGHT, 2f),
    DARK_200(ThemeChoice.DARK, 2f),
    CONTRAST_200(ThemeChoice.CONTRAST, 2f),
}

/**
 * A screen shown in each [Look] in turn, in [EpicTheme] with these [settings] (in memory, so the phone's aren't
 * touched): [show] it once (a test sets its content only once), then [each] look in turn redraws it.
 */
class Looks(private val compose: AndroidComposeTestRule<*, *>, val settings: AppSettings = AppSettings(MemoryPrefs())) {
    private var look by mutableStateOf(Look.LIGHT)

    /** The screen, in the look of the moment, TalkBack taken as on or off ([screenReader]). */
    fun show(screenReader: Boolean = false, content: @Composable () -> Unit) {
        settings.theme = look.theme
        compose.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(look.fontScale)) {
                EpicTheme(settings, screenReader) { content() }
            }
        }
        compose.waitForIdle()
    }

    /** [check], in each look in turn (the last one's left showing). */
    fun each(check: (Look) -> Unit) {
        for (l in Look.entries) {
            compose.runOnIdle {
                look = l
                settings.theme = l.theme
            }
            compose.waitForIdle()
            check(l)
        }
    }
}

/**
 * The accessibility checks (on, with [enableEpicChecks]) run on everything the screen has: each part that scrolls is
 * walked from its top to its end a screenful at a time, the checks run at each stop (they see only what's on screen); a
 * screen that doesn't scroll is checked as it is. [what] names the screen in a failure.
 */
fun AndroidComposeTestRule<*, *>.checkAll(what: String = "the screen") {
    waitForIdle()
    val scrolling = onAllNodes(hasScrollAction())
    val count = scrolling.fetchSemanticsNodes().size
    if (count == 0) {
        onAllNodes(isRoot()).onFirst().tryPerformAccessibilityChecks()
        return
    }
    for (i in 0 until count) walk(scrolling[i], what)
}

/**
 * Down [node] from its top to its end, the accessibility checks at each stop. Each scroll goes no further than there's
 * room for: what's left over of a longer one goes on to what holds the list, and a sheet would be dragged down by it,
 * part of it out of sight (where the checks see a button cut short). A lazy list's range is counted in items, not
 * pixels: it goes back to its first item, and its last step may go past its end (forward, a sheet is already open).
 */
private fun AndroidComposeTestRule<*, *>.walk(node: SemanticsNodeInteraction, what: String) {
    val config = { node.fetchSemanticsNode().config }
    val axis = { config().getOrNull(SemanticsProperties.VerticalScrollAxisRange) }
    val start = axis()
    if (start == null) {
        node.tryPerformAccessibilityChecks()
        return
    }
    val lazy = SemanticsActions.ScrollToIndex in config()
    if (lazy) {
        node.performScrollToIndex(0)
    } else if (start.value() > 0f) {
        node.performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, -start.value()) }
    }
    waitForIdle()
    repeat(MAX_STOPS) {
        node.tryPerformAccessibilityChecks()
        val range = axis() ?: return
        val left = range.maxValue() - range.value()
        if (left < 1f) return
        val screenful = node.fetchSemanticsNode().boundsInRoot.height * 0.8f
        val step = if (lazy) screenful else minOf(screenful, left)
        node.performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, step) }
        waitForIdle()
    }
    throw AssertionError("$what: still scrolling after $MAX_STOPS screenfuls")
}

private const val MAX_STOPS = 60

/**
 * The text's words are whole: each line it wraps onto ends where a word does (docs/DESIGN.md › Type: words wrap onto
 * more lines, never cut short; a word broken across lines is hard to read with low vision).
 */
fun SemanticsNodeInteraction.assertWordsWhole(): SemanticsNodeInteraction {
    val layouts = mutableListOf<TextLayoutResult>()
    performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
    val layout = layouts.single()
    val text = layout.layoutInput.text.text
    for (line in 0 until layout.lineCount - 1) {
        val end = layout.getLineEnd(line)
        if (end in 1 until text.length && !text[end - 1].isWhitespace() && text[end - 1] != '-' &&
            !text[end].isWhitespace()) {
            throw AssertionError("\"$text\" is broken mid-word: \"${text.substring(layout.getLineStart(line), end)}\"")
        }
    }
    return this
}

/**
 * The accessibility checks every screen's test runs: enableAccessibilityChecks's own (Android's Accessibility Test
 * Framework, over every window from its root), with screenshots, so the text's contrast is measured on what's drawn
 * (Compose's words aren't TextViews, whose colours it could read); and its warnings fail a test as its errors do, as
 * contrast measured on a screenshot is only ever a warning. Set aside: the contrast of words cut off by the edge of
 * what scrolls (only a sliver of them is in the screenshot, often with a divider's line; [checkAll] checks them whole at
 * its next stop), and, with a [sheet] open, Material's scrim ("Close sheet", a tap outside the sheet closes it), which
 * the checks see as only the strip over the navigation bar, 24 dp tall: that one result is Material's, not ours (the
 * sheet has its own Close button, and Back closes it too).
 */
fun AndroidComposeTestRule<*, *>.enableEpicChecks(sheet: Boolean = false) {
    val cutOff = allOf(matchesCheck(TextContrastCheck::class.java), againstScrollingEdge)
    val scrim = allOf(matchesCheck(TouchTargetSizeCheck::class.java), matchesElements(materialScrim))
    val validator = AccessibilityValidator()
        .setRunChecksFromRootView(true)
        .setCaptureScreenshots(true)
        .setThrowExceptionFor(AccessibilityCheckResultType.WARNING)
        .setSuppressingResultMatcher(if (sheet) anyOf(cutOff, scrim) else cutOff)
    enableAccessibilityChecks(validator)
}

/** A result for an element the checks say may be only partly in sight, at the edge of what scrolls. */
private val againstScrollingEdge = object : TypeSafeMatcher<AccessibilityViewCheckResult>() {
    override fun describeTo(description: Description) {
        description.appendText("an element at the edge of what scrolls")
    }

    override fun matchesSafely(result: AccessibilityViewCheckResult) =
        result.metadata?.getBoolean(TextContrastCheck.KEY_IS_AGAINST_SCROLLABLE_EDGE, false) == true
}

/** Material's scrim behind a sheet, as the accessibility checks see it. */
val materialScrim = object : TypeSafeMatcher<ViewHierarchyElement>() {
    override fun describeTo(description: Description) {
        description.appendText("Material's sheet scrim, \"Close sheet\"")
    }

    override fun matchesSafely(element: ViewHierarchyElement) = element.contentDescription?.toString() == "Close sheet"
}

/**
 * The phone's own text size at its largest, 200% (its settings' font size, `font_scale` 2.0), for every test of the
 * class it's the class rule of: what [Looks]' DeviceConfigurationOverride can't reach is at twice the size too, as a
 * sheet, a menu and a dialog are windows of their own, which take their text size from the phone's settings. Put back
 * as it was after the class (this size, found still set by a run stopped part-way through, goes back to 100%).
 */
class LargeText : ExternalResource() {
    private var was: String? = null

    override fun before() {
        val now = shell("settings get system font_scale").trim()
        was = now.takeIf { it.toFloatOrNull().let { s -> s != null && s != SCALE } }
        shell("settings put system font_scale $SCALE")
        // The phone's configuration changes for every app, before an activity starts in it.
        SystemClock.sleep(SETTLE_MS)
    }

    override fun after() {
        shell("settings put system font_scale ${was ?: "1.0"}")
        SystemClock.sleep(SETTLE_MS)
    }

    private companion object {
        const val SCALE = 2.0f
        const val SETTLE_MS = 2_500L
    }
}

/**
 * The bars' icons over [window] are the dark ones, as a light screen needs (the insets controller's "light"
 * appearance), for the status bar and the navigation bar both.
 */
fun lightBars(window: Window): Boolean = WindowCompat.getInsetsController(window, window.decorView)
    .let { it.isAppearanceLightStatusBars && it.isAppearanceLightNavigationBars }

/**
 * An open sheet's window (a dialog's), among the app's windows; null with none open. On the main thread. Android 10 and
 * later (WindowInspector): the tests that use it are skipped before (as lint asks of test code, @SdkSuppress).
 */
@SdkSuppress(minSdkVersion = Build.VERSION_CODES.Q)
fun sheetWindow(): Window? = WindowInspector.getGlobalWindowViews().firstNotNullOfOrNull { it.dialogWindow() }

private fun View.dialogWindow(): Window? {
    if (this is DialogWindowProvider) return window
    if (this is ViewGroup) for (i in 0 until childCount) getChildAt(i).dialogWindow()?.let { return it }
    return null
}

/** A shell command, as the test's instrumentation (adb's shell user), and what it printed. */
internal fun shell(command: String): String {
    val out = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
    return android.os.ParcelFileDescriptor.AutoCloseInputStream(out).use { it.readBytes().decodeToString() }
}

/**
 * The emulator's screen as a 10-inch tablet's turned sideways, 1280 x 800 dp (2560 x 1600 at 320 dpi): an expanded
 * window, for every test of the class it's the class rule of (docs/DESIGN.md › Tablets…: the rail, the Games grid, the
 * two-pane game and Help). A real window, not a forced size, so the layouts read their width class as on a tablet and
 * the touch targets are measured at the screen's own density. Put back as it was after the class: a size someone set
 * stays set, but this one, found still there (a run stopped part-way through a class, which never got to put it back),
 * goes, or every test after it would be a tablet's.
 */
class TabletScreen : ExternalResource() {
    private var size: String? = null
    private var density: String? = null

    override fun before() {
        size = override(shell("wm size"), "size")?.takeIf { it != SIZE }
        density = override(shell("wm density"), "density")?.takeIf { it != DENSITY }
        shell("wm size $SIZE")
        shell("wm density $DENSITY")
        // The screen and the system's bars settle at the new size before an activity starts in it.
        SystemClock.sleep(SETTLE_MS)
    }

    override fun after() {
        shell(size?.let { "wm size $it" } ?: "wm size reset")
        shell(density?.let { "wm density $it" } ?: "wm density reset")
        SystemClock.sleep(SETTLE_MS)
    }

    /** `wm size` / `wm density`'s "Override …: x" (a size someone set), or null for the screen's own. */
    private fun override(said: String, what: String) =
        Regex("Override $what: (\\S+)").find(said)?.groupValues?.get(1)

    private companion object {
        const val SIZE = "2560x1600"
        const val DENSITY = "320"
        const val SETTLE_MS = 2_500L
    }
}
