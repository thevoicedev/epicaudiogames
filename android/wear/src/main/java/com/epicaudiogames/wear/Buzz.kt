package com.epicaudiogames.wear

import android.content.Context
import android.media.AudioAttributes
import android.os.Build
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import com.epicaudiogames.wearlink.WearHaptic

/**
 * The watch's buzzes (docs/DESIGN.md › Watches): a long, strong one as the phone's microphone opens and two short ones
 * as it closes, the cue for a player who can't hear the listening sound; and three light ones when a press can't reach
 * the phone. They're told apart by their rhythm as well as their strength, as a watch's motor may not do strengths.
 * They play as a game's (media) vibration, which the watch's touch-vibration setting doesn't turn off. A watch with no
 * vibrator just stays still. iOS's watch plays watchOS's start, stop and failure haptics (PhoneLink.swift); the phone
 * app's own ticks are Haptics.kt.
 */
class Buzz(context: Context) {
    private val vibrator: Vibrator? = runCatching {
        if (Build.VERSION.SDK_INT >= 31) {
            context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            context.getSystemService(Vibrator::class.java)
        }
    }.getOrNull()?.takeIf { it.hasVibrator() }

    /** The microphone opened or closed on the phone. */
    fun play(haptic: WearHaptic) = vibrate(of(haptic))

    /** A press that couldn't reach the phone. */
    fun failure() = vibrate(FAILURE)

    private fun vibrate(pattern: Pattern) {
        val v = vibrator ?: return
        val effect = if (v.hasAmplitudeControl()) {
            VibrationEffect.createWaveform(pattern.timings, pattern.amplitudes, -1)
        } else {
            VibrationEffect.createWaveform(pattern.timings, -1)
        }
        runCatching {
            if (Build.VERSION.SDK_INT >= 33) {
                v.vibrate(effect, VibrationAttributes.createForUsage(VibrationAttributes.USAGE_MEDIA))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(effect, AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_GAME).build())
            }
        }.onFailure { Log.w(TAG, "can't vibrate", it) }
    }

    /**
     * A buzz: how long each step lasts ([timings], ms, starting with a pause) and how strong each is ([amplitudes], 0
     * to 255; a motor without strengths buzzes every other step at its own).
     */
    class Pattern(val timings: LongArray, val amplitudes: IntArray) {
        init {
            require(timings.size == amplitudes.size) { "a step without a strength" }
        }

        /** How long it buzzes, in all (ms). */
        val buzzing: Long get() = timings.filterIndexed { i, _ -> amplitudes[i] > 0 }.sum()

        /** How many separate buzzes it has. */
        val pulses: Int get() = amplitudes.count { it > 0 }
    }

    companion object {
        private const val TAG = "Buzz"

        /** The microphone opening: one long buzz, as strong as the motor goes. */
        val STARTED = Pattern(longArrayOf(0, 400), intArrayOf(0, 255))

        /** The microphone closing: two short buzzes, a little softer. */
        val STOPPED = Pattern(longArrayOf(0, 90, 110, 90), intArrayOf(0, 200, 0, 200))

        /** A press that couldn't reach the phone: three quick, light buzzes. */
        val FAILURE = Pattern(longArrayOf(0, 50, 70, 50, 70, 50), intArrayOf(0, 140, 0, 140, 0, 140))

        /** The buzz for [haptic]. */
        fun of(haptic: WearHaptic): Pattern = when (haptic) {
            WearHaptic.LISTENING_STARTED -> STARTED
            WearHaptic.LISTENING_STOPPED -> STOPPED
        }
    }
}
