package com.epicaudiogames.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Whether the game opens the mic by itself: each "Open the microphone by itself" setting, with TalkBack on and off. */
class MicPolicyTest {
    @Test
    fun byDefaultItListensByItselfOnlyWithoutAScreenReader() {
        assertTrue(listensByItself(MicAuto.NOT_WITH_SCREEN_READER, screenReaderOn = false))
        assertFalse(listensByItself(MicAuto.NOT_WITH_SCREEN_READER, screenReaderOn = true))
    }

    @Test
    fun alwaysListensByItselfWithOrWithoutOne() {
        assertTrue(listensByItself(MicAuto.ALWAYS, screenReaderOn = false))
        assertTrue(listensByItself(MicAuto.ALWAYS, screenReaderOn = true))
    }

    @Test
    fun neverListensByItselfWithOrWithoutOne() {
        assertFalse(listensByItself(MicAuto.NEVER, screenReaderOn = false))
        assertFalse(listensByItself(MicAuto.NEVER, screenReaderOn = true))
    }

    @Test
    fun theSettingStartsAtNotWithAScreenReader() {
        assertEquals(MicAuto.NOT_WITH_SCREEN_READER, AppSettings(MemoryPrefs()).micAuto)
    }
}
