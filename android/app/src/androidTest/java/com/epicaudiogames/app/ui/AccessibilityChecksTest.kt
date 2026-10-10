package com.epicaudiogames.app.ui

import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.tryPerformAccessibilityChecks
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The accessibility checks every screen's test runs ([enableEpicChecks], Looks.kt) do catch what they're there for, on
 * Compose's own elements: a button with nothing for TalkBack to say, and words too faint to read (measured on what's
 * drawn). So a screen's test passing means they looked, and found nothing. (A clickable element is safe from the touch
 * target check: Compose reports it at least 48 dp, as it takes touches over that much.)
 */
@RunWith(AndroidJUnit4::class)
class AccessibilityChecksTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    @Before
    fun setUp() = compose.enableEpicChecks()

    @Test
    fun aButtonWithNoNameFails() {
        compose.setContent {
            Box(Modifier.background(Color.White).padding(40.dp)) {
                Box(Modifier.size(64.dp).background(Color.Black).clickable {}.testTag("nameless"))
            }
        }
        assertFails { compose.onNodeWithTag("nameless").tryPerformAccessibilityChecks() }
    }

    @Test
    fun wordsTooFaintToReadFail() {
        compose.setContent {
            Column(Modifier.background(Color.White).padding(40.dp)) {
                Text("Hardly there", Modifier.testTag("faint").padding(16.dp), color = Color(0xFFDDDDDD), fontSize = 18.sp)
            }
        }
        assertFails { compose.onNodeWithTag("faint").tryPerformAccessibilityChecks() }
    }

    private fun assertFails(action: () -> Unit) {
        val failed = runCatching(action).exceptionOrNull()
        assertTrue("the checks found nothing wrong ($failed)", failed != null && "ccessibility" in failed.toString())
    }
}
