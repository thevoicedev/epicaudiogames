package com.epicaudiogames.app

import android.app.Application
import android.os.Bundle
import android.graphics.Color
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.epicaudiogames.app.ui.EpicTheme
import com.epicaudiogames.app.ui.GameScreen
import com.epicaudiogames.app.ui.HomeScreen
import com.epicaudiogames.app.ui.StoreSheet
import com.epicaudiogames.engine.GameMap
import com.epicaudiogames.engine.Play
import com.epicaudiogames.engine.Session
import com.epicaudiogames.engine.nuclear.NuclearAudio
import com.epicaudiogames.engine.nuclear.NuclearWar
import java.io.File

class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // White status and navigation bar icons, over the dark header and the blue backdrop.
        enableEdgeToEdge(SystemBarStyle.dark(Color.TRANSPARENT), SystemBarStyle.dark(Color.TRANSPARENT))
        setContent { EpicTheme { App(model) } }
    }

    override fun onStart() {
        super.onStart()
        model.onScreen(true)
    }

    override fun onStop() {
        super.onStop()
        model.onScreen(false)
    }
}

/** The game list, and the game being played (one at a time). */
class AppModel(app: Application) : AndroidViewModel(app) {
    val games = Catalog.load(app.assets)
    val saves = Saves(app)
    val packs = Packs(app)
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
    /** Where the list is scrolled to: kept while a game is played, and as the list is drawn again. */
    val homeList = LazyListState()
    /** Each game's map (or Nuclear War's clips), with the packs installed when it was loaded (the key names them). */
    private val maps = mutableMapOf<String, Any>()
    /** The open game's key in [maps]: the packs it was loaded with. */
    private var loaded: String? = null
    private var openJob: Job? = null
    /** Whether the app is on screen (MainActivity started): a game that loads while it isn't waits for it. */
    private val shown = MutableStateFlow(false)
    val store = Store(app, games, packs, viewModelScope, onInstalled = { packInstalled() }).also { it.start() }

    init {
        // A game reaching an end that a pack bought while it played unlocks: it opens again, with the pack.
        viewModelScope.launch { snapshotFlow { game?.end }.collect { if (it != null) packInstalled() } }
    }

    /**
     * Opens a game from the list, or [again] with a pack just installed: that game stays on screen, under the
     * spinner, until the new one is ready.
     */
    fun open(info: GameInfo, again: Boolean = false) {
        if (opening != null) return
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
                game = GameController(getApplication(), info, play, saves, dirs, onLeave = ::home).also { it.open() }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                opening = null
                close()
                // What went wrong goes to the log: the player is told plainly.
                Log.w("AppModel", "couldn't open ${info.id}", e)
                notice = "${info.title} couldn't be opened."
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
    }

    /** The store sheet for a game's packs (null: closed). Opening it pauses the game and reads the purchases again. */
    fun showStore(info: GameInfo?) {
        if (info != null && opening != null) return
        storeFor = info
        store.sheet(open = info != null)
        if (info != null) {
            game?.takeIf { it.end == null }?.pause()
        } else {
            packInstalled()
        }
    }

    /**
     * A pack was installed, the game reached an end, or the store sheet closed: a game waiting at an end that its own
     * pack, now installed, unlocks opens again with it. A chapter's end comes back with NEXT CHAPTER; the Werewolf's
     * last ends start again with the new stories, as PLAY AGAIN does. Other games and other ends are left alone, and
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

    /** The app coming on screen or going: a game loading waits for it; coming back reads the purchases again. */
    fun onScreen(on: Boolean) {
        shown.value = on
        if (on) viewModelScope.launch { store.restore() }
    }

    private fun close() {
        game?.close()
        game = null
        loaded = null
    }

    override fun onCleared() {
        close()
        store.close()
    }
}

@Composable
fun App(model: AppModel) {
    val game = model.game
    val loading = model.opening != null
    // While a game loads, what's under the spinner takes no touches and TalkBack doesn't read it.
    Box(Modifier.fillMaxSize().then(if (loading) Modifier.clearAndSetSemantics {} else Modifier)) {
        if (game == null) {
            // Drawn again on the way back to the list and when a pack is installed, scrolled as it was.
            key(model.visits, model.store.installs) {
                HomeScreen(model.homeList, model.games, model.saves::inProgress, model.packs::isInstalled, model::open,
                    model::showStore)
            }
        } else {
            BackHandler { game.leave() }
            GameScreen(game, onStore = { model.showStore(game.info) })
        }
    }
    if (loading) {
        BackHandler { model.cancelOpen() }
        Box(
            Modifier.fillMaxSize()
                .background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.35f))
                .pointerInput(Unit) {}
                .semantics {
                    contentDescription = "Loading"
                    liveRegion = LiveRegionMode.Polite
                },
            contentAlignment = Alignment.Center,
        ) {
            CircularProgressIndicator(color = androidx.compose.ui.graphics.Color.White)
        }
    }
    model.storeFor?.let { StoreSheet(it, model.store, model.packs) { model.showStore(null) } }
    model.notice?.let { text ->
        AlertDialog(
            onDismissRequest = { model.notice = null },
            confirmButton = { TextButton(onClick = { model.notice = null }) { Text("OK") } },
            title = { Text("Sorry!") },
            text = { Text(text) },
        )
    }
}
