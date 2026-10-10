package com.epicaudiogames.app

import android.content.Context
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.annotation.RequiresApi

/**
 * The ticks that go with the app's sounds (docs/DESIGN.md › Sounds, haptics and the microphone): one as the microphone
 * opens, a softer one as it closes (Settings › Vibrate when listening starts), and a double one when a pack installs.
 * For a player who can't hear the listening sounds, they're the cue. Touch feedback, so the phone's own setting for it
 * applies (Android 13+). A phone with no vibrator just stays still. iOS: Accessibility/Haptics.swift.
 */
class Haptics(context: Context) {
    private val vibrator: Vibrator? = runCatching {
        if (Build.VERSION.SDK_INT >= 31) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            context.getSystemService(Vibrator::class.java)
        }
    }.getOrNull()?.takeIf { it.hasVibrator() }

    /** The microphone opening: a tick. */
    fun micOpened() = tick(OPENED_MS)

    /**
     * The microphone closing: the lightest tick the phone has (Android 12+, where it has one), else the same tick, so
     * the two are told apart by their sounds.
     */
    fun micClosed() {
        if (Build.VERSION.SDK_INT >= 31 &&
            vibrator?.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_LOW_TICK) == true) {
            vibrate(VibrationEffect.startComposition().addPrimitive(VibrationEffect.Composition.PRIMITIVE_LOW_TICK).compose())
        } else {
            tick(CLOSED_MS)
        }
    }

    /** A pack installed: a double click. */
    fun success() = when {
        Build.VERSION.SDK_INT >= 29 -> vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_DOUBLE_CLICK))
        Build.VERSION.SDK_INT >= 26 -> vibrate(VibrationEffect.createWaveform(DOUBLE_CLICK, -1))
        else -> before26(pattern = DOUBLE_CLICK)
    }

    /** Android's own tick (Android 10+), else a buzz of [millis]. */
    private fun tick(millis: Long) = when {
        Build.VERSION.SDK_INT >= 29 -> vibrate(VibrationEffect.createPredefined(VibrationEffect.EFFECT_TICK))
        Build.VERSION.SDK_INT >= 26 -> vibrate(VibrationEffect.createOneShot(millis, VibrationEffect.DEFAULT_AMPLITUDE))
        else -> before26(millis = millis)
    }

    @RequiresApi(26)
    private fun vibrate(effect: VibrationEffect) = buzz {
        if (Build.VERSION.SDK_INT >= 33) {
            it.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_TOUCH))
        } else {
            it.vibrate(effect)
        }
    }

    /** Android 7's way, before VibrationEffect: a buzz of [millis], or the [pattern]'s. */
    @Suppress("DEPRECATION")
    private fun before26(millis: Long = 0, pattern: LongArray? = null) = buzz {
        if (pattern != null) it.vibrate(pattern, -1) else it.vibrate(millis)
    }

    private fun buzz(how: (Vibrator) -> Unit) {
        val v = vibrator ?: return
        runCatching { how(v) }.onFailure { Log.w(TAG, "can't vibrate", it) }
    }

    private companion object {
        const val TAG = "Haptics"
        /** The ticks' lengths on phones without Android's own effects (before Android 10). */
        const val OPENED_MS = 15L
        const val CLOSED_MS = 10L
        /** A double click before Android 10: two short buzzes. */
        val DOUBLE_CLICK = longArrayOf(0, OPENED_MS, 90, OPENED_MS)
    }
}
