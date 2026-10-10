package com.epicaudiogames.app.ui

import android.Manifest
import android.view.WindowManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusGroup
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Send
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material.icons.outlined.HourglassEmpty
import androidx.compose.material.icons.outlined.MicOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CollectionInfo
import androidx.compose.ui.semantics.CollectionItemInfo
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.collectionInfo
import androidx.compose.ui.semantics.collectionItemInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.isTraversalGroup
import androidx.compose.ui.semantics.paneTitle
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.semantics.text
import androidx.compose.ui.semantics.traversalIndex
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.epicaudiogames.app.CircleAction
import com.epicaudiogames.app.FeedItem
import com.epicaudiogames.app.GameController
import com.epicaudiogames.app.MicPrimed
import com.epicaudiogames.app.PackInfo
import com.epicaudiogames.app.Permissions
import com.epicaudiogames.app.R
import com.epicaudiogames.app.currentWord
import com.epicaudiogames.app.findActivity
import com.epicaudiogames.app.rememberWords
import com.epicaudiogames.app.ui.theme.EpicColors
import com.epicaudiogames.app.ui.theme.EpicTheme
import com.epicaudiogames.app.ui.theme.LocalAppSettings
import com.epicaudiogames.app.ui.theme.LocalReduceMotion
import com.epicaudiogames.app.ui.theme.LocalScreenReader
import com.epicaudiogames.app.ui.theme.isAccessibilityTextSize
import com.epicaudiogames.engine.End
import com.epicaudiogames.engine.Button as Option
import androidx.compose.material.icons.outlined.Mic as MicOutlined

/**
 * The game, a chat: the header, the talking circle (the game's picture in a ring that shows what it's doing), the
 * transcript as it's spoken with the question's options at its end, and the answer bar: typing and the mic. At an
 * end, the end panel. [screenReader]: TalkBack (or another screen reader) is on, and the transcript keeps still for it
 * (see [Feed]); a test can say so with LocalScreenReader. At accessibility text sizes the layout is compact: the title
 * moves into the transcript, the circle shrinks and the answer bar stacks (docs/DESIGN.md › Type). On a wide window
 * (an expanded one, or a medium one in landscape) the transcript has a pane of its own beside the rest, read in the
 * same order as on a phone (docs/DESIGN.md › The game on wide windows). [onStore] opens the game's store sheet, from
 * its menu or a locked end; [onHelp] the help sheet on "Playing with your voice", from its menu or the pause (the game
 * waits for it, paused). iOS: GameView.swift.
 *
 * With a keyboard, Space is the talking circle wherever the focus is but in the answer box (MainActivity offers it to
 * the game before anything else), and Escape pauses or carries on (at an end, it leaves). A keyboard's focus coming
 * into the game lands on the circle.
 */
@Composable
fun GameScreen(
    game: GameController,
    onStore: (ShopSource) -> Unit,
    screenReader: Boolean = LocalScreenReader.current,
    onHelp: () -> Unit = {},
) {
    // The whole game takes the screen reader as it's given (the circle's focus as it opens, the transcript's scrolling),
    // so a test that says it's on is believed everywhere.
    CompositionLocalProvider(LocalScreenReader provides screenReader) {
        GameContent(game, onStore, onHelp, screenReader)
    }
}

/** [GameScreen], its screen reader provided. */
@Composable
private fun GameContent(
    game: GameController,
    onStore: (ShopSource) -> Unit,
    onHelp: () -> Unit,
    screenReader: Boolean,
) {
    val context = LocalContext.current
    val settings = LocalAppSettings.current
    // The mic was asked for by a tap (the mic button, or the circle): allowed, the game then listens as the tap would
    // have, even where it doesn't by itself (TalkBack on). Saved, in case the activity is made again meanwhile.
    var tapped by rememberSaveable { mutableStateOf(false) }
    // The mic is off and Android won't ask for it any more: the way to the phone's settings (the dialog below). Kept
    // as a tablet turns.
    var micOff by rememberSaveable { mutableStateOf(false) }
    // The mic, and with it (Android 13+) the notification that shows the game while the screen is off. Only the mic's
    // answer matters here: without the notification, the game still goes on in the background.
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        // Android's answer about the mic, when it was asked (for the usage data: allowed or not).
        it[Manifest.permission.RECORD_AUDIO]?.let(game::micAnswered)
        if (Permissions.micGranted(context)) {
            game.allowMic(listen = tapped)
        } else {
            game.micAllowed = false
            // Asked by a tap, and refused for good: Android answers for the player without asking (refused in an
            // earlier run of the app, which doesn't know it was asked), so a tap would do nothing at all. The way to
            // the phone's settings instead, as a second tap would find it.
            if (tapped && !Permissions.micRationale(context)) micOff = true
        }
        tapped = false
    }
    val ask: (mic: Boolean) -> Unit = { mic ->
        val wanted = listOfNotNull(
            Manifest.permission.RECORD_AUDIO.takeIf { mic },
            Permissions.notificationPermission(context)?.takeIf { !Permissions.notificationsAsked },
        )
        if (mic) Permissions.micAsked = true
        Permissions.notificationsAsked = true
        if (wanted.isNotEmpty()) permission.launch(wanted.toTypedArray())
    }
    // Opening, the game asks for the mic it hasn't got, unless the player said Not now (or refused it) when onboarding
    // asked (settings.micPrimed; docs/DESIGN.md › Onboarding): the mic button and the circle still ask. A game that
    // hears without the microphone (a debug build's script) has it allowed, and asks for nothing.
    LaunchedEffect(game) {
        game.micAllowed = !game.micNeedsPermission || Permissions.micGranted(context)
        ask(!game.micAllowed && game.micWorks && !Permissions.micAsked && settings.micPrimed != MicPrimed.DECLINED)
    }
    // The mic button, or the circle, with the mic not allowed: asked for again while Android still asks, else the way
    // to Settings.
    val askForMic: () -> Unit = {
        if (!Permissions.micAsked || Permissions.micRationale(context)) {
            tapped = true
            ask(true)
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
    // The screen going off, or the app going to the background, doesn't pause the game: it goes on in the pocket,
    // talking and listening (GameController's BackgroundPlay). The keyboard goes, though, so the game listens again
    // after its next question. Coming back, a mic allowed in Settings meanwhile works at once.
    val focus = LocalFocusManager.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(game) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP && game.typing) focus.clearFocus()
            if (event == Lifecycle.Event.ON_RESUME && !game.micAllowed && Permissions.micGranted(context)) game.allowMic()
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    // Paused, the keyboard goes away: what's typed waits for the tap that carries on. Only then: clearing the focus
    // leaves the window with none in touch mode, and the next key would go to Android first (MainActivity's FirstKeys).
    LaunchedEffect(game.paused) {
        if (game.paused && game.typing) focus.clearFocus()
    }
    // The talking circle's tap: with the mic refused, the mic button's way to it.
    val tapCircle: () -> Unit = {
        if (game.circleAction == CircleAction.MIC_REFUSED) askForMic() else game.circle()
    }
    KeyShortcuts { shortcut ->
        when (shortcut) {
            // The one button, unless the answer box has the keys, or there's nothing to do yet (or at an end).
            Shortcut.OneButton -> {
                val action = game.circleAction
                if (game.typing || action == null || !action.enabled) return@KeyShortcuts false
                tapCircle()
                true
            }
            // Escape pauses, and carries on from the pause; at an end, with nothing to pause, it leaves (its place
            // kept), as Back does.
            Shortcut.Escape -> {
                when {
                    game.end != null -> game.leave()
                    game.paused -> game.carryOn()
                    else -> game.pause()
                }
                true
            }
            is Shortcut.ToTab -> false
        }
    }

    val compact = isAccessibilityTextSize()
    val onStoreFromMenu = { onStore(ShopSource.MENU) }
    val onStoreFromEnd = { onStore(ShopSource.LOCKED_END) }
    // The talking circle: where a keyboard's focus lands as it comes into the game (the first key pressed after a
    // touch), so it's on the one button, not on Back at the top. At an end, where the circle is only a picture, the
    // first thing on screen has it as usual.
    val circleFocus = remember { FocusRequester() }
    Box(
        Modifier
            .fillMaxSize()
            .background(EpicTheme.colors.background)
            // (Paused, the circle is under the pause: the keyboard's focus goes to the pause's buttons as usual.)
            .focusProperties { onEnter = { if (!game.paused) circleFocus.requestFocus() } }
            .focusGroup(),
    ) {
        // Paused, TalkBack reads only the overlay, and what's under it can't be touched either; nor can a keyboard's
        // Tab or arrows go there: under the opaque pause its focus couldn't be seen, and a key pressed on what's there
        // would do what the pause keeps from happening (the mic would listen, Back would leave). Read as it's moved.
        val hidden = Modifier
            .then(if (game.paused) Modifier.clearAndSetSemantics {} else Modifier)
            .focusProperties { onEnter = { if (game.paused) cancelFocusChange() } }
            .focusGroup()
        if (gameHasTwoPanes()) {
            TwoPanes(
                game, screenReader, compact, tapCircle, askForMic, onStoreFromMenu, onStoreFromEnd, onHelp, hidden,
                circleFocus,
            )
        } else {
            Column(Modifier.fillMaxSize().imePadding().then(hidden)) {
                // Over the transcript that scrolls under them, so the circle stays whole for TalkBack.
                Column(Modifier.aboveScrollingContent()) {
                    GameHeader(game, showTitle = !compact, onStoreFromMenu, onHelp)
                    TalkingCircle(game, tapCircle, compact, circleFocus)
                }
                Feed(game, screenReader, compact, Modifier.weight(1f))
                if (game.end != null) EndPanel(game, onStoreFromEnd) else AnswerBar(game, askForMic, compact)
            }
        }
        if (game.paused) Paused(game, onHelp)
    }
    if (micOff) {
        AlertDialog(
            onDismissRequest = { micOff = false },
            title = { Text(stringResource(R.string.microphone_off)) },
            text = { Text(stringResource(R.string.microphone_off_text)) },
            confirmButton = {
                EpicButton(stringResource(R.string.microphone_off_settings), {
                    micOff = false
                    game.pause()            // the game waits while the mic is turned on in Settings
                    Permissions.openAppSettings(context)
                }, Modifier.testTag("mic-off-settings"), kind = ButtonKind.Text)
            },
            dismissButton = {
                EpicButton(stringResource(R.string.not_now), { micOff = false }, Modifier.testTag("mic-off-not-now"),
                    kind = ButtonKind.Text)
            },
            modifier = Modifier.windowTestTags(),
        )
    }
}

/**
 * The game on a wide window: on the leading side (about 40%), the header, the talking circle and its status line, then
 * the question's options and the answer bar (or the end panel); on the other, the transcript. TalkBack and the
 * keyboard go through it as on a phone: the header and the circle, the transcript, then the answers.
 */
@Composable
private fun TwoPanes(
    game: GameController,
    screenReader: Boolean,
    compact: Boolean,
    tapCircle: () -> Unit,
    askForMic: () -> Unit,
    onStoreFromMenu: () -> Unit,
    onStoreFromEnd: () -> Unit,
    onHelp: () -> Unit,
    hidden: Modifier,
    circleFocus: FocusRequester,
) {
    val c = EpicTheme.colors
    val options = game.ask?.buttons.orEmpty()
    Row(
        Modifier
            .fillMaxSize()
            .imePadding()
            .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Horizontal))
            .then(hidden),
    ) {
        Column(Modifier.weight(0.4f).fillMaxHeight()) {
            // Over the options that scroll under them, so the circle stays whole for TalkBack.
            Column(Modifier.aboveScrollingContent().semantics { isTraversalGroup = true; traversalIndex = 0f }) {
                GameHeader(game, showTitle = !compact, onStoreFromMenu, onHelp)
                TalkingCircle(game, tapCircle, compact, circleFocus)
            }
            Column(Modifier.weight(1f).semantics { isTraversalGroup = true; traversalIndex = 2f }) {
                Column(
                    Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    if (options.isNotEmpty()) Options(options, game::tap)
                }
                if (game.end != null) EndPanel(game, onStoreFromEnd) else AnswerBar(game, askForMic, compact)
            }
        }
        VerticalDivider(thickness = c.edgeWidth, color = c.outlineSubtle)
        Feed(
            game, screenReader, compact,
            Modifier
                .weight(0.6f)
                .fillMaxHeight()
                .windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Vertical))
                .semantics { isTraversalGroup = true; traversalIndex = 1f },
            showOptions = false,
        )
    }
}

/**
 * The header, under the status bar: Back, the game's title (a heading, wrapping onto more lines, not cut short), and
 * the ⋮ menu: Start again, More stories and levels (the store sheet, which pauses the game) and How to play (the help
 * sheet, which pauses it too). Privacy and Support are in Settings. In the compact layout the title is the
 * transcript's first line instead ([Feed]), so it has the width.
 */
@Composable
private fun GameHeader(game: GameController, showTitle: Boolean, onStore: () -> Unit, onHelp: () -> Unit) {
    val c = EpicTheme.colors
    var menu by remember { mutableStateOf(false) }
    Column(
        Modifier.fillMaxWidth().background(c.surfaceRaised).statusBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Row(
            Modifier.readableWidth().heightIn(min = 56.dp).padding(horizontal = 4.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconActionButton(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back), game::leave)
            if (showTitle) {
                Text(
                    game.info.title,
                    Modifier.weight(1f).padding(horizontal = 8.dp).semantics { heading() },
                    style = EpicTheme.type.itemTitle,
                    color = c.heading,
                )
            } else {
                Spacer(Modifier.weight(1f))
            }
            // The menu drops from the ⋮ button: the Box is what it's placed by.
            Box {
                IconActionButton(Icons.Default.MoreVert, stringResource(R.string.game_menu), { menu = true },
                    Modifier.testTag("game-menu"))
                // Edged, as it's the header's colour over the header (and black on black in High contrast). A popup:
                // its test tags need saying again.
                DropdownMenu(
                    expanded = menu,
                    onDismissRequest = { menu = false },
                    modifier = Modifier.windowTestTags(),
                    containerColor = c.surfaceRaised,
                    border = BorderStroke(c.edgeWidth, c.outline),
                ) {
                    // Starting again stops the voice and the mic itself: a pause first would end the turn instead.
                    MenuItem(stringResource(R.string.menu_start_again), "menu-start-again") {
                        menu = false
                        game.startAgain()
                    }
                    if (game.info.packs.isNotEmpty()) {
                        // The store sheet pauses the game (AppModel.showStore).
                        MenuItem(stringResource(R.string.more_stories), "menu-packs") {
                            menu = false
                            onStore()
                        }
                    }
                    // The help sheet, on playing with your voice: the game waits for it (AppModel.openHelpSheet).
                    MenuItem(stringResource(R.string.how_to_play), "menu-how-to-play") {
                        menu = false
                        onHelp()
                    }
                }
            }
        }
        HorizontalDivider(thickness = c.edgeWidth, color = c.outlineSubtle)
    }
}

@Composable
private fun MenuItem(label: String, tag: String, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(label, style = EpicTheme.type.label) },
        onClick = onClick,
        modifier = Modifier.heightIn(min = 48.dp).testTag(tag).focusRing(RoundedCornerShape(4.dp)),
    )
}

/** The talking circle of [game], as it plays (the one below, on its state). */
@Composable
private fun TalkingCircle(game: GameController, onTap: () -> Unit, compact: Boolean, focus: FocusRequester) =
    TalkingCircle(
        CircleState(
            game.info.id, game.circleAction, game.paused, game.speaking, game.listening, game.partial,
            ended = game.end != null, asked = game.ask != null, micReady = game.micAllowed && game.micWorks,
            opened = game, level = { game.level },
        ),
        onTap, compact, focus,
    )

/**
 * What the talking circle shows, as plain state (GameComponentsTest shows each): what a tap does ([action]; null at an
 * end), what the game is doing, the words heard so far ([partial]), whether a question waits ([asked]) and whether the
 * mic can take it ([micReady]), and whose cover it is ([game], a game's id). [level], the mic's, is read as the ring is
 * drawn: it changes many times a second, and the ring redraws without the circle being composed again. [opened] is
 * what the focus moves to the circle for, as the game opens.
 */
internal class CircleState(
    val game: String,
    val action: CircleAction?,
    val paused: Boolean = false,
    val speaking: Boolean = false,
    val listening: Boolean = false,
    val partial: String = "",
    val ended: Boolean = false,
    val asked: Boolean = false,
    val micReady: Boolean = true,
    val opened: Any = game,
    val level: () -> Float = { 0f },
)

/**
 * The game's picture, and its one button ([onTap]): a tap carries on, skips the voice, or starts or stops listening;
 * with the mic not allowed, it asks for it, as the mic button does. TalkBack hears what a tap does and the game's
 * state ([CircleAction]: "Skip", "Speaking"). At an end it's only a picture. When the game opens, it takes the focus
 * (and TalkBack's) a moment later, with nothing announced: the game is talking (docs/DESIGN.md › Game).
 *
 * What the game is doing shows three ways, never by colour alone: the ring's colour, its style (speaking, a ring that
 * pulses; listening, one as thick as the voice it hears; waiting, a thin dashed one) and the badge's icon. With
 * Reduce Motion, nothing pulses and the listening ring holds at 10 dp.
 */
@Composable
internal fun TalkingCircle(
    s: CircleState,
    onTap: () -> Unit,
    compact: Boolean,
    focus: FocusRequester = remember { FocusRequester() },
) {
    val c = EpicTheme.colors
    val reduceMotion = LocalReduceMotion.current
    // The focus moves for TalkBack and the keyboard, whose focus it is; a finger has no use for it.
    val screenReader = LocalScreenReader.current
    val keyboard = LocalInputModeManager.current.inputMode == InputMode.Keyboard
    val action = s.action
    // What a tap does and the game's state, for TalkBack: as it read them while its focus stays on the circle, so it
    // doesn't say them again as the game moves on, over the voice or as the mic opens (ScreenReaderFocus.kt). A tap
    // still does what the game says now.
    val told = action?.let { heldWhileRead(CIRCLE_TAG, stringResource(it.label) to stringResource(it.state)) }
    val size = if (compact) 88.dp else 128.dp
    val ring = when {
        action == null -> Ring(c.ringIdle, dashed = false)                  // an end: just a picture
        s.paused -> Ring(c.ringIdle, dashed = true)
        s.speaking -> Ring(c.ringSpeaking, dashed = false)
        s.listening -> Ring(c.ringListening, dashed = false)
        else -> Ring(c.ringIdle, dashed = true)
    }
    val listening = s.listening && !s.paused
    val pulse = if (s.speaking && !s.paused && !reduceMotion) rememberPulse() else null
    val badge = when (action) {
        CircleAction.CARRY_ON -> Icons.Default.PlayArrow
        CircleAction.SKIP -> Icons.Default.SkipNext
        CircleAction.STOP_LISTENING -> Icons.Default.Mic
        CircleAction.TALK -> Icons.Outlined.MicOutlined
        CircleAction.MIC_REFUSED, CircleAction.NO_RECOGNITION -> Icons.Outlined.MicOff
        CircleAction.WAIT -> Icons.Outlined.HourglassEmpty
        null -> null
    }
    Column(
        Modifier.fillMaxWidth().padding(top = 12.dp - FOCUS_RING_ROOM, bottom = 4.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(
            Modifier
                // The keyboard's focus ring goes round the circle, clear of it: on its edge it would hide the ring
                // whose colour and style say what the game is doing (and in Dark it's the speaking ring's gold).
                .focusRing(CircleShape)
                .padding(FOCUS_RING_ROOM)
                .size(size)
                .testTag(CIRCLE_TAG)
                // A button takes the focus only from a keyboard, unless asked: with TalkBack on, it may (as it opens).
                .then(if (screenReader) Modifier.focusProperties { canFocus = true } else Modifier)
                .focusRequester(focus)
                .focusOnAppear(s.opened, focusable = false, enabled = screenReader || keyboard)
                .then(
                    if (action == null || told == null) {
                        Modifier
                    } else {
                        Modifier
                            .semantics {
                                contentDescription = told.first
                                stateDescription = told.second
                            }
                            // As the headphones' button and the notification's (GameController.circle), but with the
                            // mic refused, the mic button's way: asked for, or the way to Settings. Waiting for the
                            // question, disabled. What it does is decided as it's tapped.
                            .clickable(
                                interactionSource = null,
                                indication = ripple(bounded = false, radius = size / 2),
                                enabled = action.enabled,
                                role = Role.Button,
                                onClick = onTap,
                            )
                    },
                ),
            contentAlignment = Alignment.Center,
        ) {
            // The picture and its ring, which pulse together while the game speaks.
            Box(
                Modifier.matchParentSize().graphicsLayer {
                    val s = pulse?.value ?: 1f
                    scaleX = s
                    scaleY = s
                },
                contentAlignment = Alignment.Center,
            ) {
                val cover = rememberAssetImage("${s.game}/cover.jpg")
                if (cover != null) {
                    Image(cover, contentDescription = null, contentScale = ContentScale.Crop,
                        modifier = Modifier.size(size - 16.dp).clip(CircleShape))
                } else {
                    Box(Modifier.size(size - 16.dp).background(c.surface, CircleShape))
                }
                Canvas(Modifier.matchParentSize()) {
                    // Read as it's drawn, so the mic's level redraws the ring without recomposing.
                    val width = when {
                        !listening -> if (ring.dashed) 3.dp else 4.dp
                        reduceMotion -> 10.dp
                        else -> (4 + 10 * s.level()).dp
                    }.toPx()
                    drawCircle(
                        ring.color,
                        radius = (this.size.minDimension - width) / 2,
                        style = Stroke(
                            width,
                            pathEffect = if (ring.dashed) {
                                PathEffect.dashPathEffect(floatArrayOf(9.dp.toPx(), 6.dp.toPx()))
                            } else {
                                null
                            },
                        ),
                    )
                }
            }
            if (badge != null) {
                Box(
                    Modifier
                        .size(if (compact) 36.dp else 44.dp)
                        .background(c.background, CircleShape)
                        .border(2.dp, ring.color, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(badge, contentDescription = null, tint = ring.color,
                        modifier = Modifier.size(if (compact) 20.dp else 26.dp))
                }
            }
        }
        Spacer(Modifier.height(8.dp - FOCUS_RING_ROOM))
        val status = when {
            s.paused -> stringResource(R.string.paused)
            s.listening && s.partial.isNotEmpty() -> stringResource(R.string.status_heard, s.partial)
            s.listening -> stringResource(R.string.status_listening)
            s.speaking -> stringResource(R.string.status_skip)
            s.ended -> ""
            s.asked -> stringResource(if (s.micReady) R.string.status_your_turn_mic else R.string.status_your_turn)
            else -> ""
        }
        // Not a live region: the game says what matters, and the mic must never hear TalkBack. Nor is it said again as
        // it changes under TalkBack's focus ("Listening…", the words heard so far): TalkBack keeps it as it read it
        // there (ScreenReaderFocus.kt). With nothing to say (an end, no question yet) it keeps its line, so nothing
        // moves, but isn't an element for TalkBack to stop on.
        val told = heldWhileRead(STATUS_TAG, status)
        Text(
            status,
            Modifier
                .readableWidth()
                .padding(horizontal = 16.dp)
                .testTag(STATUS_TAG)
                .clearAndSetSemantics { if (told.isNotEmpty()) text = AnnotatedString(told) },
            style = EpicTheme.type.label,
            color = c.text,
            textAlign = TextAlign.Center,
        )
    }
}

/** The talking circle's ring: its colour, and whether it's the dashed one (waiting for the player). */
private data class Ring(val color: Color, val dashed: Boolean)

/** The talking circle's test tag (docs/DESIGN.md's identifier; iOS's too). */
internal const val CIRCLE_TAG = "talking-circle"

/** The mic button's (iOS's identifier: AnswersPanel.swift). */
internal const val MIC_TAG = "mic"

/** The line under the circle's: what to do, in words. */
internal const val STATUS_TAG = "game-status"

/** The room round the talking circle for the focus ring: its 3 dp, and 3 dp clear of the circle's own ring. */
private val FOCUS_RING_ROOM = 6.dp

/** The speaking pulse: a little bigger and back, twice a second. */
@Composable
private fun rememberPulse(): State<Float> = rememberInfiniteTransition(label = "pulse").animateFloat(
    initialValue = 1f, targetValue = 1.06f,
    animationSpec = infiniteRepeatable(tween(480), RepeatMode.Reverse), label = "pulse",
)

/**
 * The transcript, with the question's options at its end (unless [showOptions] is false: the wide layout has them in
 * the other pane). Without a screen reader it follows the newest words (at once with Reduce Motion). With one
 * ([screenReader]) it scrolls only when the options, a reply or the end panel appear, so nothing moves under the
 * player's finger: TalkBack moves through the lines itself (docs/DESIGN.md › Game › Transcript). In the [compact]
 * layout, the game's title is its first line.
 */
@Composable
private fun Feed(
    game: GameController,
    screenReader: Boolean,
    compact: Boolean,
    modifier: Modifier,
    showOptions: Boolean = true,
) {
    val state = rememberLazyListState()
    val reduceMotion = LocalReduceMotion.current
    var height by remember { mutableIntStateOf(0) }
    // The question's options, from the moment it's asked (as the voice starts) until it's answered or the game moves
    // on: at the end of the chat, under its last line.
    val options = game.ask?.buttons.orEmpty()
    val shown = if (showOptions) options else emptyList()
    val first = if (compact) 1 else 0
    // Scrolled to the item after the last one, the end of a tall entry shows too.
    val toEnd: suspend () -> Unit = {
        if (game.feed.isNotEmpty() || shown.isNotEmpty()) {
            val end = first + game.feed.size + if (shown.isEmpty()) 0 else 1
            if (reduceMotion) state.scrollToItem(end) else state.animateScrollToItem(end)
        }
    }
    if (screenReader) {
        val replies = game.feed.count { it is FeedItem.Reply }
        val ending = game.end != null
        LaunchedEffect(options) { if (options.isNotEmpty()) toEnd() }
        LaunchedEffect(replies) { if (replies > 0) toEnd() }
        // The end panel coming takes room from the feed: once that's laid out, its end again.
        LaunchedEffect(ending, height) { if (ending) toEnd() }
    } else {
        // The newest words stay in view, and the options when they come: a new entry, an entry growing as a line joins
        // it, or less room for the feed (the keyboard up, the end panel).
        LaunchedEffect(game.feed.size, game.feed.lastOrNull(), height, options) { toEnd() }
    }
    LazyColumn(
        modifier.fillMaxWidth().onSizeChanged { height = it.height },
        state = state,
        contentPadding = PaddingValues(start = 16.dp, top = 8.dp, end = 16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (compact) {
            item {
                Text(
                    game.info.title,
                    Modifier.readableWidth().semantics { heading() },
                    style = EpicTheme.type.itemTitle,
                    color = EpicTheme.colors.heading,
                )
            }
        }
        itemsIndexed(game.feed) { i, item ->
            when (item) {
                is FeedItem.Spoken -> Spoken(item, if (i == game.activeEntry) game.activeChars else null)
                is FeedItem.Reply -> Reply(item)
                is FeedItem.Note -> Text(
                    stringResource(item.text),
                    Modifier.readableWidth().padding(vertical = 2.dp),
                    style = EpicTheme.type.secondary,
                    color = EpicTheme.colors.textMuted,
                    textAlign = TextAlign.Center,
                )
            }
        }
        if (shown.isNotEmpty()) item { Options(shown, game::tap) }
        // The feed's end, 12 dp under the last item (the spacing): what it scrolls to.
        item { Spacer(Modifier.height(0.dp)) }
    }
}

/**
 * A line of the game: its speaker's name in bold above a bubble (not for the narrator, nor with Settings › Show who's
 * speaking off), the words in the transcript style. The line being spoken has an accent bar on its leading edge and
 * an accent border, and its current word is highlighted ([transcriptText]). TalkBack reads it as one element, its
 * speaker first whether the name shows or not ([FeedItem.readAs]), and doesn't announce it as it comes: the game is
 * already saying it.
 */
@Composable
private fun Spoken(item: FeedItem.Spoken, saidChars: Int?) {
    val c = EpicTheme.colors
    val settings = LocalAppSettings.current
    val readAs = item.readAs(rememberWords())
    val current = saidChars != null
    val shape = RoundedCornerShape(16.dp)
    Column(
        Modifier
            .readableWidth()
            .padding(end = 32.dp)
            .clearAndSetSemantics { contentDescription = readAs },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (settings.speakerNames && item.name.isNotBlank() && item.who != "NARRATOR") {
            Text(item.name, style = EpicTheme.type.speaker, color = c.text)
        }
        Text(
            transcriptText(item.text, saidChars, settings.highlightWords, settings.wholeLine, c),
            Modifier
                .clip(shape)
                .background(c.surface)
                .then(if (current) Modifier.accentBar(c.accent) else Modifier)
                .border(if (current) 2.dp else c.edgeWidth, if (current) c.accent else c.outlineSubtle, shape)
                // Room for the bar on every line, so the words don't shift as a line stops being the current one.
                .padding(start = ACCENT_BAR + 14.dp, end = 16.dp, top = 10.dp, bottom = 10.dp),
            style = EpicTheme.type.transcript,
            color = c.text,
        )
    }
}

/** The current line's bar: [ACCENT_BAR] wide down its leading edge (the right, in a right-to-left language). */
private fun Modifier.accentBar(color: Color) = drawBehind {
    val width = ACCENT_BAR.toPx()
    val x = if (layoutDirection == LayoutDirection.Rtl) size.width - width else 0f
    drawRect(color, topLeft = Offset(x, 0f), size = Size(width, size.height))
}

private val ACCENT_BAR = 4.dp

/**
 * A line's words. Not being spoken ([saidChars] null), as they are. Being spoken: the word the voice is on in inverse
 * colours (if [highlight]), and the words still to come at full strength ([wholeLine]) or hidden: transparent, so they
 * keep their place and nothing moves as they're said. Never faded: pale words were hard to read.
 */
internal fun transcriptText(
    text: String,
    saidChars: Int?,
    highlight: Boolean,
    wholeLine: Boolean,
    colors: EpicColors,
): AnnotatedString = buildAnnotatedString {
    if (saidChars == null) {
        append(text)
        return@buildAnnotatedString
    }
    val (before, word, after) = currentWord(text, saidChars)
    append(before)
    if (highlight) {
        withStyle(SpanStyle(color = colors.highlightText, background = colors.highlightBg)) { append(word) }
    } else {
        append(word)
    }
    if (wholeLine) {
        append(after)
    } else {
        withStyle(SpanStyle(color = Color.Transparent)) { append(after) }
    }
}

/** What the player said, typed or tapped, at the right under "You". TalkBack reads it "You said: …". */
@Composable
private fun Reply(item: FeedItem.Reply) {
    val c = EpicTheme.colors
    val shape = RoundedCornerShape(16.dp)
    val readAs = item.readAs(rememberWords())
    Column(
        Modifier
            .readableWidth()
            .padding(start = 48.dp)
            .clearAndSetSemantics { contentDescription = readAs },
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(stringResource(R.string.reply_you), style = EpicTheme.type.speaker, color = c.text)
        Text(
            item.text,
            Modifier
                .clip(shape)
                .background(c.replySurface)
                .border(c.edgeWidth, c.replyEdge, shape)
                .padding(horizontal = 16.dp, vertical = 10.dp),
            style = EpicTheme.type.transcript,
            color = c.text,
        )
    }
}

/**
 * The answer bar: the text box, Send and the mic. Speaking or typing is the answer; the question's options are in
 * the chat. In the [compact] layout the text box has a row of its own, and Send and the mic show their words under it.
 */
@Composable
private fun AnswerBar(game: GameController, askForMic: () -> Unit, compact: Boolean) {
    val c = EpicTheme.colors
    // Gone (an end), nothing is being typed.
    DisposableEffect(game) {
        onDispose { game.typing = false }
    }
    var text by rememberSaveable { mutableStateOf("") }
    val send = {
        if (text.isNotBlank()) game.answer(text)
        text = ""
    }
    val onText: (String) -> Unit = {
        text = it
        game.typed()
    }
    Column(
        Modifier.fillMaxWidth().background(c.surfaceRaised),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        HorizontalDivider(thickness = c.edgeWidth, color = c.outlineSubtle)
        if (compact) {
            Column(
                Modifier.readableWidth().navigationBarsPadding().padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                AnswerField(text, onText, send, game, Modifier.fillMaxWidth())
                // Side by side while their words fit whole; the mic's longer names ("Talk (the microphone is off)")
                // at the largest text don't, and then each has a row of its own.
                SharedRow {
                    EpicButton(stringResource(R.string.send), send, kind = ButtonKind.Secondary,
                        icon = Icons.AutoMirrored.Filled.Send)
                    MicButton(game, askForMic, words = true)
                }
            }
        } else {
            Row(
                Modifier.readableWidth().navigationBarsPadding().padding(12.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                AnswerField(text, onText, send, game, Modifier.weight(1f))
                IconActionButton(Icons.AutoMirrored.Filled.Send, stringResource(R.string.send), send)
                MicButton(game, askForMic, words = false)
            }
        }
    }
}

/**
 * The text box, labelled "Type an answer" (the label stays, above what's typed). Its 2 dp outline turns into the
 * 3 dp focus ring while it has the focus. Typing is the answer coming: the mic doesn't open by itself meanwhile.
 */
@Composable
private fun AnswerField(
    text: String,
    onText: (String) -> Unit,
    send: () -> Unit,
    game: GameController,
    modifier: Modifier,
) {
    val c = EpicTheme.colors
    val shape = RoundedCornerShape(12.dp)
    var focused by remember { mutableStateOf(false) }
    TextField(
        value = text,
        onValueChange = onText,
        label = { Text(stringResource(R.string.answer_field)) },
        singleLine = true,
        textStyle = EpicTheme.type.body,
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
        keyboardActions = KeyboardActions(onSend = { send() }),
        shape = shape,
        colors = TextFieldDefaults.colors(
            focusedTextColor = c.text, unfocusedTextColor = c.text,
            focusedContainerColor = c.surface, unfocusedContainerColor = c.surface,
            focusedIndicatorColor = Color.Transparent, unfocusedIndicatorColor = Color.Transparent,
            focusedLabelColor = c.textMuted, unfocusedLabelColor = c.textMuted,
            cursorColor = c.text,
        ),
        modifier = modifier
            .border(if (focused) 3.dp else 2.dp, if (focused) c.focus else c.outline, shape)
            .onFocusChanged {
                focused = it.isFocused
                game.typing = it.isFocused
            },
    )
}

/**
 * The mic: 56 dp, primary; while listening, the listening colour with a stop icon; with the mic refused or no speech
 * recognition, outlined, with a crossed-out mic. Named as the circle's way to talk: Talk, Stop listening, or why it
 * can't ([CircleAction.mic]); as TalkBack read it while its focus stays on it, so "Stop listening" isn't said as the
 * mic opens (ScreenReaderFocus.kt). With [words] (the compact layout), a wide button showing that name.
 */
@Composable
private fun MicButton(game: GameController, askForMic: () -> Unit, words: Boolean, modifier: Modifier = Modifier) {
    val c = EpicTheme.colors
    val action = CircleAction.mic(game.listening, game.micAllowed, game.micWorks)
    val label = heldWhileRead(MIC_TAG, stringResource(action.label))
    val canTalk = game.micAllowed && game.micWorks
    val onClick = { if (game.micAllowed) game.mic() else askForMic() }
    val fill = when {
        game.listening -> c.ringListening
        canTalk -> c.primary
        else -> c.surface
    }
    // On the listening colour, the background's colour (dark on a light green, light on a dark one).
    val tint = when {
        game.listening -> c.background
        canTalk -> c.onPrimary
        else -> c.text
    }
    val edge = if (game.listening || canTalk) null else BorderStroke(2.dp, c.outline)
    val icon: ImageVector = when {
        game.listening -> Icons.Default.Stop
        canTalk -> Icons.Default.Mic
        else -> Icons.Outlined.MicOff
    }
    if (words) {
        val shape = RoundedCornerShape(14.dp)
        Button(
            onClick = onClick,
            modifier = modifier.heightIn(min = 56.dp).testTag(MIC_TAG).focusRing(shape),
            shape = shape,
            colors = ButtonDefaults.buttonColors(containerColor = fill, contentColor = tint),
            border = edge,
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 12.dp),
        ) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(24.dp))
            Spacer(Modifier.width(8.dp))
            Text(label, style = EpicTheme.type.label, textAlign = TextAlign.Center)
        }
    } else {
        Box(
            modifier
                .size(56.dp)
                .testTag(MIC_TAG)
                .focusRing(CircleShape)
                .clip(CircleShape)
                .background(fill)
                .then(if (edge != null) Modifier.border(edge, CircleShape) else Modifier)
                .clickable(role = Role.Button, onClick = onClick)
                .semantics { contentDescription = label },
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(28.dp))
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
internal fun Options(options: List<Option>, onTap: (Option) -> Unit) {
    val heading = stringResource(R.string.options)
    FlowRow(
        Modifier.readableWidth().semantics {
            contentDescription = heading
            heading()
            collectionInfo = CollectionInfo(rowCount = options.size, columnCount = 1)
        },
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        options.forEachIndexed { i, option ->
            Chip(option.label, Modifier.semantics { collectionItemInfo = CollectionItemInfo(i, 1, 0, 1) }) { onTap(option) }
        }
    }
}

/** An option: a surface pill with a 2 dp outline, 48 dp tall at least, its label as written. */
@Composable
private fun Chip(label: String, modifier: Modifier, onClick: () -> Unit) {
    val c = EpicTheme.colors
    val shape = RoundedCornerShape(24.dp)
    Box(
        modifier
            .heightIn(min = 48.dp)
            .widthIn(min = 48.dp)
            .focusRing(shape)
            .clip(shape)
            .background(c.surface)
            .border(2.dp, c.outline, shape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(label, style = EpicTheme.type.label, color = c.text, textAlign = TextAlign.Center)
    }
}

/** [game]'s end panel, once it's at an end (the one below, on its state). */
@Composable
private fun EndPanel(game: GameController, onStore: () -> Unit) {
    val end = game.end ?: return
    EndPanel(
        end, game.info.packs.firstOrNull { it.id == end.locked }, game.canGoOn,
        onNext = game::nextChapter, onAgain = game::playAgain, onBack = game::leave, onStore = onStore,
    )
}

/**
 * The end: what was reached ([end]), and what next. It stops above the navigation bar; with less room than it needs,
 * it scrolls. A pane named by its heading, which takes the focus (and TalkBack's) as it appears. Its free part over,
 * a locked end says which [pack] has what's next, with its Get button; with the next chapter here ([canGoOn]), Next
 * chapter; then Play again (Try again after a game over) and Back to games.
 */
@Composable
internal fun EndPanel(
    end: End,
    pack: PackInfo?,
    canGoOn: Boolean,
    onNext: () -> Unit,
    onAgain: () -> Unit,
    onBack: () -> Unit,
    onStore: () -> Unit,
) {
    val c = EpicTheme.colors
    val headline = stringResource(
        when (end.kind) {
            "chapter" -> R.string.end_chapter
            "gameover" -> R.string.end_game_over
            else -> R.string.end_the_end
        },
    )
    val shape = RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.surfaceRaised)
            .border(c.edgeWidth, c.outlineSubtle, shape)
            .semantics { paneTitle = headline }
            .verticalScroll(rememberScrollState())
            .navigationBarsPadding()
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(
            Modifier.readableWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                headline,
                Modifier
                    .testTag("end-heading")
                    .focusOnAppear(end)
                    .semantics(mergeDescendants = true) { heading() },
                style = EpicTheme.type.headline,
                color = c.heading,
                textAlign = TextAlign.Center,
            )
            Text(end.title, style = EpicTheme.type.itemTitle, color = c.text, textAlign = TextAlign.Center)
            if (end.locked != null && !canGoOn) {
                if (pack != null) {
                    val more = stringResource(
                        if (end.kind == "chapter") R.string.end_next_in else R.string.end_more_in, pack.title,
                    )
                    Text(more, style = EpicTheme.type.body, color = c.text, textAlign = TextAlign.Center)
                    EpicButton(stringResource(R.string.get_pack, pack.title), onStore,
                        Modifier.fillMaxWidth().testTag("end-get"))
                } else {
                    Text(stringResource(R.string.end_coming_soon), style = EpicTheme.type.body,
                        color = c.text, textAlign = TextAlign.Center)
                }
            }
            if (canGoOn) {
                EpicButton(stringResource(R.string.next_chapter), onNext, Modifier.fillMaxWidth().testTag("end-next"))
            }
            val again = stringResource(if (end.kind == "gameover") R.string.end_try_again else R.string.end_play_again)
            EpicButton(again, onAgain, Modifier.fillMaxWidth().testTag("end-again"), kind = ButtonKind.Secondary)
            EpicButton(stringResource(R.string.end_back), onBack, Modifier.fillMaxWidth().testTag("end-back"),
                kind = ButtonKind.Secondary)
        }
    }
}

/** [game]'s pause, over it (the one below). */
@Composable
private fun Paused(game: GameController, onHelp: () -> Unit) = Paused(game::carryOn, onHelp, game::leave)

/**
 * Everything waits for the player, over the game hidden by the scrim (solid: words showing through behind the buttons
 * are hard to read with low vision): carry on ([onCarryOn]), how to play (the help sheet, [onHelp]), or leave the game
 * ([onLeave]: its place is kept, as with Back). A tap anywhere else carries on too, for a finger only: TalkBack, which
 * hears "Paused" as it appears and moves to its heading, has the buttons.
 */
@Composable
internal fun Paused(onCarryOn: () -> Unit, onHelp: () -> Unit, onLeave: () -> Unit) {
    val c = EpicTheme.colors
    val paused = stringResource(R.string.paused)
    val carryOn by rememberUpdatedState(onCarryOn)
    Box(
        Modifier
            .fillMaxSize()
            .background(c.scrim)
            .pointerInput(Unit) { detectTapGestures { carryOn() } }
            .semantics { paneTitle = paused },
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .widthIn(max = 420.dp)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(
                paused,
                Modifier
                    .focusOnAppear()
                    .semantics(mergeDescendants = true) { heading() },
                style = EpicTheme.type.headline,
                color = c.heading,
                textAlign = TextAlign.Center,
            )
            EpicButton(stringResource(R.string.carry_on), onCarryOn, Modifier.fillMaxWidth().testTag("paused-carry-on"),
                icon = Icons.Default.PlayArrow)
            // The help sheet, over the pause: the game stays paused for it.
            EpicButton(stringResource(R.string.how_to_play), onHelp, Modifier.fillMaxWidth().testTag("paused-help"),
                kind = ButtonKind.Secondary)
            EpicButton(stringResource(R.string.leave_game), onLeave, Modifier.fillMaxWidth().testTag("paused-leave"),
                kind = ButtonKind.Secondary)
        }
    }
}
