package com.epicaudiogames.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.wear.ambient.AmbientLifecycleObserver

/**
 * The Wear OS app: one screen (WatchScreen.kt) showing the game on the phone (PhoneLink.kt), which is heard while the
 * screen is up (started to stopped). It supports ambient mode: with the wrist down the screen stays on the game,
 * dimmed, and the buzzes as the phone's microphone opens and closes still come, which is when a player relying on them
 * needs them. A debug build can show a game's state without a phone (WatchDemo.kt). iOS: EpicWatchApp.swift.
 */
class WatchActivity : ComponentActivity() {
    private lateinit var phone: PhoneLink

    /** The watch is in ambient mode (the wrist down, the screen dimmed). */
    private var ambient by mutableStateOf(false)

    private val ambientObserver = AmbientLifecycleObserver(
        this,
        object : AmbientLifecycleObserver.AmbientLifecycleCallback {
            override fun onEnterAmbient(ambientDetails: AmbientLifecycleObserver.AmbientDetails) {
                ambient = true
            }

            override fun onExitAmbient() {
                ambient = false
            }
        },
    )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        lifecycle.addObserver(ambientObserver)
        phone = PhoneLink(this, Buzz(this), demo = WatchDemo.state(intent))
        setContent { WatchScreen(phone.state, phone.trouble, ambient, onPress = phone::press) }
    }

    override fun onStart() {
        super.onStart()
        phone.start()
    }

    override fun onStop() {
        phone.stop()
        super.onStop()
    }
}
