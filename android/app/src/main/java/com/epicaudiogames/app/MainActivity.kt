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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewmodel.compose.viewModel
import com.epicaudiogames.app.ui.EpicTheme
import com.epicaudiogames.app.ui.GameScreen
import com.epicaudiogames.app.ui.HomeScreen
import com.epicaudiogames.engine.GameMap

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
    var game by mutableStateOf<GameController?>(null)
        private set
    /** Bumped on the way back to the list, so it shows which games can be carried on. */
    var visits by mutableIntStateOf(0)
        private set

    fun open(info: GameInfo) {
        close()
        val app = getApplication<Application>()
        val map = GameMap.parse(app.assets.open("${info.id}/map.json").bufferedReader().use { it.readText() })
        game = GameController(app, info, map, saves, onLeave = ::home).also { it.open() }
    }

    fun home() {
        close()
        visits++
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
    if (game == null) {
        key(model.visits) { HomeScreen(model.games, model.saves::inProgress, model::open) }
    } else {
        BackHandler { game.leave() }
        GameScreen(game)
    }
}
