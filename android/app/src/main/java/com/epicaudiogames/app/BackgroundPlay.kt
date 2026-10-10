package com.epicaudiogames.app

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.view.KeyEvent
import androidx.compose.runtime.snapshotFlow
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.core.content.IntentCompat
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * What lets a game go on with the screen off or the phone in a pocket, for as long as it's open: a foreground service
 * ([GameService]: the voice keeps playing and the mic keeps listening), its notification (the game, its cover, and the
 * talking circle's button), a media session (the headphones' button does what a tap on the talking circle does,
 * [GameController.circle]; pause pauses, and play carries on or talks), and a wake lock while the game speaks or
 * listens.
 *
 * Android only lets the service use the mic in the background if it was started with the mic allowed and the app on
 * screen: [start] (the game opening) and [micAllowed] are both called from the screen.
 */
class BackgroundPlay(private val context: Context, private val game: GameController) {
    private val scope = MainScope()
    private val cover: Bitmap? = runCatching {
        context.assets.open("${game.info.id}/cover.jpg").use { BitmapFactory.decodeStream(it) }
    }.getOrNull()
    /** The cover's middle, square, for the notification's picture. */
    private val icon: Bitmap? = cover?.let {
        val side = minOf(it.width, it.height)
        Bitmap.createBitmap(it, (it.width - side) / 2, (it.height - side) / 2, side, side)
    }
    private val openApp = PendingIntent.getActivity(
        context, 0,
        Intent(context, MainActivity::class.java).setAction(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
    private val tapCircle = PendingIntent.getService(
        context, 1, Intent(context, GameService::class.java).setAction(GameService.ACTION_CIRCLE),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )
    private val session = MediaSession(context, "EpicAudioGames").apply {
        @Suppress("DEPRECATION")    // needed before Android 8, ignored after
        setFlags(MediaSession.FLAG_HANDLES_MEDIA_BUTTONS or MediaSession.FLAG_HANDLES_TRANSPORT_CONTROLS)
        setSessionActivity(openApp)
        setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, game.info.title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, context.getString(R.string.app_name))
                .apply { if (cover != null) putBitmap(MediaMetadata.METADATA_KEY_ALBUM_ART, cover) }
                .build(),
        )
        setCallback(Buttons(), Handler(Looper.getMainLooper()))
    }
    private val wakeLock = context.getSystemService(PowerManager::class.java)
        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "EpicAudioGames:game")
        .apply { setReferenceCounted(false) }
    /** The notification's button now: what a tap on the talking circle does ([circle]), or none. */
    private var state: CircleAction? = null
    private var closed = false
    /** The service was started with the mic allowed: it may listen in the background. */
    private var listens = false

    /** The game opening (on screen): the service starts, and the notification and session follow the game. */
    fun start() {
        current = this
        session.isActive = true
        state = circle()
        listens = Permissions.micGranted(context)
        GameService.start(context)
        scope.launch {
            snapshotFlow { circle() to (game.speaking || game.listening) }.collect { (circle, busy) ->
                // The CPU stays up while the game talks or listens (the screen may be off); not while it waits.
                if (busy) wakeLock.acquire(WAKE_MS) else if (wakeLock.isHeld) wakeLock.release()
                if (circle != state) Log.i(TAG, "${game.info.id}: ${circle?.name ?: "no button"}")
                state = circle
                session.setPlaybackState(playback(circle))
                if (current === this@BackgroundPlay) GameService.update(context, notification())
            }
        }
    }

    /** The mic just allowed (the app on screen): the service starts again, now allowed to listen in the background. */
    fun micAllowed() {
        if (closed || listens) return
        listens = true
        GameService.start(context)
    }

    /** The game closing: the service stops, and the notification and media session go. */
    fun stop() {
        if (closed) return
        closed = true
        scope.cancel()
        if (current === this) {
            current = null
            GameService.stop()
        }
        session.isActive = false
        session.release()
        if (wakeLock.isHeld) wakeLock.release()
    }

    /** What the talking circle does now, for the notification's button ([notificationButton]). */
    private fun circle() = notificationButton(game.circleAction, end = game.end != null)

    /**
     * Play (the lock screen's, or headphones'): carries on when paused, else talks when the game is waiting for an
     * answer; otherwise nothing.
     */
    private fun play(from: String) {
        if (closed) return
        val waiting = game.ask != null && !game.speaking && !game.listening
        Log.i(TAG, "${game.info.id}: $from -> ${if (game.paused) "carry on" else if (waiting) "talk" else "nothing"}")
        when {
            game.paused -> game.carryOn()
            waiting -> game.mic()
        }
    }

    /**
     * Pause (the lock screen's, or headphones taken out of the ears): the game waits for a tap, as for "stop". Already
     * paused, or at an end, nothing.
     */
    private fun pause(from: String) {
        if (closed) return
        Log.i(TAG, "${game.info.id}: $from -> pause")
        if (!game.paused && game.end == null) game.pause()
    }

    /** The headphones' play/pause or hook button, and the notification's: a tap on the talking circle. */
    fun tap(from: String) {
        if (closed) return
        Log.i(TAG, "${game.info.id}: $from -> ${state?.name ?: "nothing"}")
        game.circle()
    }

    /** Playing while the game speaks or listens (the lock screen then shows pause, which pauses the game). */
    private fun playback(circle: CircleAction?): PlaybackState {
        val playing = circle == CircleAction.SKIP || circle == CircleAction.STOP_LISTENING
        return PlaybackState.Builder()
            .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or PlaybackState.ACTION_PLAY_PAUSE)
            .setState(
                if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                PlaybackState.PLAYBACK_POSITION_UNKNOWN, if (playing) 1f else 0f,
            )
            .build()
    }

    fun notification(): Notification {
        val b = builder(context)
            .setContentTitle(game.info.title)
            .setContentText(context.getString(R.string.app_name))
            .setContentIntent(openApp)
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
        if (icon != null) b.setLargeIcon(icon)
        val style = Notification.MediaStyle().setMediaSession(session.sessionToken)
        // Named as the circle is on screen: what TalkBack says for it on the lock screen and in the shade.
        val button = state
        if (button != null) {
            val icon = Icon.createWithResource(context, button.icon)
            b.addAction(Notification.Action.Builder(icon, context.getString(button.label), tapCircle).build())
            style.setShowActionsInCompactView(0)
        }
        b.setStyle(style)
        if (Build.VERSION.SDK_INT >= 31) b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        return b.build()
    }

    private inner class Buttons : MediaSession.Callback() {
        override fun onMediaButtonEvent(intent: Intent): Boolean {
            val key = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
                ?: return super.onMediaButtonEvent(intent)
            // Each press counts once, on its way down. A wired headset's button (HEADSETHOOK) and play/pause are a tap
            // on the talking circle; PAUSE (as when earbuds come out of the ears) pauses, and PLAY carries on or talks.
            val name = KeyEvent.keyCodeToString(key.keyCode)
            val press = key.action == KeyEvent.ACTION_DOWN && key.repeatCount == 0
            when (key.keyCode) {
                KeyEvent.KEYCODE_HEADSETHOOK, KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> if (press) tap(name)
                KeyEvent.KEYCODE_MEDIA_PAUSE -> if (press) pause(name)
                KeyEvent.KEYCODE_MEDIA_PLAY -> if (press) play(name)
                else -> return super.onMediaButtonEvent(intent)
            }
            return true
        }

        // The lock screen's and the notification shade's play/pause.
        override fun onPlay() = play("play")
        override fun onPause() = pause("pause")
    }

    /** The notification button's icon: play to carry on, skip, stop listening, and the mic to talk. */
    private val CircleAction.icon: Int
        get() = when (this) {
            CircleAction.CARRY_ON -> R.drawable.ic_play
            CircleAction.SKIP -> R.drawable.ic_skip
            CircleAction.STOP_LISTENING -> R.drawable.ic_stop
            CircleAction.TALK, CircleAction.MIC_REFUSED, CircleAction.NO_RECOGNITION, CircleAction.WAIT ->
                R.drawable.ic_mic
        }

    companion object {
        private const val TAG = "BackgroundPlay"
        private const val CHANNEL = "game"
        /** A wake lock's longest hold: taken again at each change, so only a game stuck speaking lets it go. */
        private const val WAKE_MS = 30 * 60 * 1000L

        /** The open game's (one at a time): what the service shows, and what its notification's button taps. */
        @SuppressLint("StaticFieldLeak")    // its context is the application, and it's cleared as the game closes
        var current: BackgroundPlay? = null
            private set

        /** A notification on the games' channel (quiet: it's there while a game is open), with the app's icon. */
        fun builder(context: Context): Notification.Builder {
            val b = if (Build.VERSION.SDK_INT >= 26) {
                context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                    NotificationChannel(
                        CHANNEL, context.getString(R.string.notification_channel), NotificationManager.IMPORTANCE_LOW,
                    ).apply {
                        description = context.getString(R.string.notification_channel_description)
                        setShowBadge(false)
                    },
                )
                Notification.Builder(context, CHANNEL)
            } else {
                @Suppress("DEPRECATION") Notification.Builder(context)
            }
            return b.setSmallIcon(R.drawable.ic_notification)
        }
    }
}

/**
 * The notification's button for the talking circle's [action]: the circle's own, named as on screen, but none at an
 * [end] (paused or not), none while there's nothing to do yet, and none for a refused mic, as asking for it needs the
 * screen. So it shows when it always has; a recogniser that isn't available keeps its button (a tap tries again).
 */
internal fun notificationButton(action: CircleAction?, end: Boolean): CircleAction? =
    action?.takeIf { !end && it.enabled && it != CircleAction.MIC_REFUSED }

/**
 * The foreground service that keeps an open game going with the screen off: the voice plays (media playback) and the
 * mic listens (microphone: only when the mic is allowed, as Android 14 requires). It shows [BackgroundPlay]'s
 * notification, and stops when the game closes.
 */
class GameService : Service() {
    private var lastStart = 0

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        lastStart = startId
        val play = BackgroundPlay.current
        if (intent?.action == ACTION_CIRCLE) {
            // The notification's button (the service is already in the foreground).
            if (play != null) play.tap("notification") else finish()
            return START_NOT_STICKY
        }
        // A start asked for with startForegroundService must go to the foreground, even when the game has closed since.
        val notification = play?.notification()
            ?: BackgroundPlay.builder(this).setContentTitle(getString(R.string.app_name)).build()
        foreground(notification)
        if (play == null || !wanted) finish()
        return START_NOT_STICKY
    }

    private fun foreground(notification: Notification) {
        var types = if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK else 0
        val mic = Permissions.micGranted(this)
        if (mic && Build.VERSION.SDK_INT >= 30) types = types or ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
        try {
            ServiceCompat.startForeground(this, ID, notification, types)
            Log.i(TAG, "in the foreground (${if (mic) "playing and listening" else "playing"})")
        } catch (e: Exception) {
            // Android turning the mic down (the app not on screen any more): playing alone, then.
            Log.w(TAG, "couldn't go to the foreground with types $types", e)
            if (types != 0) runCatching {
                ServiceCompat.startForeground(this, ID, notification,
                    if (Build.VERSION.SDK_INT >= 29) ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK else 0)
            }.onFailure { Log.w(TAG, "couldn't go to the foreground", it) }
        }
    }

    private fun finish() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        // Only if no start has come since (a game opening again at once).
        stopSelf(lastStart)
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "GameService"
        private const val ID = 1
        const val ACTION_CIRCLE = "com.epicaudiogames.app.CIRCLE"
        private var instance: GameService? = null
        /** Whether a game wants the service: one stopped before it started still has to go to the foreground first. */
        private var wanted = false

        /** Starts the service, or starts it again (a mic just allowed): from the screen only. */
        fun start(context: Context) {
            wanted = true
            try {
                ContextCompat.startForegroundService(context, Intent(context, GameService::class.java))
            } catch (e: Exception) {
                // Android 12+ refuses a start from the background: the game plays on while the app is on screen.
                Log.w(TAG, "couldn't start", e)
            }
        }

        /** The notification again (the button changed). Only while the service runs, so it doesn't outlive it. */
        fun update(context: Context, notification: Notification) {
            if (instance == null) return
            context.getSystemService(NotificationManager::class.java).notify(ID, notification)
        }

        fun stop() {
            wanted = false
            instance?.finish()
        }
    }
}
