package com.epicaudiogames.wear

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.epicaudiogames.wearlink.Stamped
import com.epicaudiogames.wearlink.WearCommand
import com.epicaudiogames.wearlink.WearInbox
import com.epicaudiogames.wearlink.WearLink
import com.epicaudiogames.wearlink.WearState
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataRequest
import com.google.android.gms.wearable.Wearable

// The watch's side of Wear OS's Data Layer: the phone's game coming in, the buttons going out. The phone's side is
// android/app's WearBridge.kt; iOS's watch has the same through WatchConnectivity (ios/EpicWatch/PhoneLink.swift).

/**
 * The game on the phone as the watch hears of it ([state]), and its two buttons' way back ([press]). The phone keeps
 * its latest state as a data item, which Google Play services copies to the watch: it's read as the screen comes up,
 * and each change is heard while the screen is up ([start], [stop]); they're taken newest first (WearLink.kt's
 * WearInbox). The microphone opening buzzes the watch strongly, and closing it buzzes differently ([Buzz]): the cue for
 * a player who can't hear the listening sound (docs/DESIGN.md › Watches). A press goes as a message to the phone that
 * has the app (its capability), which does it as the headphones' button or the pause; one that can't reach it buzzes a
 * failure, and says so ([trouble]) until the phone is heard from again. With a [demo] state (a debug build's,
 * WatchDemo.kt) it shows that and hears nothing.
 */
class PhoneLink(context: Context, private val buzz: Buzz, private val demo: WearState? = null) {
    /** The game on the phone: none, until the phone says. */
    var state by mutableStateOf(demo ?: WearState.NONE)
        private set

    /** A press couldn't reach the phone; false again once the phone is heard from. */
    var trouble by mutableStateOf(false)
        private set

    private val inbox = WearInbox()
    private val data = Wearable.getDataClient(context.applicationContext)
    private val messages = Wearable.getMessageClient(context.applicationContext)
    private val capabilities = Wearable.getCapabilityClient(context.applicationContext)
    private val main = Handler(Looper.getMainLooper())
    private var hearing = false

    /** The phone's state changing, while the screen is up. Read as it comes: the events go once this returns. */
    private val changes = DataClient.OnDataChangedListener { events ->
        val states = events
            .filter { it.type == DataEvent.TYPE_CHANGED && it.dataItem.uri.path == WearLink.STATE_PATH }
            .mapNotNull { stamped(it.dataItem) }
        main.post { for (s in states) received(s, catchingUp = false) }
    }

    /** The phone in reach again: what a failed press said goes. */
    private val reach = CapabilityClient.OnCapabilityChangedListener { info ->
        if (info.nodes.isNotEmpty()) main.post { trouble = false }
    }

    /** The screen is up: the phone's latest state, kept from before, then each change. */
    fun start() {
        if (demo != null || hearing) return
        hearing = true
        data.addListener(changes, STATE_URI, DataClient.FILTER_LITERAL)
        capabilities.addListener(reach, WearLink.PHONE_CAPABILITY)
        data.getDataItems(STATE_URI, DataClient.FILTER_LITERAL)
            .addOnSuccessListener { items ->
                // A phone this watch was paired with before may have left one too: the newest is this phone's.
                val latest = try {
                    items.mapNotNull(::stamped).maxByOrNull { it.at }
                } finally {
                    items.release()
                }
                // Whatever changed while the screen was away isn't news now: no buzz for it.
                if (latest != null) received(latest, catchingUp = true)
            }
            .addOnFailureListener { Log.w(TAG, "couldn't read the phone's state", it) }
    }

    /** The screen has gone: nothing more is heard until it's back. */
    fun stop() {
        if (!hearing) return
        hearing = false
        data.removeListener(changes)
        capabilities.removeListener(reach)
    }

    /**
     * A button pressed: the big one ([WearCommand.PRIMARY]) or Pause, sent to the phone, which does it as the
     * headphones' button or the pause does there (WearBridge.perform). The phone must be in reach (near, or on the same
     * network); the message starts the phone app if it isn't running.
     */
    fun press(command: WearCommand) {
        if (demo != null) return
        capabilities.getCapability(WearLink.PHONE_CAPABILITY, CapabilityClient.FILTER_REACHABLE)
            .addOnSuccessListener { info ->
                val phone = info.nodes.firstOrNull { it.isNearby } ?: info.nodes.firstOrNull()
                if (phone == null) {
                    couldntReach()
                } else {
                    messages.sendMessage(phone.id, WearLink.COMMAND_PATH, command.payload)
                        .addOnFailureListener {
                            Log.w(TAG, "a press didn't reach the phone", it)
                            couldntReach()
                        }
                }
            }
            .addOnFailureListener {
                Log.w(TAG, "couldn't find the phone", it)
                couldntReach()
            }
    }

    /** A state from the phone: shown if it's the newest, with a buzz if the microphone opened or closed. */
    private fun received(new: Stamped, catchingUp: Boolean) {
        val taken = inbox.take(new.state, new.at, catchingUp)
        if (!taken.shown) return
        state = inbox.state
        trouble = false
        taken.haptic?.let(buzz::play)
    }

    private fun couldntReach() {
        trouble = true
        buzz.failure()
    }

    private companion object {
        const val TAG = "PhoneLink"

        /** The phone's data item, from whichever node has it (the host is a wildcard). */
        val STATE_URI: Uri = Uri.Builder()
            .scheme(PutDataRequest.WEAR_URI_SCHEME)
            .authority("*")
            .path(WearLink.STATE_PATH)
            .build()

        /** The state in a data item from the phone; null for anything else. */
        fun stamped(item: DataItem): Stamped? {
            val map = DataMapItem.fromDataItem(item).dataMap
            return WearState.from(map.keySet().associateWith { map.get<Any?>(it) })
        }
    }
}
