package com.epicaudiogames.app.analytics

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import android.util.Log
import com.epicaudiogames.app.BuildConfig
import kotlinx.coroutines.CompletableDeferred
import java.io.File
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.TimeUnit

/**
 * Usage data (docs/DESIGN.md › Usage data): what the player does in the app, as events of web/analytics/events.json
 * with their details ([Events] makes every one). The app tells its [Analytics]; [UsageData] sends them to our server,
 * [NoAnalytics] (tests) nowhere. iOS: Analytics/Analytics.swift.
 */
interface Analytics {
    /** Something happened: an event of the whitelist, with some of its details (see [Events]). */
    fun track(name: String, props: Map<String, Any> = emptyMap())
}

/** Usage data that goes nowhere: the tests', and a screen shown on its own. */
object NoAnalytics : Analytics {
    override fun track(name: String, props: Map<String, Any>) = Unit
}

/** Something happened ([Events] has what). */
fun Analytics.track(event: Event) = track(event.name, event.props)

/** How Settings › Privacy › Delete my usage data went. */
enum class UsageDeletion {
    /** The server deleted what this phone sent under its random ID; the app has forgotten that ID. */
    DELETED,
    /** The server couldn't be reached, or said no: nothing changed, so it can be tried again. */
    FAILED,
    /**
     * There's no random ID on this phone to delete under: usage data is off (turning it off forgets the ID), or nothing
     * has been recorded since it was last forgotten.
     */
    NOTHING_SENT,
}

/** Where the usage data's work is done: one task at a time, in the order they're asked for. */
interface Worker {
    /** Does [task] as soon as what's before it is done. */
    fun run(task: () -> Unit)

    /** Does [task] in [ms] (and every [ms] after that, with [repeat]); what's returned stops it. */
    fun later(ms: Long, repeat: Boolean = false, task: () -> Unit): () -> Unit
}

/**
 * The phone's [Worker]: a thread of its own, so files and requests never hold up the screen. A task that throws is
 * logged and done with: usage data never stops the app.
 */
class ThreadWorker(private val log: (String) -> Unit) : Worker {
    private val executor = ScheduledThreadPoolExecutor(1) { r -> Thread(r, "usage-data").apply { isDaemon = true } }
        .apply { removeOnCancelPolicy = true }

    override fun run(task: () -> Unit) = executor.execute { safely(task) }

    override fun later(ms: Long, repeat: Boolean, task: () -> Unit): () -> Unit {
        val job = if (repeat) {
            executor.scheduleWithFixedDelay({ safely(task) }, ms, ms, TimeUnit.MILLISECONDS)
        } else {
            executor.schedule({ safely(task) }, ms, TimeUnit.MILLISECONDS)
        }
        return { job.cancel(false) }
    }

    private fun safely(task: () -> Unit) {
        try {
            task()
        } catch (e: Exception) {
            log("usage data: ${e.javaClass.simpleName}")
        }
    }
}

/**
 * The app's usage data, sent to our server under a random ID while Settings › Privacy › Share usage data is on
 * ([sharing]): each event stamped with that ID ([InstallId]), the session, its number in the session, the time and
 * the coarse [About] details, then queued ([EventQueue]: kept on the phone until it's sent, at most 1,000 events and
 * a week) and sent ([Sender]) as the app goes off screen, every minute while it's on screen, when a game is left
 * ([flush]) and when the network comes back after a send found none. All of it on a thread of its own ([Worker]).
 *
 * - A session is new each time the app's process starts, and when the app comes back after 30 minutes away.
 * - Turned off, nothing more is recorded or sent, what's waiting is deleted, and the random ID is forgotten; turned on
 *   again, the next event makes a new one, in a new session, so nothing links the two.
 * - [delete] asks the server to delete everything under the ID, then forgets it as turning off does.
 * - On the first run, nothing is sent until onboarding has been finished or skipped ([waitForWelcome]): its welcome
 *   page says plainly that usage data is collected, with Turn off, and a player who turns it off there has sent
 *   nothing at all.
 * - [server] null (a debug build not given one at launch, Firebase Test Lab and so Play's pre-launch report, or
 *   "EpicAnalytics off"): nothing is recorded or sent. Tests use [NoAnalytics].
 * - [strict] (debug builds): an event the whitelist hasn't got, or a detail of the wrong type, throws, so the bug is
 *   found at once; a release build leaves it out (the server would turn away the batch it came in).
 *
 * The process has one ([of]): the session and the queue outlive the screens, as the app comes and goes. iOS:
 * Analytics/Analytics.swift.
 */
class UsageData internal constructor(
    dir: File,
    private val server: String?,
    post: Post,
    private val worker: Worker,
    /** What the app runs on, read as each event is recorded (the kind of device changes as a foldable opens). */
    private val about: () -> About,
    /** Milliseconds that go on counting while the phone sleeps (elapsedRealtime): how long things took. */
    private val clock: () -> Long,
    /** Milliseconds since 1970: when things happened. */
    private val wallClock: () -> Long,
    private val strict: Boolean,
    private val log: (String) -> Unit,
    sharing: Boolean,
    waitForWelcome: Boolean,
    private val newId: () -> UUID = UUID::randomUUID,
) : Analytics {
    private val installId = InstallId(File(dir, INSTALL_ID), newId)
    private val queue = EventQueue(File(dir, QUEUE), wallClock)
    private val sender = server?.let { Sender(queue, post, it, clock, log) }

    // The worker's alone, as the queue and the ID are.
    private var session = newId().toString()
    private var seq = 0
    /** No app_open yet in this process. */
    private var cold = true
    private var onScreen = false
    private var onScreenAt = 0L
    private var offScreenAt: Long? = null
    private var ticking: (() -> Unit)? = null
    private var retrying: (() -> Unit)? = null

    @Volatile private var on = sharing
    @Volatile private var held = waitForWelcome

    init {
        // Turned off before (perhaps in a run that ended before it had forgotten everything): nothing of it is left.
        if (!sharing) worker.run(::forgetAll)
    }

    /**
     * Settings › Privacy › Share usage data. Turned off: nothing more is recorded or sent, what's waiting is deleted
     * and the random ID forgotten (a request already on its way finishes first). Turned on: the next event makes a new
     * random ID.
     */
    var sharing: Boolean
        get() = on
        set(value) {
            if (value == on) return
            on = value
            if (!value) worker.run(::forgetAll)
        }

    /**
     * Onboarding hasn't been finished or skipped yet, on the first run: what happens is kept, but nothing is sent
     * until the player has had the welcome's word about usage data, and its Turn off.
     */
    var waitForWelcome: Boolean
        get() = held
        set(value) {
            if (value == held) return
            held = value
            if (!value) worker.run { send() }
        }

    override fun track(name: String, props: Map<String, Any>) {
        Events.problem(name, props)?.let { problem ->
            // A mistake in the app's own code: found at once in a debug build; never sent from a release one.
            if (strict) throw IllegalArgumentException("usage data: $problem")
            log("usage data: left out $problem")
            return
        }
        if (server == null || !on) return
        val at = wallClock()
        worker.run { if (on) record(Event(name, props), at) }
    }

    /**
     * The app came on screen (MainActivity started): app_open, a new session after 30 minutes away, and what's waiting
     * sent every minute.
     */
    fun foreground() {
        if (server == null) return
        val at = clock()
        val now = wallClock()
        worker.run {
            if (onScreen) return@run                // the activity made again, as a tablet turned: still on screen
            onScreen = true
            onScreenAt = at
            offScreenAt?.let { if (at - it >= NEW_SESSION_MS) newSession() }
            offScreenAt = null
            if (on) record(Events.appOpen(cold, first = installId.peek() == null), now)
            cold = false
            ticking?.invoke()
            ticking = worker.later(TICK_MS, repeat = true) { send() }
        }
    }

    /** The app went off screen (MainActivity stopped, not to be remade at once): app_background, and sending now. */
    fun background() {
        if (server == null) return
        val at = clock()
        val now = wallClock()
        worker.run {
            if (!onScreen) return@run
            onScreen = false
            offScreenAt = at
            ticking?.invoke()
            ticking = null
            if (on) record(Events.appBackground((at - onScreenAt) / 1000), now)
            send()
        }
    }

    /** Sends what's waiting now (a game was just left), unless sending is waiting after a failure. */
    fun flush() {
        if (server != null) worker.run { send() }
    }

    /** The phone has a network again: what a send without one left waiting goes now. */
    fun networkBack() {
        worker.run { if (sender?.offline == true) send(anyway = true) }
    }

    /**
     * Settings › Privacy › Delete my usage data: the server is asked to delete everything under the random ID (after
     * any request on its way), then the ID is forgotten and what's waiting deleted, as turning usage data off does;
     * on, the next event makes a new ID. If the server can't be reached nothing changes, so it can be asked again.
     */
    suspend fun delete(): UsageDeletion {
        val sender = sender ?: return UsageDeletion.NOTHING_SENT
        val answer = CompletableDeferred<UsageDeletion>()
        worker.run {
            answer.complete(
                try {
                    val id = installId.peek()
                    when {
                        id == null -> UsageDeletion.NOTHING_SENT
                        sender.forget(id) -> {
                            forgetAll()
                            UsageDeletion.DELETED
                        }
                        else -> UsageDeletion.FAILED
                    }
                } catch (e: Exception) {
                    UsageDeletion.FAILED
                },
            )
        }
        return answer.await()
    }

    /** An event stamped and queued: the ID (made now if there isn't one), the session, its number, its time. */
    private fun record(event: Event, at: Long) {
        queue.add(Events.json(event, Stamp(installId.get(), session, seq++, at, about())))
    }

    /**
     * Sends what's waiting, unless it mustn't now: usage data off, the welcome not seen yet, or waiting after a
     * failure ([anyway]: the network's back, worth a try). What can't go is tried again when the wait is over.
     */
    private fun send(anyway: Boolean = false) {
        val sender = sender ?: return
        if (!on || held || queue.isEmpty()) return
        if (!anyway && !sender.ready()) return
        retrying?.invoke()
        retrying = null
        sender.send(stillOn = { on })
        val retryAt = sender.retryAt
        if (retryAt != null && !queue.isEmpty()) {
            retrying = worker.later(maxOf(0L, retryAt - clock())) { send() }
        }
    }

    /** A new session: a new ID for it, its events counted from 0 again. */
    private fun newSession() {
        session = newId().toString()
        seq = 0
    }

    /**
     * Nothing of the usage data left on the phone: what's waiting and the random ID go, and a new session starts, so
     * nothing sent later can be linked to what went before.
     */
    private fun forgetAll() {
        queue.clear()
        installId.forget()
        newSession()
        retrying?.invoke()
        retrying = null
        sender?.reset()
    }

    companion object {
        /** Where the release app sends usage data (/api/events and /api/forget, web/server.js). */
        const val SERVER = "https://epicaudiogames.com"
        /**
         * The launch's intent extra for another server, in a debug build only: `adb shell am start -n
         * com.epicaudiogames.app/.MainActivity --es EpicAnalytics http://127.0.0.1:3000` (with `adb reverse tcp:3000
         * tcp:3000`, the web server on this computer). "off" turns usage data off in any build, for that run.
         */
        const val EXTRA = "EpicAnalytics"
        /** Its folder, in no_backup (never in a backup), and its two files. */
        const val DIR = "analytics"
        const val INSTALL_ID = "install_id"
        const val QUEUE = "queue.jsonl"
        /** On screen, what's waiting is sent this often (ms). */
        const val TICK_MS = 60_000L
        /** Back on screen after this long away (ms): a new session. */
        const val NEW_SESSION_MS = 30L * 60 * 1000
        private const val TAG = "UsageData"

        /**
         * Where this process's usage data goes: our server in a release build, the [extra]'s address in a debug one
         * (none without one), and nowhere in Firebase Test Lab ([testLab]: Play's pre-launch report) or with "off".
         */
        fun serverFor(debug: Boolean, extra: String?, testLab: Boolean): String? = when {
            testLab -> null
            extra.equals("off", ignoreCase = true) -> null
            !debug -> SERVER
            extra == null -> null
            else -> extra.trim().trimEnd('/').removeSuffix("/api/events").trimEnd('/')
                .takeIf { it.startsWith("http://") || it.startsWith("https://") }
        }

        /** The first launch's EpicAnalytics extra: the process's usage data goes as it says (see [of]). */
        @Volatile private var launchExtra: String? = null
        private var made: UsageData? = null

        /** MainActivity's launch, before the app's model is made: its EpicAnalytics extra, if it has one. */
        fun launchedWith(intent: Intent?) {
            if (made == null) intent?.getStringExtra(EXTRA)?.let { launchExtra = it }
        }

        /** The process's usage data: made the first time it's asked for, as Settings ([sharing]) and onboarding are. */
        @Synchronized
        fun of(context: Context, sharing: Boolean, waitForWelcome: Boolean): UsageData = made ?: run {
            val app = context.applicationContext
            val log: (String) -> Unit = { if (BuildConfig.DEBUG) Log.d(TAG, it) }
            val testLab = runCatching {
                Settings.System.getString(app.contentResolver, "firebase.test.lab") == "true"
            }.getOrDefault(false)
            val server = serverFor(BuildConfig.DEBUG, launchExtra, testLab)
            log(if (server == null) "usage data: off in this run" else "usage data: to $server")
            // What kind of device it is doesn't change; how wide its screen is does (a foldable opened).
            val pm = app.packageManager
            val watch = pm.hasSystemFeature(PackageManager.FEATURE_WATCH)
            // PackageManager.FEATURE_PC (Android 8.1), by name: Chromebooks have it on older Androids too.
            val pc = pm.hasSystemFeature("android.hardware.type.pc")
            UsageData(
                dir = File(app.noBackupFilesDir, DIR),
                server = server,
                post = HttpPost("EpicAudioGames/${BuildConfig.VERSION_NAME} (android)"),
                worker = ThreadWorker(log),
                about = {
                    About(
                        appVersion = BuildConfig.VERSION_NAME,
                        build = BuildConfig.VERSION_CODE.toString(),
                        osVersion = Build.VERSION.RELEASE.orEmpty(),
                        lang = Locale.getDefault().toLanguageTag(),
                        formFactor = formFactor(watch, pc, app.resources.configuration.smallestScreenWidthDp),
                    )
                },
                clock = SystemClock::elapsedRealtime,
                wallClock = System::currentTimeMillis,
                strict = BuildConfig.DEBUG,
                log = log,
                sharing = sharing,
                waitForWelcome = waitForWelcome,
            ).also {
                if (server != null) it.watchNetwork(app)
                made = it
            }
        }
    }

    /** The network coming back sends what a send without one left waiting ([networkBack]). */
    private fun watchNetwork(context: Context) {
        val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return
        runCatching {
            connectivity.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = networkBack()
            })
        }
    }
}
