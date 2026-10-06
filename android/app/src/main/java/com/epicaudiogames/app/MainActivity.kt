package com.epicaudiogames.app

import android.app.Application
import android.os.Bundle
import android.graphics.Color
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.Dispatchers
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
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // White status and navigation bar icons, over the dark header and the blue backdrop.
        enableEdgeToEdge(SystemBarStyle.dark(Color.TRANSPARENT), SystemBarStyle.dark(Color.TRANSPARENT))
        setContent { EpicTheme { App() } }
    }
}

/** The game list, and the game being played (one at a time). */
class AppModel(app: Application) : AndroidViewModel(app) {
    val games = Catalog.load(app.assets)
    val saves = Saves(app)
    val packs = Packs(app)
    val store = Store(app, games, packs, viewModelScope).also { it.start() }
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
    /** Each game's map (or Nuclear War's clips), with the packs installed when it was loaded (the key names them). */
    private val maps = mutableMapOf<String, Any>()

    fun open(info: GameInfo) {
        if (opening != null) return
        close()
        opening = info
        viewModelScope.launch {
            val app = getApplication<Application>()
            val installed = packs.installed(info)
            val key = info.id + installed.joinToString("") { (p, _) -> "+${p.id}@${p.version}" }
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
            // Nuclear War is written in code, its clips loaded like a map; the other games are maps.
            val play: Play = if (loaded is NuclearAudio) NuclearWar(loaded) else Session(loaded as GameMap)
            opening = null
            game = GameController(app, info, play, saves, installed.map { it.second }, onLeave = ::home).also { it.open() }
        }
    }

    fun home() {
        close()
        visits++
    }

    fun showStore(game: GameInfo?) {
        storeFor = game
        if (game != null) viewModelScope.launch { store.restore() }
    }

    /** A pack was installed: a game waiting at the end its pack unlocks is opened again, with the pack. */
    fun packInstalled() {
        val g = game ?: return
        if (g.end != null) open(g.info)
    }

    private fun close() {
        game?.close()
        game = null
    }

    override fun onCleared() = close()
}

@Composable
fun App(model: AppModel = viewModel()) {
    val game = model.game
    val installs = model.store.installs
    LaunchedEffect(installs) { if (installs > 0) model.packInstalled() }
    if (game == null) {
        key(model.visits, installs) {
            HomeScreen(model.games, model.saves::inProgress, model.packs::isInstalled, model::open, model::showStore)
        }
        if (model.opening != null) {
            Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.35f)),
                contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = androidx.compose.ui.graphics.Color.White)
            }
        }
    } else {
        BackHandler { game.leave() }
        GameScreen(game, onStore = { model.showStore(game.info) })
    }
    model.storeFor?.let { StoreSheet(it, model.store, model.packs) { model.showStore(null) } }
}
