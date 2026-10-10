package com.epicaudiogames.app

import android.content.Intent
import android.os.Build
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.AndroidComposeTestRule
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import com.epicaudiogames.app.ui.lightBars
import com.epicaudiogames.app.ui.sheetWindow
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The bars' icons follow the app's palette (docs/DESIGN.md › Everywhere), not the theme's attributes nor the phone's
 * dark mode: over Light they're dark once the system's splash has gone (taking it away puts the theme's own light ones
 * back, and MainActivity sets the app's again), and over the store sheet, a window of its own. The app as it's
 * launched, Light its theme (DebugLaunch's EpicTheme, stored as if picked in Settings): the player's own is put back
 * after.
 */
@RunWith(AndroidJUnit4::class)
@SdkSuppress(minSdkVersion = Build.VERSION_CODES.Q)
class BarIconsTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    /** The player's theme, read before the launch stores Light. */
    private val theme = AppSettings(SharedPrefs(context)).theme
    private val launch = Intent(context, MainActivity::class.java)
        .putExtra("EpicNoIntro", true)
        .putExtra("EpicSkipOnboarding", true)
        .putExtra("EpicAnalytics", "off")
        .putExtra("EpicMic", "off")
        .putExtra("EpicTheme", "light")
        .putExtra("EpicStore", "frootopia")

    @get:Rule
    val compose = AndroidComposeTestRule(ActivityScenarioRule<MainActivity>(launch)) { rule ->
        var activity: MainActivity? = null
        rule.scenario.onActivity { activity = it }
        checkNotNull(activity)
    }

    @After
    fun tearDown() {
        AppSettings(SharedPrefs(context)).theme = theme
    }

    @Test
    fun overLightTheyreDarkAfterTheSplashAndOverTheStoreSheet() {
        compose.waitUntil(LAUNCH_MS) { compose.onAllNodes(hasTestTag("store-sheet")).fetchSemanticsNodes().isNotEmpty() }
        // The splash goes as the app's first frame shows, before the sheet opens: time for it to have gone.
        Thread.sleep(SPLASH_MS)
        compose.runOnIdle {
            assertTrue("the app's window", lightBars(compose.activity.window))
            assertTrue("the store sheet's window", sheetWindow()?.let(::lightBars) == true)
        }
    }

    private companion object {
        const val LAUNCH_MS = 30_000L
        const val SPLASH_MS = 2_000L
    }
}
