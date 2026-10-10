package com.epicaudiogames.app

import android.app.Application
import android.content.Intent
import android.content.pm.ActivityInfo
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.LazyGridState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.splashscreen.SplashScreen.Companion.installSplashScreen
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.epicaudiogames.app.analytics.Event
import com.epicaudiogames.app.analytics.Events
import com.epicaudiogames.app.analytics.HelpSource
import com.epicaudiogames.app.analytics.MicAsked
import com.epicaudiogames.app.analytics.UsageData
import com.epicaudiogames.app.analytics.UsageDeletion
import com.epicaudiogames.app.analytics.track
import com.epicaudiogames.app.ui.AppStart
import com.epicaudiogames.app.ui.ButtonKind
import com.epicaudiogames.app.ui.EpicButton
import com.epicaudiogames.app.ui.FirstKeys
import com.epicaudiogames.app.ui.GameScreen
import com.epicaudiogames.app.ui.HelpScreen
import com.epicaudiogames.app.ui.HelpSheet
import com.epicaudiogames.app.ui.HomeScreen
import com.epicaudiogames.app.ui.IntroScreen
import com.epicaudiogames.app.ui.IntroTimes
import com.epicaudiogames.app.ui.LocalScreenReaderFocus
import com.epicaudiogames.app.ui.LocalShortcuts
import com.epicaudiogames.app.ui.MainTabs
import com.epicaudiogames.app.ui.ONBOARDING_VERSION
import com.epicaudiogames.app.ui.Onboarding
import com.epicaudiogames.app.ui.ScreenReaderFocus
import com.epicaudiogames.app.ui.SettingsScreen
import com.epicaudiogames.app.ui.ShopScreen
import com.epicaudiogames.app.ui.ShopSource
import com.epicaudiogames.app.ui.Shortcut
import com.epicaudiogames.app.ui.Shortcuts
import com.epicaudiogames.app.ui.StoreSheet
import com.epicaudiogames.app.ui.Tab
import com.epicaudiogames.app.ui.tabAfterOnboarding
import com.epicaudiogames.app.ui.windowTestTags
import com.epicaudiogames.app.ui.theme.EpicTheme
import com.epicaudiogames.app.ui.theme.restoreBarIcons
import com.epicaudiogames.engine.GameMap
import com.epicaudiogames.engine.Play
import com.epicaudiogames.engine.Session
import com.epicaudiogames.engine.nuclear.NuclearAudio
import com.epicaudiogames.engine.nuclear.NuclearWar
import java.io.File

class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()
    /** The keyboard's shortcuts (ui/Keyboard.kt): the screens showing say what each does. */
    private val shortcuts = Shortcuts()
    /** Where TalkBack's focus is (ui/ScreenReaderFocus.kt): the game's one button keeps still under it. */
    private val screenReaderFocus = ScreenReaderFocus()

    override fun onCreate(savedInstanceState: Bundle?) {
        // A notification sound left muted by a listen the app was stopped in (a crash) comes back (RecognizerBeep.kt).
        RecognizerBeep.recover(this)
        // Where usage data goes in a debug build (its EpicAnalytics extra), known before the model is made.
        UsageData.launchedWith(intent)
        // A debug build's launch extras (DebugLaunch.kt in src/debug; nothing at all in a release build): the saves and
        // settings cleared or set, and how the games hear, before the model reads them. For a launch, not for the
        // activity made again (a tablet turning), which keeps its model and must not be reset under the player.
        val launch = savedInstanceState == null
        if (launch) DebugLaunch.launching(this, intent)
        // The system's splash (Theme.EpicAudioGames.Starting: navy, the emblem) until the first frame, on Android 7 to
        // 11 as on 12 and later; the intro then takes over with the emblem in the same place (ui/IntroScreen.kt).
        val splash = installSplashScreen()
        super.onCreate(savedInstanceState)
        // Android's own way out of the splash fades its emblem first, and the intro's would show through, dimmed then
        // whole again: under the intro the splash just goes, as nothing changes. Straight to onboarding or the tabs,
        // it fades out quickly (at once with Reduce motion, or the phone's animations off). Once it's gone, a debug
        // build's log lines can say what's on screen (DebugLaunch).
        splash.setOnExitAnimationListener { view ->
            val gone = {
                view.remove()
                // Taking the splash away has put the theme's own bar icons back (light ones), over what EpicTheme set
                // for the palette: on a light screen they'd be white on white.
                restoreBarIcons(window)
                DebugLaunch.splashGone()
            }
            if (model.intro || model.settings.reduceMotion) {
                gone()
            } else {
                view.view.animate().alpha(0f).setDuration(SPLASH_FADE_MS).withEndAction { gone() }.start()
            }
        }
        // Phones stay portrait; tablets, foldables open and Chromebooks turn any way and take any window size
        // (docs/DESIGN.md › Tablets…), as Android 16 makes every app do on a large screen.
        requestedOrientation = if (resources.configuration.smallestScreenWidthDp >= LARGE_SCREEN_DP) {
            ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
        } else {
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
        }
        // Drawn under transparent bars; their icons follow the app's theme, not just the phone's dark mode (EpicTheme).
        enableEdgeToEdge()
        val screens = ComposeView(this).apply {
            setContent {
                CompositionLocalProvider(
                    LocalShortcuts provides shortcuts,
                    LocalScreenReaderFocus provides screenReaderFocus,
                ) { App(model) }
            }
        }
        // Space is offered to the game before anything else has it (FirstKeys): its one button, wherever the focus is.
        // It hears TalkBack's focus come and go, too.
        setContentView(
            FirstKeys(this) { it.keyCode == KeyEvent.KEYCODE_SPACE && shortcut(it) }.apply {
                onScreenReaderFocus = screenReaderFocus::follow
                addView(screens)
            },
        )
        // The rest of the launch's extras, the model made: the tab, a store sheet, a game played by itself, and the
        // log lines the screenshot tools wait for.
        if (launch) DebugLaunch.launched(model)
    }

    /** A launch for the activity already showing (am start --activity-single-top): a debug build's extras again. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        DebugLaunch.newIntent(model, intent)
    }

    // A key nothing on screen used (the focus elsewhere, or on something that doesn't take it): a shortcut, if the
    // screen showing has one for it (Escape, Ctrl with a tab's number). A key that isn't one goes on to Android.
    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean = shortcut(event) || super.onKeyDown(keyCode, event)

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean =
        shortcuts.released(keyCode) || super.onKeyUp(keyCode, event)

    /** A key that may be a shortcut, going down or up: true if the screen showing used it. */
    private fun shortcut(event: KeyEvent): Boolean = Shortcut.of(event)?.let { shortcuts.key(event, it) } ?: false

    override fun onStart() {
        super.onStart()
        model.onScreen(true)
    }

    override fun onStop() {
        super.onStop()
        // (Stopped only to be made again at once, as a tablet turns, the app hasn't gone anywhere.)
        model.onScreen(false, remade = isChangingConfigurations)
    }
}

/**
 * The way in (the intro, onboarding), the tabs (Games, Shop, Help, Settings), and the game being played over them (one
 * at a time), with the help sheet over it.
 */
class AppModel(app: Application) : AndroidViewModel(app) {
    val games = Catalog.load(app.assets)
    val saves = Saves(app)
    val packs = Packs(app)
    /** The player's settings, read before the first frame (the theme, the intro). */
    val settings = AppSettings(SharedPrefs(app))
    /** Whether TalkBack (or another screen reader) is on, as it changes. */
    val screenReader = ScreenReader(app)
    /**
     * The app's own sounds (AppAudio.kt): the intro's sting, the welcome and help read aloud, the success sound, and
     * Settings' samples. Its manifest has the help pages.
     */
    val appAudio = AppAudio(app, settings)
    /** The help topics, this app's, in order (the manifest's; none in a build without it). */
    val helpPages: List<HelpPage> get() = appAudio.manifest?.help.orEmpty()
    /**
     * What shows before the tabs as the app starts (docs/DESIGN.md › Structure; ui/AppFlow.kt): the intro on the
     * process's first launch with Settings › Play the intro sound on, then onboarding until it's finished or skipped;
     * a debug build's launch can say otherwise (DebugLaunch: EpicNoIntro, EpicSkipOnboarding and the like).
     */
    private val start = DebugLaunch.start(AppStart.of(settings.introSound, firstLaunch = !launched, settings.onboardingVersion))
        .also { launched = true }
    /** The intro is showing (ui/IntroScreen.kt). */
    var intro by mutableStateOf(start.intro)
        private set
    /** Onboarding is showing (ui/Onboarding.kt): the first run's, or opened again. */
    var onboarding by mutableStateOf(start.onboarding)
        private set
    /** The tab onboarding was opened again from ("Show the welcome again"); null on the first run. */
    var onboardingFrom by mutableStateOf<Tab?>(null)
        private set
    /** The Games heading takes the focus as it shows: the intro or onboarding has just ended. */
    var focusGames by mutableStateOf(false)
        private set
    /** The Help tab's open topic, kept while other tabs (or a game) show. */
    var helpTopic by mutableStateOf<String?>(null)
        private set
    /** The Help tab's topic was opened from elsewhere (Settings › How to play): its heading takes the focus once. */
    var focusHelpTopic by mutableStateOf(false)
        private set
    /** The help sheet is open over the game, on [helpSheetTopic] (null: its list of topics). */
    var helpSheet by mutableStateOf(false)
        private set
    var helpSheetTopic by mutableStateOf<String?>(null)
        private set
    /** The tab showing (Games as the app starts); a game is shown over the tabs, full screen. */
    var tab by mutableStateOf(Tab.GAMES)
        private set
    /** The game whose packs the store sheet shows, if it's open. */
    var storeFor by mutableStateOf<GameInfo?>(null)
        private set
    var game by mutableStateOf<GameController?>(null)
        private set
    /** Bumped on the way back to the list, so it shows which games can be carried on. */
    var visits by mutableIntStateOf(0)
        private set
    /** The game whose map is loading (a big map takes a moment: it loads away from the screen's thread). */
    var opening by mutableStateOf<GameInfo?>(null)
        private set
    /** Something to tell the player: a game that couldn't be opened, or went wrong and stopped. */
    var notice by mutableStateOf<String?>(null)
    /** Where the Games list is scrolled to: kept while a game is played, and as the list is drawn again. */
    val homeList = LazyGridState()
    /** When the Shop tab last read the purchases (elapsedRealtime), so showing it again soon doesn't ask Play again. */
    private var shopReadAt: Long? = null
    /**
     * Usage data (docs/DESIGN.md › Usage data; analytics/): what the player does in the app, the games
     * (GameController's onEvent) and the shop (Store's), as events of web/analytics/events.json, sent to our server
     * under a random ID while Settings › Privacy › Share usage data is on; nothing is sent on the first run until
     * onboarding, which says so, is over. The release app's; a debug build's only with a server given as it's
     * launched (UsageData.EXTRA), and never in tests. The process's one: its session and queue outlive this model.
     */
    val analytics = UsageData.of(app, sharing = settings.analytics, waitForWelcome = settings.onboardingVersion == 0)
    /** Each game's map (or Nuclear War's clips), with the packs installed when it was loaded (the key names them). */
    private val maps = mutableMapOf<String, Any>()
    /** The open game's key in [maps]: the packs it was loaded with. */
    private var loaded: String? = null
    private var openJob: Job? = null
    /** Whether the app is on screen (MainActivity started): a game that loads while it isn't waits for it. */
    private val shown = MutableStateFlow(false)
    /** The packs' purchases and downloads, from the build's pack server (or a debug launch's, EpicPacksURL). */
    val store = Store(
        app, games, packs, viewModelScope, onInstalled = { installed() }, onEvent = analytics::track,
        packsUrl = DebugLaunch.packsUrl ?: BuildConfig.PACKS_URL,
    ).also { it.start() }
    /**
     * The Wear OS app's link (WearBridge.kt; docs/WEAR_OS.md): the open game's state goes to the watch as it changes,
     * phone to watch, and the watch's buttons come back as the headphones' button and the pause. iOS: AppModel.watch.
     */
    val wear = WearBridge(DataLayerLink(app), Words.of(app)) { game?.let(::GameOnWatch) }

    init {
        // Share usage data turned off (Settings, or onboarding's Turn off): nothing more goes, and what's on the phone
        // is forgotten. Onboarding over: what waited for it goes.
        viewModelScope.launch { snapshotFlow { settings.analytics }.collect { analytics.sharing = it } }
        viewModelScope.launch {
            snapshotFlow { settings.onboardingVersion }.collect { analytics.waitForWelcome = it == 0 }
        }
        // A game reaching an end that a pack bought while it played unlocks: it opens again, with the pack.
        viewModelScope.launch { snapshotFlow { game?.end }.collect { if (it != null) packInstalled() } }
        // Settings' voice speed and music volume reach what's playing at once: the open game's turn, a help page.
        viewModelScope.launch {
            snapshotFlow { settings.voiceSpeed }.collect {
                game?.speedChanged()
                appAudio.speedChanged()
            }
        }
        viewModelScope.launch { snapshotFlow { settings.musicVolume }.collect { game?.musicVolumeChanged() } }
        wear.start(viewModelScope)
    }

    /**
     * Opens a game from the list, or [again] with a pack just installed: that game stays on screen, under the
     * spinner, until the new one is ready.
     */
    fun open(info: GameInfo, again: Boolean = false) {
        if (opening != null) return
        // The game's audio alone from here: the sting, or a help page being read, stops.
        appAudio.stopAll()
        if (!again) close()
        opening = info
        openJob = viewModelScope.launch {
            try {
                val installed = packs.installed(info)
                val key = key(info, installed)
                val play = load(info, key, installed)
                // A game that finished loading after the app was left starts when the app is back.
                shown.first { it }
                opening = null
                close()
                loaded = key
                val dirs = installed.map { it.second }
                // The mic opens by itself as Settings say, by default not with TalkBack on (MicPolicy.kt); the sounds,
                // the voice speed and the time to answer are Settings' too. What happens in it is usage data. It hears
                // with the phone's recogniser, unless a debug build's launch says otherwise (DebugLaunch: a script).
                game = GameController(
                    getApplication(), info, play, saves, dirs, onLeave = ::home,
                    listensByItself = { listensByItself(settings.micAuto, screenReader.on) },
                    onEvent = analytics::track,
                    settings = settings,
                    hearing = DebugLaunch.hearing ?: Hearing.SPEECH,
                ).also { it.open() }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                opening = null
                close()
                // What went wrong goes to the log: the player is told plainly.
                Log.w("AppModel", "couldn't open ${info.id}", e)
                notice = getApplication<Application>().getString(R.string.game_not_opened, info.title)
            }
        }
    }

    /** Back while a game loads: it isn't opened after all. */
    fun cancelOpen() {
        openJob?.cancel()
        opening = null
    }

    /** A game's id and its installed packs, each at the version on the phone: "frootopia+frootopia-stories@1". */
    private fun key(info: GameInfo, installed: List<Pair<PackInfo, File>>) =
        info.id + installed.joinToString("") { (p, _) -> "+${p.id}@${p.version}" }

    /** The game, with its installed packs merged into its map (Nuclear War is code: its clips load like a map). */
    private suspend fun load(info: GameInfo, key: String, installed: List<Pair<PackInfo, File>>): Play {
        val app = getApplication<Application>()
        val loaded = maps[key] ?: withContext(Dispatchers.Default) {
            if (info.id == NuclearWar.ID) {
                NuclearAudio.parse(app.assets.open("${info.id}/clips.json").bufferedReader().use { it.readText() })
            } else {
                GameMap.parse(
                    app.assets.open("${info.id}/map.json").bufferedReader().use { it.readText() },
                    installed.map { (_, dir) -> File(dir, "pack.json").readText() },
                )
            }
        }.also { maps[key] = it }
        return if (loaded is NuclearAudio) NuclearWar(loaded) else Session(loaded as GameMap)
    }

    fun home() {
        game?.failure?.let { notice = it }
        close()
        visits++
        // How the game went (its game_leave, as it closed) goes now.
        analytics.flush()
    }

    /**
     * Shows a tab: picked in the bar or the rail, with Ctrl and its number, or Back (to Games). Leaving the Shop, what
     * the store said there goes.
     */
    fun select(tab: Tab) {
        if (tab == this.tab) return
        if (this.tab == Tab.SHOP) store.sheet(open = false)
        // Leaving Help, a page being read stops (the topic stays open for the way back).
        if (this.tab == Tab.HELP) stopHelpClip()
        this.tab = tab
        event(Events.tabView(tab))
        if (tab == Tab.SHOP) event(Events.shopView(ShopSource.TAB))
    }

    /**
     * The Shop tab is showing: it reads the purchases again (a pack bought on another phone downloads, a payment
     * approved shows), at most once a minute however often it's shown (docs/DESIGN.md › Shop).
     */
    fun shopShown() {
        val now = SystemClock.elapsedRealtime()
        shopReadAt?.let { if (now - it < SHOP_READ_MS) return }
        shopReadAt = now
        store.sheet(open = true)
    }

    /**
     * The store sheet for a game's packs (null: closed), opened [from] a game's card, its menu or a locked end. Opening
     * it pauses the game and reads the purchases again.
     */
    fun showStore(info: GameInfo?, from: ShopSource = ShopSource.CARD) {
        if (info != null && opening != null) return
        storeFor = info
        store.sheet(open = info != null)
        if (info != null) {
            event(Events.shopView(from))
            game?.takeIf { it.end == null }?.pause()
        } else {
            packInstalled()
        }
    }

    /**
     * Settings › Sound and voice › Play a sample: a line in the games' host's voice, at the speed chosen. With TalkBack
     * on it waits a moment, so TalkBack's own feedback for the tap comes first (as Help's Listen does).
     */
    fun playSample() = afterScreenReader { appAudio.previewVoiceSpeed() }

    /** Settings › Listening sounds or Vibrate when listening starts, turned on: the sound and tick as the mic opens. */
    fun previewCue() = afterScreenReader { appAudio.previewCue() }

    /** Settings › Play the intro sound, turned on: the sting, as the app will start with it. */
    fun previewIntro() = afterScreenReader { appAudio.previewIntro() }

    /** Settings › Music volume, a step picked: a few seconds of a game's music at that volume (Off: silence). */
    fun previewMusic() = afterScreenReader { appAudio.previewMusic() }

    /** Runs [then] now, or with TalkBack on a moment later, once TalkBack has said what the tap did. */
    private fun afterScreenReader(then: () -> Unit) {
        if (!screenReader.on) {
            then()
            return
        }
        viewModelScope.launch {
            delay(SCREEN_READER_PAUSE_MS)
            then()
        }
    }

    /**
     * A pack was installed (Store): the success sound for a player watching it arrive, on the Shop or in the store
     * sheet (docs/DESIGN.md › Shop); one installing out of sight (a retry, a restore as the app comes back) is quiet.
     * Then a game waiting at an end for it opens again ([packInstalled]).
     */
    private fun installed() {
        if (shown.value && ((tab == Tab.SHOP && game == null) || storeFor != null)) appAudio.playSuccess()
        packInstalled()
    }

    // ----- The intro (docs/DESIGN.md › Intro) -----

    private var introStarted = false
    private var introSkipped = false

    /**
     * The intro is on screen: its sting starts now, or with TalkBack on a moment later, once TalkBack has read the
     * intro's name ([IntroTimes]). The intro ends a moment after the sting does, or with no sting (none in the build,
     * another app's music playing) after a while. Once, however often it's asked (the activity made again as a tablet
     * turns): the sting's end comes here, not to a screen that may have gone.
     */
    fun startIntro() {
        if (!intro || introStarted) return
        introStarted = true
        viewModelScope.launch {
            val shown = SystemClock.elapsedRealtime()
            val since = { SystemClock.elapsedRealtime() - shown }
            // The manifest (which sting) is still being read as the app starts: waited for away from the screen's
            // thread, so the intro never stops drawing for it.
            withContext(Dispatchers.Default) { appAudio.manifest }
            if (screenReader.on) delay(IntroTimes.SCREEN_READER_DELAY - since())
            if (!intro) return@launch                       // skipped meanwhile: no sting at all
            if (!appAudio.playIntro(::stingEnded)) {
                delay(IntroTimes.WITHOUT_STING - since())
                endIntro(skipped = false)
            }
        }
    }

    /** The sting has played to its end (the intro ends a moment later), or faded out as the intro was skipped. */
    private fun stingEnded() {
        if (introSkipped) {
            endIntro(skipped = true)
        } else {
            viewModelScope.launch {
                delay(IntroTimes.AFTER_STING)
                endIntro(skipped = false)
            }
        }
    }

    /** A tap on the intro, its TalkBack action, Escape, Space or Back: the sting fades out quickly, and it ends. */
    fun skipIntro() {
        if (!intro || introSkipped) return
        introSkipped = true
        if (appAudio.introPlaying) appAudio.skipIntro() else endIntro(skipped = true)
    }

    /** Onboarding next, on the first run; or Games, with the focus on its heading. */
    private fun endIntro(skipped: Boolean) {
        if (!intro) return
        intro = false
        event(Events.introFinished(skipped))
        if (!onboarding) focusGames = true
    }

    // ----- Onboarding (docs/DESIGN.md › Onboarding) -----

    /**
     * "Show the welcome again", in Help or Settings: onboarding again, from its first page (the welcome isn't read by
     * itself this time); skipped, it comes back to this tab.
     */
    fun showWelcome() {
        appAudio.stopClip()
        onboardingFrom = tab
        onboarding = true
    }

    /**
     * Onboarding has ended, [completed] (Start playing) or skipped: it isn't shown by itself again
     * (settings.onboardingVersion), and the player goes to Games with the focus on its heading, or, skipping onboarding
     * opened again, back to the tab it came from (ui/AppFlow.kt's tabAfterOnboarding).
     */
    fun onboardingDone(completed: Boolean) {
        if (!onboarding) return
        settings.onboardingVersion = ONBOARDING_VERSION
        val to = tabAfterOnboarding(completed, onboardingFrom)
        onboarding = false
        onboardingFrom = null
        event(Events.onboardingFinished(completed))
        select(to)
        if (to == Tab.GAMES) focusGames = true
    }

    /** The Games heading has taken the focus ([focusGames]). */
    fun gamesFocused() {
        focusGames = false
    }

    /** What the player said to Android's microphone question, asked by onboarding (for the usage data). */
    fun onboardingMicAnswered(granted: Boolean) = event(Events.micPermission(granted, MicAsked.ONBOARDING))

    // ----- Help (docs/DESIGN.md › Help) -----

    /** The Help tab's topic opened ([id]), or closed (null): a page being read stops. Which one is never sent. */
    fun showTopic(id: String?) {
        if (id == helpTopic) return
        stopHelpClip()
        helpTopic = id
        if (id != null) event(Events.helpViewed(HelpSource.TAB))
    }

    /**
     * Settings › How to play: the Help tab, on playing with your voice (as a game's How to play opens), its heading
     * taking the focus.
     */
    fun howToPlay() {
        select(Tab.HELP)
        showTopic(HOW_TO_PLAY)
        focusHelpTopic = true
    }

    /** The Help topic opened from elsewhere has taken the focus ([focusHelpTopic]). */
    fun helpTopicFocused() {
        focusHelpTopic = false
    }

    /**
     * A game's How to play (its menu, or the pause): the help sheet, on playing with your voice, over the game, which
     * waits for it, paused (at an end there's nothing to pause).
     */
    fun openHelpSheet() {
        game?.takeIf { it.end == null && !it.paused }?.pause()
        helpSheetTopic = HOW_TO_PLAY
        helpSheet = true
        event(Events.helpViewed(HelpSource.GAME))
    }

    /** In the help sheet, a topic opened ([id]) or the list again (null): a page being read stops. */
    fun showSheetTopic(id: String?) {
        stopHelpClip()
        helpSheetTopic = id
        if (id != null) event(Events.helpViewed(HelpSource.GAME))
    }

    /** The help sheet has closed: what it was reading stops; the game stays paused, for Carry on. */
    fun closeHelpSheet() {
        stopHelpClip()
        helpSheet = false
        helpSheetTopic = null
    }

    /** A help page being read aloud stops (not the welcome, nor a sample). */
    private fun stopHelpClip() {
        if (appAudio.clipPlaying is AppClip.Help) appAudio.stopClip()
    }

    /**
     * Settings › Privacy › Delete my usage data: the server is asked to delete everything this phone sent under its
     * random ID, then the app forgets that ID (and what's waiting to be sent); still sharing, the next event makes a
     * new one. With usage data off, the ID is forgotten already: nothing can be found to delete.
     */
    suspend fun deleteUsageData(): UsageDeletion = analytics.delete()

    /** What the player said to the microphone's question, asked from Settings (for the usage data). */
    fun micAnswered(granted: Boolean) = event(Events.micPermission(granted, MicAsked.SETTINGS))

    /** Usage data: something happened ([analytics]). */
    private fun event(e: Event) = analytics.track(e)

    /**
     * A pack was installed, the game reached an end, or the store sheet closed: a game waiting at an end that its own
     * pack, now installed, unlocks opens again with it. A chapter's end comes back with "Next chapter"; the Werewolf's
     * last ends start again with the new stories, as "Play again" does. Other games and other ends are left alone, and
     * nothing happens under the store sheet.
     */
    fun packInstalled() {
        val g = game ?: return
        val e = g.end ?: return
        if (opening != null || storeFor != null) return
        val pack = g.info.packs.firstOrNull { it.id == e.locked } ?: return
        if (!packs.isInstalled(pack) || key(g.info, packs.installed(g.info)) == loaded) return
        open(g.info, again = true)
    }

    /**
     * The app coming on screen or going: a game loading waits for it; coming back reads the purchases again. For the
     * usage data it's the app opened or put away, unless the screen is only being [remade] (a tablet turning).
     */
    fun onScreen(on: Boolean, remade: Boolean = false) {
        shown.value = on
        if (on) {
            analytics.foreground()
            viewModelScope.launch { store.restore() }
        } else if (!remade) {
            analytics.background()
        }
    }

    private fun close() {
        if (helpSheet) closeHelpSheet()
        game?.close()
        game = null
        loaded = null
    }

    override fun onCleared() {
        close()
        wear.stop()
        store.close()
        screenReader.close()
        appAudio.close()
    }

    private companion object {
        /** The Shop tab reads the purchases again at most this often (ms). */
        const val SHOP_READ_MS = 60_000L
        /** With TalkBack on, a sample waits this long after its tap (docs/DESIGN.md › Help: Listen's 400 ms). */
        const val SCREEN_READER_PAUSE_MS = 400L
        /** The help topic How to play opens: "Playing with your voice" (tools/app_text.toml's ids are fixed). */
        const val HOW_TO_PLAY = "voice"
        /**
         * The process has launched the app once: its intro, if it had one, is over. Another launch while the process
         * lives (the app left with Back, and opened again) has none.
         */
        var launched = false
    }
}

/** The smallest width (dp) from which a screen is a large one (a tablet, a foldable open): it turns any way. */
private const val LARGE_SCREEN_DP = 600

/** How long the system's splash takes to fade out when no intro follows it (ms). */
private const val SPLASH_FADE_MS = 250L

/** The app's screens, in the player's theme (EpicTheme: Settings › Appearance and the phone's own settings). */
@Composable
fun App(model: AppModel) {
    EpicTheme(model.settings, screenReader = model.screenReader.on) {
        Screens(model)
    }
}

/**
 * The way in, then the app (docs/DESIGN.md › Structure): the intro (after the system's splash, once per process),
 * onboarding (the first run, or opened again), then the tabs, or the game over them, full screen; a game loading; the
 * store sheet, over a game or the Games tab; the help sheet over a game; and anything to tell the player.
 */
@Composable
private fun Screens(model: AppModel) {
    val game = model.game
    val opening = model.opening
    // Each tab's place (how far it's scrolled, Settings › Licences open) is kept while another shows, or a game, or
    // onboarding opened again.
    val tabs = rememberSaveableStateHolder()
    // The test tags (docs/DESIGN.md's identifiers) as resource ids, so UI tests and the screenshot scripts find them.
    Box(Modifier.fillMaxSize().background(EpicTheme.colors.background).semantics { testTagsAsResourceId = true }) {
        when {
            model.intro -> {
                // Back skips it, as a tap does.
                BackHandler(onBack = model::skipIntro)
                IntroScreen(onSkip = model::skipIntro)
                LaunchedEffect(Unit) { model.startIntro() }
            }
            model.onboarding -> Onboarding(
                model.settings, model.appAudio.manifest, model.appAudio,
                reopened = model.onboardingFrom != null,
                onMicAnswer = model::onboardingMicAnswered,
                onDone = model::onboardingDone,
            )
            else -> {
                // While a game loads, what's under the spinner takes no touches and TalkBack doesn't read it.
                Box(Modifier.fillMaxSize().then(if (opening != null) Modifier.clearAndSetSemantics {} else Modifier)) {
                    if (game == null) {
                        MainTabs(model.tab, model::select) { tab ->
                            tabs.SaveableStateProvider(tab.key) { TabScreen(model, tab) }
                        }
                    } else {
                        BackHandler { game.leave() }
                        GameScreen(
                            game,
                            onStore = { from -> model.showStore(game.info, from) },
                            onHelp = model::openHelpSheet,
                        )
                    }
                }
                if (opening != null) {
                    BackHandler { model.cancelOpen() }
                    Opening(opening.title)
                }
            }
        }
    }
    model.storeFor?.let { StoreSheet(it, model.store, model.packs) { model.showStore(null) } }
    if (model.helpSheet && game != null) {
        HelpSheet(model.helpPages, model.appAudio, model.helpSheetTopic, model::showSheetTopic, model::closeHelpSheet)
    }
    model.notice?.let { text ->
        AlertDialog(
            onDismissRequest = { model.notice = null },
            confirmButton = {
                EpicButton(stringResource(R.string.ok), { model.notice = null }, Modifier.testTag("notice-ok"),
                    kind = ButtonKind.Text)
            },
            title = { Text(stringResource(R.string.notice_title)) },
            text = { Text(text) },
            modifier = Modifier.windowTestTags(),
        )
    }
}

/** A tab's screen, on the model's state. */
@Composable
private fun TabScreen(model: AppModel, tab: Tab) {
    val activity = LocalContext.current.findActivity()
    when (tab) {
        // Drawn again on the way back to the list and when a pack is installed, scrolled as it was.
        Tab.GAMES -> key(model.visits, model.store.installs) {
            HomeScreen(
                model.homeList, model.games, model.saves::inProgress, model.packs::isInstalled, model::open,
                onStore = { model.showStore(it, ShopSource.CARD) },
                focusHeading = model.focusGames,
                onHeadingFocused = model::gamesFocused,
            )
        }
        Tab.SHOP -> ShopScreen(
            model.games, model.store, model.packs::isInstalled,
            onBuy = { pack -> activity?.let { model.store.buy(it, pack) } },
            onShown = model::shopShown,
        )
        Tab.HELP -> HelpScreen(
            model.helpPages, model.appAudio, model.helpTopic, model::showTopic, model::showWelcome,
            focusTopic = model.focusHelpTopic,
            onTopicFocused = model::helpTopicFocused,
        )
        Tab.SETTINGS -> SettingsScreen(
            model.settings,
            onPlaySample = model::playSample,
            onPreviewCue = model::previewCue,
            onPreviewIntro = model::previewIntro,
            onPreviewMusic = model::previewMusic,
            onHowToPlay = model::howToPlay,
            onShowWelcome = model::showWelcome,
            onDeleteUsageData = model::deleteUsageData,
            onMicAnswer = model::micAnswered,
        )
    }
}

/**
 * A game loading, over what was there (the scrim hides it: solid, as words showing through are hard to read): a
 * spinner and "Opening The Werewolf", which TalkBack says as it appears (iOS posts it as an announcement).
 */
@Composable
private fun Opening(title: String) {
    val c = EpicTheme.colors
    Box(
        Modifier.fillMaxSize().background(c.scrim).pointerInput(Unit) {},
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier.padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            CircularProgressIndicator(color = c.primary)
            Text(
                stringResource(R.string.opening_game, title),
                Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                style = EpicTheme.type.label,
                color = c.text,
                textAlign = TextAlign.Center,
            )
        }
    }
}
