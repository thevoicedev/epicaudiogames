package com.epicaudiogames.app.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.epicaudiogames.app.FeedItem
import com.epicaudiogames.app.GameController

/**
 * The game: the talking circle (the game's picture, pulsing while it speaks, ringed while it listens), the
 * transcript as it's spoken, and the answers: buttons, typing and the mic. At an end, the end panel.
 */
@Composable
fun GameScreen(game: GameController) {
    val context = LocalContext.current
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        game.micAllowed = granted
        if (granted) game.listen()
    }
    LaunchedEffect(game) {
        val granted = ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
        game.micAllowed = granted
        if (!granted && game.micWorks) permission.launch(Manifest.permission.RECORD_AUDIO)
    }
    // The screen stays on while a game plays; leaving the app pauses it.
    val view = LocalView.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(game) {
        view.keepScreenOn = true
        val observer = LifecycleEventObserver { _, event -> if (event == Lifecycle.Event.ON_STOP) game.pause() }
        lifecycle.addObserver(observer)
        onDispose {
            view.keepScreenOn = false
            lifecycle.removeObserver(observer)
        }
    }

    Backdrop(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize().imePadding()) {
            var menu by remember { mutableStateOf(false) }
            HeaderBar(game.info.title, onBack = game::leave) {
                IconButton(onClick = { menu = true }) {
                    Icon(Icons.Default.MoreVert, contentDescription = "More", tint = Color.White)
                }
                DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                    DropdownMenuItem(text = { Text("Start again") }, onClick = { menu = false; game.startAgain() })
                }
            }
            TalkingCircle(game)
            Feed(game, Modifier.weight(1f))
            if (game.end != null) EndPanel(game) else Answers(game)
        }
        if (game.paused) Paused(game)
    }
}

@Composable
private fun TalkingCircle(game: GameController) {
    val pulse by rememberInfiniteTransition(label = "pulse").animateFloat(
        initialValue = 1f, targetValue = 1.06f,
        animationSpec = infiniteRepeatable(tween(480), RepeatMode.Reverse), label = "pulse",
    )
    val scale = if (game.speaking) pulse else 1f
    val ring = when {
        game.listening -> Palette.listen
        game.speaking -> Palette.gold
        else -> Color.White.copy(alpha = 0.7f)
    }
    val ringWidth = if (game.listening) (4 + 10 * game.level).dp else 4.dp
    Column(
        Modifier.fillMaxWidth().padding(top = 14.dp, bottom = 6.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier.size(146.dp).clickable(remember { MutableInteractionSource() }, indication = null) {
                if (game.speaking) game.skip() else game.mic()
            },
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(146.dp).scale(scale).border(ringWidth, ring, CircleShape))
            val cover = rememberAssetImage("${game.info.id}/cover.jpg")
            if (cover != null) {
                Image(cover, contentDescription = null, contentScale = ContentScale.Crop,
                    modifier = Modifier.size(126.dp).scale(scale).clip(CircleShape))
            }
        }
        Spacer(Modifier.height(8.dp))
        val status = when {
            game.paused -> "Paused"
            game.listening && game.partial.isNotEmpty() -> "“${game.partial}”"
            game.listening -> "Listening…"
            game.speaking -> "Tap the picture to skip"
            game.end != null -> ""
            game.ask != null -> if (game.micAllowed && game.micWorks) "Your turn! Tap the mic to talk" else "Your turn!"
            else -> ""
        }
        OutlinedText(status, size = 18.sp, maxLines = 2)
    }
}

@Composable
private fun Feed(game: GameController, modifier: Modifier) {
    val state = rememberLazyListState()
    LaunchedEffect(game.feed.size) {
        if (game.feed.isNotEmpty()) state.animateScrollToItem(game.feed.size - 1)
    }
    LazyColumn(
        modifier.fillMaxWidth(),
        state = state,
        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        itemsIndexed(game.feed) { i, item ->
            when (item) {
                is FeedItem.Spoken -> Spoken(item, if (i == game.activeEntry) game.activeChars else null)
                is FeedItem.Reply -> Reply(item.text)
                is FeedItem.Note -> OutlinedText(item.text, Modifier.fillMaxWidth().padding(vertical = 4.dp), size = 16.sp)
            }
        }
    }
}

/** A line of the game. While it's being spoken, the words still to come are paler. */
@Composable
private fun Spoken(item: FeedItem.Spoken, saidChars: Int?) {
    Column(
        Modifier
            .widthIn(max = 340.dp)
            .clip(RoundedCornerShape(topStart = 4.dp, topEnd = 18.dp, bottomEnd = 18.dp, bottomStart = 18.dp))
            .background(Palette.card)
            .padding(horizontal = 14.dp, vertical = 9.dp),
    ) {
        if (item.who != "NARRATOR") {
            Text(item.name.uppercase(), color = speakerColor(item.who), fontFamily = Lilita, fontSize = 13.sp)
        }
        val text = buildAnnotatedString {
            if (saidChars == null) {
                append(item.text)
            } else {
                val cut = item.text.indexOf(' ', saidChars).let { if (it < 0) item.text.length else it }
                append(item.text.substring(0, cut))
                withStyle(SpanStyle(color = Palette.ink.copy(alpha = 0.35f))) { append(item.text.substring(cut)) }
            }
        }
        Text(text, style = MaterialTheme.typography.bodyLarge, color = Palette.ink)
    }
}

@Composable
private fun Reply(text: String) {
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterEnd) {
        Text(
            text,
            style = MaterialTheme.typography.bodyLarge,
            color = Palette.ink,
            modifier = Modifier
                .widthIn(max = 300.dp)
                .clip(RoundedCornerShape(topStart = 18.dp, topEnd = 4.dp, bottomEnd = 18.dp, bottomStart = 18.dp))
                .background(Palette.reply)
                .padding(horizontal = 14.dp, vertical = 9.dp),
        )
    }
}

/** The answer buttons, the text box and the mic. */
@Composable
private fun Answers(game: GameController) {
    Column(
        Modifier
            .fillMaxWidth()
            .background(Color.White.copy(alpha = 0.22f))
            .windowInsetsPadding(WindowInsets.navigationBars)
            .padding(10.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        val buttons = game.ask?.buttons.orEmpty().take(4)
        if (buttons.isNotEmpty()) {
            val stacked = buttons.any { it.label.length > 10 }
            if (stacked) {
                buttons.forEach { b -> AnswerButton(b.label, Modifier.fillMaxWidth()) { game.answer(b.value) } }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    buttons.forEach { b -> AnswerButton(b.label, Modifier.weight(1f)) { game.answer(b.value) } }
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            var text by rememberSaveable { mutableStateOf("") }
            val send = {
                if (text.isNotBlank()) game.answer(text)
                text = ""
            }
            TextField(
                value = text,
                onValueChange = { text = it },
                placeholder = { Text("Type an answer", fontFamily = Lilita) },
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = { send() }),
                shape = RoundedCornerShape(24.dp),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.White, unfocusedContainerColor = Color.White,
                    focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent,
                ),
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = send) {
                Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send", tint = Color.White)
            }
            val canTalk = game.micAllowed && game.micWorks
            Box(
                Modifier
                    .size(54.dp)
                    .clip(CircleShape)
                    .background(if (game.listening) Palette.listen else if (canTalk) Palette.choice else Color.Gray)
                    .clickable(enabled = game.micAllowed) { game.mic() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(if (canTalk) Icons.Default.Mic else Icons.Default.MicOff, contentDescription = "Talk", tint = Color.White,
                    modifier = Modifier.size(28.dp))
            }
        }
    }
}

@Composable
private fun AnswerButton(label: String, modifier: Modifier, onClick: () -> Unit) {
    val color = when (label.lowercase()) {
        "yes" -> Palette.yes
        "no" -> Palette.no
        else -> Palette.choice
    }
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(containerColor = color),
        shape = RoundedCornerShape(16.dp),
        contentPadding = PaddingValues(vertical = 12.dp, horizontal = 10.dp),
        modifier = modifier,
    ) {
        Text(label.uppercase(), fontFamily = Lilita, fontSize = 19.sp, color = Color.White, textAlign = TextAlign.Center)
    }
}

/** The end: what was reached, and what next. */
@Composable
private fun EndPanel(game: GameController) {
    val end = game.end ?: return
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(topStart = 26.dp, topEnd = 26.dp))
            .background(Palette.card)
            .windowInsetsPadding(WindowInsets.navigationBars)
            .padding(18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        val heading = when (end.kind) {
            "chapter" -> "CHAPTER COMPLETE!"
            "gameover" -> "GAME OVER"
            else -> "THE END"
        }
        OutlinedText(heading, size = 30.sp, fill = Palette.gold)
        Text(end.title, style = MaterialTheme.typography.titleLarge, color = Palette.title, textAlign = TextAlign.Center)
        if (end.locked != null && !game.canGoOn) {
            Text("What happens next is coming soon, in a story pack.", style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center)
        }
        if (game.canGoOn) EndButton("NEXT CHAPTER", Palette.yes) { game.nextChapter() }
        EndButton(if (end.kind == "gameover") "TRY AGAIN" else "PLAY AGAIN", Palette.choice) { game.playAgain() }
        EndButton("BACK TO GAMES", Palette.headerBottom) { game.leave() }
    }
}

@Composable
private fun EndButton(label: String, color: Color, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(containerColor = color),
        shape = RoundedCornerShape(18.dp),
        contentPadding = PaddingValues(vertical = 12.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(label, fontFamily = Lilita, fontSize = 20.sp, color = Color.White)
    }
}

@Composable
private fun Paused(game: GameController) {
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.55f))
            .clickable(remember { MutableInteractionSource() }, indication = null) { game.carryOn() },
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(96.dp).clip(CircleShape).background(Palette.yes), contentAlignment = Alignment.Center) {
                Icon(Icons.Default.PlayArrow, contentDescription = "Carry on", tint = Color.White, modifier = Modifier.size(64.dp))
            }
            Spacer(Modifier.height(14.dp))
            OutlinedText("Tap to carry on", size = 24.sp)
        }
    }
}
