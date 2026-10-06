package com.epicaudiogames.app.ui

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.epicaudiogames.app.GameInfo
import com.epicaudiogames.app.PackInfo

/** The game list: a card per game, with its cover, its description, what's free, and its packs. */
@Composable
fun HomeScreen(
    games: List<GameInfo>,
    inProgress: (String) -> Boolean,
    installed: (PackInfo) -> Boolean,
    onOpen: (GameInfo) -> Unit,
    onStore: (GameInfo) -> Unit,
) {
    Backdrop(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            HeaderBar("EPIC AUDIO GAMES")
            LazyColumn(
                Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.navigationBars),
                contentPadding = PaddingValues(16.dp, 14.dp, 16.dp, 28.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                item {
                    OutlinedText(
                        "Put on your headphones, listen, and answer out loud!",
                        Modifier.fillMaxWidth().padding(horizontal = 4.dp),
                        size = 19.sp,
                        maxLines = 3,
                    )
                }
                items(games, key = { it.id }) { game ->
                    GameCard(game, inProgress(game.id), installed, onStore = { onStore(game) }) { onOpen(game) }
                }
            }
        }
    }
}

@Composable
private fun GameCard(
    game: GameInfo,
    continuing: Boolean,
    installed: (PackInfo) -> Boolean,
    onStore: () -> Unit,
    onClick: () -> Unit,
) {
    Card(
        onClick = onClick,
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = Palette.card),
        elevation = CardDefaults.cardElevation(defaultElevation = 6.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Box {
            val cover = rememberAssetImage("${game.id}/cover.jpg")
            if (cover != null) {
                Image(cover, contentDescription = null, contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f))
            } else {
                Box(Modifier.fillMaxWidth().aspectRatio(16f / 9f).background(Palette.headerBottom))
            }
            if (continuing) {
                Pill("CONTINUE", Palette.gold, Palette.ink, Modifier.align(Alignment.TopEnd).padding(10.dp))
            }
        }
        Column(Modifier.padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 16.dp)) {
            Text(game.title, style = MaterialTheme.typography.titleLarge, color = Palette.title)
            Spacer(Modifier.height(4.dp))
            Text(game.blurb, style = MaterialTheme.typography.bodyMedium, color = Palette.ink.copy(alpha = 0.85f))
            Spacer(Modifier.height(10.dp))
            // Its packs: one to get (it opens the store), or all of them in.
            val toGet = game.packs.firstOrNull { !installed(it) }
            if (game.packs.isNotEmpty()) {
                Pill(if (toGet != null) "+ ${toGet.title.uppercase()}" else "ALL PACKS INSTALLED", Palette.gold, Palette.ink,
                    Modifier.clickable(onClick = onStore))
                Spacer(Modifier.height(8.dp))
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (game.free.isNotEmpty()) Pill(game.free.uppercase(), Palette.headerLine, Palette.title)
                Spacer(Modifier.weight(1f))
                Pill(if (continuing) "CARRY ON" else "PLAY", Palette.yes, Color.White, big = true)
            }
        }
    }
}

@Composable
fun Pill(text: String, background: Color, color: Color, modifier: Modifier = Modifier, big: Boolean = false) {
    Text(
        text,
        color = color,
        fontSize = if (big) 18.sp else 13.sp,
        fontFamily = Lilita,
        textAlign = TextAlign.Center,
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(background)
            .padding(horizontal = if (big) 22.dp else 12.dp, vertical = if (big) 8.dp else 5.dp),
    )
}

/** An image from the app's assets (a game's cover), decoded once. */
@Composable
fun rememberAssetImage(path: String): ImageBitmap? {
    val context = LocalContext.current
    return remember(path) {
        runCatching { context.assets.open(path).use { BitmapFactory.decodeStream(it)?.asImageBitmap() } }.getOrNull()
    }
}
