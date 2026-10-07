package com.epicaudiogames.app.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import android.view.WindowManager
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
import androidx.compose.foundation.indication
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MicOff
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CollectionInfo
import androidx.compose.ui.semantics.CollectionItemInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.collectionInfo
import androidx.compose.ui.semantics.collectionItemInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.epicaudiogames.app.FeedItem
import com.epicaudiogames.app.GameController
import com.epicaudiogames.engine.Button as Option

/** The mic has been asked for since the app started: opening another game doesn't ask again (the mic button does). */
private var micAsked = false

/**
 * The game, a chat: the talking circle (the game's picture, pulsing while it speaks, ringed while it listens), the
 * transcript as it's spoken with the question's options at its end, and the answer bar: typing and the mic. At an
 * end, the end panel.
 */
@Composable
fun GameScreen(game: GameController, onStore: () -> Unit) {
    val context = LocalContext.current
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) {
            game.allowMic()
        } else {
            game.micAllowed = false
        }
    }
    LaunchedEffect(game) {
        game.micAllowed = micGranted(context)
        if (!game.micAllowed && game.micWorks && !micAsked) {
            micAsked = true
            permission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }
    // The mic button with the mic not allowed: asked for again while Android still asks, else the way to Settings.
    var micOff by remember { mutableStateOf(false) }
    val askForMic: () -> Unit = {
        val activity = context.findActivity()
        if (!micAsked || (activity != null &&
                ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.RECORD_AUDIO))) {
            micAsked = true
            permission.launch(Manifest.permission.RECORD_AUDIO)
        } else {
            micOff = true
        }
    }
    // The screen stays on while a game talks or listens; paused, or at an end, it may sleep. The window's own flag,
    // set and cleared here alone.
    val window = context.findActivity()?.window
    val awake = !game.paused && game.end == null
    DisposableEffect(window, awake) {
        if (awake) {
            window?.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        onDispose { window?.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) }
    }
    // Leaving the app pauses the game (not the activity being made again for a new theme or font size); coming
    // back, a mic allowed in Settings meanwhile works at once.
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(game) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP && context.findActivity()?.isChangingConfigurations != true) {
                game.pause()
            }
            if (event == Lifecycle.Event.ON_RESUME && !game.micAllowed && micGranted(context)) game.allowMic()
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    // Paused, the keyboard goes away: what's typed waits for the tap that carries on.
    val focus = LocalFocusManager.current
    LaunchedEffect(game.paused) {
        if (game.paused) focus.clearFocus()
    }

    Backdrop(Modifier.fillMaxSize()) {
        // Paused, TalkBack reads only the overlay: what's under it can't be touched either.
        Column(Modifier.fillMaxSize().imePadding().then(if (game.paused) Modifier.clearAndSetSemantics {} else Modifier)) {
            var menu by remember { mutableStateOf(false) }
            HeaderBar(game.info.title, onBack = game::leave) {
                // The menu drops from the ⋮ button: the Box is what it's placed by.
                Box {
                    IconButton(onClick = { menu = true }) {
                        Icon(Icons.Default.MoreVert, contentDescription = "More", tint = Color.White)
                    }
                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                        DropdownMenuItem(text = { Text("Start again") }, onClick = { menu = false; game.startAgain() })
                        if (game.info.packs.isNotEmpty()) {
                            DropdownMenuItem(text = { Text("More stories and levels") }, onClick = { menu = false; onStore() })
                        }
                        DropdownMenuItem(text = { Text("Help") }, onClick = { menu = false; openWebPage(context, HELP_URL) })
                        DropdownMenuItem(text = { Text("Privacy policy") }, onClick = { menu = false; openWebPage(context, PRIVACY_URL) })
                    }
                }
            }
            TalkingCircle(game)
            Feed(game, Modifier.weight(1f))
            if (game.end != null) EndPanel(game, onStore) else AnswerBar(game, askForMic)
        }
        if (game.paused) Paused(game)
    }
    if (micOff) {
        AlertDialog(
            onDismissRequest = { micOff = false },
            title = { Text("The microphone is off") },
            text = { Text("To answer out loud, allow the microphone in Settings. You can always tap or type instead.") },
            confirmButton = {
                TextButton(onClick = {
                    micOff = false
                    context.startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)),
                    )
                }) { Text("Settings") }
            },
            dismissButton = { TextButton(onClick = { micOff = false }) { Text("Not now") } },
        )
    }
}

/** The website's help and privacy pages (the stores want both reachable in the app), opened in the browser. */
private const val HELP_URL = "https://epicaudiogames.com/support"
private const val PRIVACY_URL = "https://epicaudiogames.com/privacy"

private fun openWebPage(context: Context, url: String) {
    // No browser on the phone: nothing to open it with, and nothing to do.
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
}

private fun micGranted(context: Context) =
    ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

private fun Context.findActivity(): Activity? {
    var c: Context = this
    while (c is ContextWrapper) {
        if (c is Activity) return c
        c = c.baseContext
    }
    return null
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
            Modifier
                .size(146.dp)
                .testTag("talking-circle")
                .semantics { contentDescription = if (game.speaking) "Skip" else "Talk" }
                .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button) {
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
    var height by remember { mutableIntStateOf(0) }
    // The question's options, from the moment it's asked (as the voice starts) until it's answered or the game moves
    // on: at the end of the chat, under its last line.
    val options = game.ask?.buttons.orEmpty()
    // The newest words stay in view, and the options when they come: a new entry, an entry growing as a line joins
    // it, or less room for the feed (the keyboard up, the end panel). Scrolled to the item after the last one, the end
    // of a tall entry shows too.
    LaunchedEffect(game.feed.size, game.feed.lastOrNull(), height, options) {
        if (game.feed.isNotEmpty() || options.isNotEmpty()) {
            state.animateScrollToItem(game.feed.size + if (options.isEmpty()) 0 else 1)
        }
    }
    LazyColumn(
        modifier.fillMaxWidth().onSizeChanged { height = it.height },
        state = state,
        contentPadding = PaddingValues(start = 14.dp, top = 8.dp, end = 14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        itemsIndexed(game.feed) { i, item ->
            when (item) {
                is FeedItem.Spoken -> Spoken(item, if (i == game.activeEntry) game.activeChars else null)
                is FeedItem.Reply -> Reply(item.text)
                is FeedItem.Note -> OutlinedText(item.text, Modifier.fillMaxWidth().padding(vertical = 4.dp), size = 16.sp)
            }
        }
        if (options.isNotEmpty()) item { Options(options, game::tap) }
        // The feed's end, 8 dp under the last item (the spacing): what it scrolls to.
        item { Spacer(Modifier.height(0.dp)) }
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
        if (item.name.isNotBlank() && item.who != "NARRATOR") {
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

/**
 * The answer bar: the text box, Send and the mic. Speaking or typing is the answer; the question's options are in
 * the chat.
 */
@Composable
private fun AnswerBar(game: GameController, askForMic: () -> Unit) {
    // Gone (an end), nothing is being typed.
    DisposableEffect(game) {
        onDispose { game.typing = false }
    }
    Row(
        Modifier
            .fillMaxWidth()
            .background(Color.White.copy(alpha = 0.22f))
            .windowInsetsPadding(WindowInsets.navigationBars)
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        var text by rememberSaveable { mutableStateOf("") }
        val send = {
            if (text.isNotBlank()) game.answer(text)
            text = ""
        }
        TextField(
            value = text,
            onValueChange = {
                text = it
                game.typed()
            },
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
            // Typing is the answer coming: the mic doesn't open by itself meanwhile.
            modifier = Modifier.weight(1f).onFocusChanged { game.typing = it.isFocused },
        )
        // Ink, as white is too faint on the bar.
        IconButton(onClick = send) {
            Icon(Icons.AutoMirrored.Filled.Send, contentDescription = "Send", tint = Palette.ink)
        }
        val canTalk = game.micAllowed && game.micWorks
        val talk = when {
            game.listening -> "Stop listening"
            canTalk -> "Talk"
            else -> "Talk (the microphone is off)"
        }
        Box(
            Modifier
                .size(54.dp)
                .clip(CircleShape)
                .background(if (game.listening) Palette.listen else if (canTalk) Palette.choice else Color.Gray)
                .clickable(role = Role.Button) { if (game.micAllowed) game.mic() else askForMic() },
            contentAlignment = Alignment.Center,
        ) {
            // Ink on the listening green, as white is too faint there.
            Icon(if (canTalk) Icons.Default.Mic else Icons.Default.MicOff, contentDescription = talk,
                tint = if (game.listening) Palette.ink else Color.White, modifier = Modifier.size(28.dp))
        }
    }
}

/**
 * The question's options, as quick replies at the end of the chat: tapped, one is the answer (its value is sent, its
 * label is the reply). Each is as wide as its label, and they wrap from line to line (a long one takes a line of its
 * own, its words whole). TalkBack hears "Options", then each one as a button.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Options(options: List<Option>, onTap: (Option) -> Unit) {
    FlowRow(
        Modifier.fillMaxWidth().semantics {
            contentDescription = "Options"
            heading()
            collectionInfo = CollectionInfo(rowCount = options.size, columnCount = 1)
        },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        options.forEachIndexed { i, option ->
            Chip(option.label, Modifier.semantics { collectionItemInfo = CollectionItemInfo(i, 1, 0, 1) }) { onTap(option) }
        }
    }
}

/**
 * An option: a white pill edged in the reply's colour, its label as written. It's at least 48 dp to touch (the space
 * around the pill counts), though it looks smaller; with large text, pills on lines one under another stay apart.
 */
@Composable
private fun Chip(label: String, modifier: Modifier, onClick: () -> Unit) {
    val touches = remember { MutableInteractionSource() }
    Box(
        modifier
            .heightIn(min = 48.dp)
            .clickable(touches, indication = null, role = Role.Button, onClick = onClick)
            .padding(vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .heightIn(min = 36.dp)
                .widthIn(min = 48.dp)
                .clip(Pill)
                .background(Palette.card)
                .border(2.dp, Palette.reply, Pill)
                .indication(touches, ripple())
                .padding(horizontal = 14.dp, vertical = 6.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(label, fontFamily = Lilita, fontSize = 15.sp, color = Palette.ink, textAlign = TextAlign.Center)
        }
    }
}

private val Pill = RoundedCornerShape(50)

/**
 * The end: what was reached, and what next. It stops above the navigation bar, whose icons are white; with less room
 * than it needs, it scrolls.
 */
@Composable
private fun EndPanel(game: GameController, onStore: () -> Unit) {
    val end = game.end ?: return
    Column(
        Modifier
            .fillMaxWidth()
            .windowInsetsPadding(WindowInsets.navigationBars)
            .clip(RoundedCornerShape(topStart = 26.dp, topEnd = 26.dp))
            .background(Palette.card)
            .verticalScroll(rememberScrollState())
            .padding(18.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        val headline = when (end.kind) {
            "chapter" -> "CHAPTER COMPLETE!"
            "gameover" -> "GAME OVER"
            else -> "THE END"
        }
        OutlinedText(headline, Modifier.semantics(mergeDescendants = true) { heading() }, size = 30.sp,
            fill = Palette.gold, maxLines = 2, textAlign = TextAlign.Center)
        Text(end.title, style = MaterialTheme.typography.titleLarge, color = Palette.title, textAlign = TextAlign.Center)
        val pack = game.info.packs.firstOrNull { it.id == end.locked }
        if (end.locked != null && !game.canGoOn) {
            if (pack != null) {
                val more = if (end.kind == "chapter") "What happens next is in ${pack.title}." else "There's more: ${pack.title}."
                Text(more, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
                // Dark text on the gold: white is too faint there.
                EndButton("GET ${pack.title.uppercase()}", Palette.gold, Palette.ink, onStore)
            } else {
                Text("What happens next is coming soon, in a story pack.", style = MaterialTheme.typography.bodyMedium,
                    textAlign = TextAlign.Center)
            }
        }
        if (game.canGoOn) EndButton("NEXT CHAPTER", Palette.yes) { game.nextChapter() }
        EndButton(if (end.kind == "gameover") "TRY AGAIN" else "PLAY AGAIN", Palette.choice) { game.playAgain() }
        EndButton("BACK TO GAMES", Palette.headerBottom) { game.leave() }
    }
}

@Composable
private fun EndButton(label: String, color: Color, text: Color = Color.White, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        colors = ButtonDefaults.buttonColors(containerColor = color),
        shape = RoundedCornerShape(18.dp),
        contentPadding = PaddingValues(vertical = 12.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        // Centred on each line, when a long one wraps (large text).
        Text(label, fontFamily = Lilita, fontSize = 20.sp, color = text, textAlign = TextAlign.Center)
    }
}

@Composable
private fun Paused(game: GameController) {
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.55f))
            .clickable(remember { MutableInteractionSource() }, indication = null, role = Role.Button) { game.carryOn() },
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
