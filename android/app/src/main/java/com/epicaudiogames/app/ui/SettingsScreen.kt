package com.epicaudiogames.app.ui

import android.Manifest
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.outlined.MicOff
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.app.ActivityCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.epicaudiogames.app.AnswerTime
import com.epicaudiogames.app.AppSettings
import com.epicaudiogames.app.BuildConfig
import com.epicaudiogames.app.FontChoice
import com.epicaudiogames.app.Links
import com.epicaudiogames.app.MicAuto
import com.epicaudiogames.app.Permissions
import com.epicaudiogames.app.R
import com.epicaudiogames.app.ThemeChoice
import com.epicaudiogames.app.Words
import com.epicaudiogames.app.rememberWords
import com.epicaudiogames.app.analytics.UsageDeletion
import com.epicaudiogames.app.findActivity
import com.epicaudiogames.app.ui.theme.EpicColors
import com.epicaudiogames.app.ui.theme.EpicTheme
import com.epicaudiogames.app.ui.theme.LocalScreenReader
import com.epicaudiogames.app.ui.theme.rememberAnimationsOff
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * The Settings tab (docs/DESIGN.md › Settings): one page of level-2 sections, the most useful for blind players first.
 * Sound and voice, Microphone, Appearance, Transcript, Privacy, Help and about; every control is a whole row, saved as
 * it changes ([settings], AppSettings.kt). The sound settings take effect in the games, and each lets the player hear
 * what it does: [onPlaySample] plays the voice at its speed; [onPreviewIntro] the intro's sound, as Play the intro sound
 * is turned on; [onPreviewCue] the listening sound and tick as the mic would open, when either is turned on; and
 * [onPreviewMusic] a few seconds of a game's music at each Music volume picked (Off: silence). [onHowToPlay] goes to
 * the Help tab, [onShowWelcome] shows the welcome again, and [onDeleteUsageData] asks the server to forget this phone.
 * [onMicAnswer] hears what the player said to the microphone's question asked here. Licences is a page of its own
 * within the tab: Back (or its Back) returns. iOS: SettingsView.swift.
 */
@Composable
fun SettingsScreen(
    settings: AppSettings,
    onPlaySample: () -> Unit,
    onHowToPlay: () -> Unit,
    onShowWelcome: () -> Unit,
    onDeleteUsageData: suspend () -> UsageDeletion,
    onMicAnswer: (Boolean) -> Unit,
    onPreviewCue: () -> Unit = {},
    onPreviewIntro: () -> Unit = {},
    onPreviewMusic: () -> Unit = {},
) {
    val c = EpicTheme.colors
    var licences by rememberSaveable { mutableStateOf(false) }
    // Kept while Licences shows, so the page is where it was on the way back, with the focus on Licences again.
    val scroll = rememberScrollState()
    val backToLicences = remember { FocusRequester() }
    var back by remember { mutableStateOf(false) }
    if (licences) {
        val close = {
            licences = false
            back = true
        }
        BackHandler(onBack = close)
        // Escape closes the page too (a keyboard's Back).
        KeyShortcuts { (it == Shortcut.Escape).also { escape -> if (escape) close() } }
        LicencesPage(onBack = close)
        return
    }
    val keyboard = LocalInputModeManager.current.inputMode == InputMode.Keyboard
    val screenReader = LocalScreenReader.current
    val words = rememberWords()
    LaunchedEffect(back) {
        if (back && (keyboard || screenReader)) runCatching { backToLicences.requestFocus() }
        back = false
    }
    Column(
        Modifier
            .fillMaxSize()
            .background(c.background)
            .verticalScroll(scroll)
            .padding(start = 16.dp, top = 16.dp, end = 16.dp, bottom = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.readableWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            ScreenHeader(stringResource(R.string.settings_heading), Modifier.testTag("settings-heading"))

            Section(stringResource(R.string.settings_sound), divider = false)
            Label(stringResource(R.string.settings_voice_speed))
            SpeedStepper(settings.voiceSpeed, AppSettings.VOICE_SPEEDS, { settings.voiceSpeed = it },
                Modifier.testTag("setting-voiceSpeed"))
            EpicButton(stringResource(R.string.settings_sample), onPlaySample,
                Modifier.fillMaxWidth().testTag("setting-voiceSample"), kind = ButtonKind.Secondary,
                icon = Icons.Default.PlayArrow)
            // Turned on, it lets the player hear what it will play as the app starts.
            SwitchRow(stringResource(R.string.settings_intro_sound), settings.introSound, {
                settings.introSound = it
                if (it) onPreviewIntro()
            }, Modifier.testTag("setting-introSound"), hint = stringResource(R.string.settings_intro_sound_hint))
            // Turned on, each lets the player hear (or feel) what it does: the mic opening, as it will in a game.
            SwitchRow(stringResource(R.string.settings_listening_sounds), settings.listeningSounds, {
                settings.listeningSounds = it
                if (it) onPreviewCue()
            }, Modifier.testTag("setting-listeningSounds"), hint = stringResource(R.string.settings_listening_sounds_hint))
            SwitchRow(stringResource(R.string.settings_listening_haptics), settings.listeningHaptics, {
                settings.listeningHaptics = it
                if (it) onPreviewCue()
            }, Modifier.testTag("setting-listeningHaptics"))
            Label(stringResource(R.string.settings_music_volume))
            // Each step picked (the one already picked too) plays the music at it, to judge it by; Off, nothing.
            ChoiceGroup(
                AppSettings.MUSIC_VOLUMES, settings.musicVolume, {
                    settings.musicVolume = it
                    onPreviewMusic()
                },
                label = { words.volumeWords(it) },
                modifier = Modifier.testTag("setting-musicVolume"),
                tag = { "setting-musicVolume-${(it * 100).toInt()}" },
            )
            Note(stringResource(R.string.settings_music_note))
            Label(stringResource(R.string.settings_answer_time))
            ChoiceGroup(
                AnswerTime.entries, settings.answerTime, { settings.answerTime = it },
                label = { words.answerTimeWords(it) },
                modifier = Modifier.testTag("setting-answerTime"),
                hint = { words.plural(R.plurals.seconds, (it.millis / 1000).toInt(), it.millis / 1000) },
                tag = { "setting-answerTime-${it.key}" },
            )

            Section(stringResource(R.string.settings_microphone))
            Label(stringResource(R.string.settings_mic_auto))
            ChoiceGroup(
                MicAuto.entries, settings.micAuto, { settings.micAuto = it },
                label = {
                    words.text(
                        when (it) {
                            MicAuto.NOT_WITH_SCREEN_READER -> R.string.mic_auto_not_with_screen_reader
                            MicAuto.ALWAYS -> R.string.mic_auto_always
                            MicAuto.NEVER -> R.string.mic_auto_never
                        },
                    )
                },
                modifier = Modifier.testTag("setting-micAuto"),
                hint = {
                    words.text(
                        when (it) {
                            MicAuto.NOT_WITH_SCREEN_READER -> R.string.mic_auto_not_with_screen_reader_hint
                            MicAuto.ALWAYS -> R.string.mic_auto_always_hint
                            MicAuto.NEVER -> R.string.mic_auto_never_hint
                        },
                    )
                },
                tag = { "setting-micAuto-${it.key}" },
            )
            MicrophoneStatus(onMicAnswer)

            Section(stringResource(R.string.settings_appearance))
            Label(stringResource(R.string.settings_theme))
            ThemeChoices(settings)
            Label(stringResource(R.string.settings_text_size))
            TextSizeChoices(settings)
            Label(stringResource(R.string.settings_font))
            ChoiceGroup(
                FontChoice.entries, settings.font, { settings.font = it },
                label = {
                    words.text(
                        when (it) {
                            FontChoice.ATKINSON -> R.string.font_atkinson
                            FontChoice.SYSTEM -> R.string.font_system
                        },
                    )
                },
                modifier = Modifier.testTag("setting-font"),
                hint = { if (it == FontChoice.ATKINSON) words.text(R.string.font_atkinson_hint) else null },
                tag = { "setting-font-${it.key}" },
            )
            // With the phone's own Remove animations on, it's on here too, and can't be turned off here.
            val phoneReduces = rememberAnimationsOff()
            SwitchRow(
                stringResource(R.string.settings_reduce_motion), settings.reduceMotion || phoneReduces,
                { settings.reduceMotion = it },
                Modifier.testTag("setting-reduceMotion"),
                hint = stringResource(
                    if (phoneReduces) R.string.settings_on_in_phone else R.string.settings_reduce_motion_hint,
                ),
                enabled = !phoneReduces,
            )

            Section(stringResource(R.string.settings_transcript))
            SwitchRow(stringResource(R.string.settings_highlight_words), settings.highlightWords,
                { settings.highlightWords = it }, Modifier.testTag("setting-highlightWords"))
            SwitchRow(stringResource(R.string.settings_whole_line), settings.wholeLine, { settings.wholeLine = it },
                Modifier.testTag("setting-wholeLine"), hint = stringResource(R.string.settings_whole_line_hint))
            SwitchRow(stringResource(R.string.settings_speaker_names), settings.speakerNames,
                { settings.speakerNames = it }, Modifier.testTag("setting-speakerNames"),
                hint = stringResource(R.string.settings_speaker_names_hint))

            Section(stringResource(R.string.settings_privacy))
            SwitchRow(
                stringResource(R.string.settings_analytics), settings.analytics, { settings.analytics = it },
                Modifier.testTag("setting-analytics"),
                hint = stringResource(R.string.settings_analytics_hint),
            )
            DeleteUsageData(onDeleteUsageData, sharing = settings.analytics)
            val context = LocalContext.current
            LinkRow(stringResource(R.string.settings_privacy_policy), { Links.open(context, Links.PRIVACY) },
                Modifier.testTag("setting-privacy"))

            Section(stringResource(R.string.settings_help_about))
            PageRow(stringResource(R.string.how_to_play), onHowToPlay, Modifier.testTag("setting-howToPlay"))
            PageRow(stringResource(R.string.show_welcome), onShowWelcome, Modifier.testTag("setting-welcome"))
            LinkRow(stringResource(R.string.settings_support), { Links.open(context, Links.SUPPORT) },
                Modifier.testTag("setting-support"))
            LinkRow(stringResource(R.string.settings_accessibility), { Links.open(context, Links.ACCESSIBILITY) },
                Modifier.testTag("setting-accessibility"))
            PageRow(stringResource(R.string.settings_licences), { licences = true },
                Modifier.focusRequester(backToLicences).testTag("setting-licences"))
            Text(
                stringResource(R.string.settings_version, BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE),
                Modifier.padding(vertical = 8.dp).testTag("setting-version"),
                style = EpicTheme.type.body,
                color = c.text,
            )
        }
    }
}

/** A section's heading, with room above it and (but for the first) a [divider] from the section before. */
@Composable
private fun Section(title: String, divider: Boolean = true) {
    Column(Modifier.padding(top = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (divider) HorizontalDivider(thickness = EpicTheme.colors.edgeWidth, color = EpicTheme.colors.outlineSubtle)
        SectionHeading(title, Modifier.padding(top = 8.dp))
    }
}

/** What the controls under it set ("Theme"): read before them. Onboarding's comfort page has them too. */
@Composable
internal fun Label(text: String) {
    Text(text, Modifier.padding(top = 8.dp), style = EpicTheme.type.label, color = EpicTheme.colors.text)
}

/**
 * Appearance › Theme: Match my phone, Light, Dark or High contrast, each with its swatch. Onboarding's comfort page has
 * it too (the same tags: the two are never on screen together).
 */
@Composable
internal fun ThemeChoices(settings: AppSettings) {
    val words = rememberWords()
    ChoiceGroup(
        ThemeChoice.entries, settings.theme, { settings.theme = it },
        label = { words.themeWords(it) },
        modifier = Modifier.testTag("setting-theme"),
        tag = { "setting-theme-${it.key}" },
        decoration = { ThemeSwatch(it) },
    )
}

/** Appearance › Text size: Standard, Large or Larger, and a line of a story at that size. Onboarding's too. */
@Composable
internal fun TextSizeChoices(settings: AppSettings) {
    val words = rememberWords()
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        ChoiceGroup(
            AppSettings.TEXT_SCALES, settings.textScale, { settings.textScale = it },
            label = { words.textSizeWords(it) },
            modifier = Modifier.testTag("setting-textScale"),
            tag = { "setting-textScale-$it" },
        )
        TextSizePreview()
    }
}

/** A line about the setting above it. */
@Composable
private fun Note(text: String) {
    Text(text, style = EpicTheme.type.secondary, color = EpicTheme.colors.textMuted)
}

/** Music volume's steps in words: "Off", "25%" and so on. */
internal fun Words.volumeWords(volume: Float): String =
    if (volume == 0f) text(R.string.volume_off) else text(R.string.volume_percent, (volume * 100).toInt())

/** Text size's steps in words: Standard, Large, Larger. */
internal fun Words.textSizeWords(scale: Float): String = text(
    when {
        scale >= 1.3f -> R.string.text_size_larger
        scale >= 1.15f -> R.string.text_size_large
        else -> R.string.text_size_standard
    },
)

/** Time to answer's choices in words: Normal, Longer, Longest. */
internal fun Words.answerTimeWords(time: AnswerTime): String = text(
    when (time) {
        AnswerTime.NORMAL -> R.string.answer_time_normal
        AnswerTime.LONGER -> R.string.answer_time_longer
        AnswerTime.LONGEST -> R.string.answer_time_longest
    },
)

/** Theme's choices in words: Match my phone, Light, Dark, High contrast. */
internal fun Words.themeWords(theme: ThemeChoice): String = text(
    when (theme) {
        ThemeChoice.SYSTEM -> R.string.theme_system
        ThemeChoice.LIGHT -> R.string.theme_light
        ThemeChoice.DARK -> R.string.theme_dark
        ThemeChoice.CONTRAST -> R.string.theme_contrast
    },
)

/**
 * A theme as a picture: a square of its palette (both of them, side by side, for Match my phone), with letters in its
 * heading colour. Only a picture: the choice's words say which theme it is.
 */
@Composable
private fun ThemeSwatch(theme: ThemeChoice) {
    val palettes = when (theme) {
        ThemeChoice.SYSTEM -> listOf(EpicColors.light, EpicColors.dark)
        ThemeChoice.LIGHT -> listOf(EpicColors.light)
        ThemeChoice.DARK -> listOf(EpicColors.dark)
        ThemeChoice.CONTRAST -> listOf(EpicColors.contrast)
    }
    val shape = RoundedCornerShape(8.dp)
    Row(
        Modifier
            .clearAndSetSemantics {}
            .border(2.dp, EpicTheme.colors.outline, shape)
            .padding(2.dp),
    ) {
        for (p in palettes) {
            Box(Modifier.size(40.dp).background(p.background, shape), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.theme_swatch), style = EpicTheme.type.label, color = p.heading)
            }
        }
    }
}

/** A line of a story as the transcript shows it, at the text size chosen: the size to judge by. */
@Composable
private fun TextSizePreview() {
    val c = EpicTheme.colors
    val shape = RoundedCornerShape(16.dp)
    Column(
        Modifier
            .fillMaxWidth()
            .background(c.surface, shape)
            .border(c.edgeWidth, c.outlineSubtle, shape)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(stringResource(R.string.text_size_preview), style = EpicTheme.type.speaker, color = c.textMuted)
        Text(stringResource(R.string.text_size_preview_line), style = EpicTheme.type.transcript, color = c.text)
    }
}

/**
 * Whether the app may use the microphone, as it changes (back from the phone's settings, too): allowed, with a tick;
 * or off, with "Allow microphone" while Android still asks, else "Open phone settings", where only the player can
 * turn it on. Said by TalkBack as it changes, and so is Android refusing for good when it's asked from here.
 */
@Composable
private fun MicrophoneStatus(onAnswer: (Boolean) -> Unit) {
    val c = EpicTheme.colors
    val context = LocalContext.current
    val activity = context.findActivity()
    var allowed by remember { mutableStateOf(Permissions.micGranted(context)) }
    // Refused for good: Android doesn't ask any more.
    var refused by remember { mutableStateOf(false) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        allowed = granted
        refused = !granted && activity != null &&
            !ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.RECORD_AUDIO)
        onAnswer(granted)
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) allowed = Permissions.micGranted(context)
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    val (icon, words, color) = if (allowed) {
        Triple(Icons.Default.Mic, stringResource(R.string.microphone_allowed), c.success)
    } else {
        Triple(Icons.Outlined.MicOff, stringResource(R.string.microphone_off), c.text)
    }
    MicStatusLine(icon, words, color)
    if (!allowed) {
        // Asked here and refused for good (or Android had stopped asking, and answered at once): said, as the button
        // the player just pressed turns into the way to the phone's settings.
        if (refused) {
            StatusText(stringResource(R.string.microphone_refused), Modifier.testTag("setting-micRefused"))
        }
        val canAsk = !refused && (!Permissions.micAsked || (activity != null &&
            ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.RECORD_AUDIO)))
        if (canAsk) {
            EpicButton(stringResource(R.string.allow_microphone), {
                Permissions.micAsked = true
                ask.launch(Manifest.permission.RECORD_AUDIO)
            }, Modifier.fillMaxWidth().testTag("setting-micAllow"), icon = Icons.Default.Mic)
        } else {
            EpicButton(stringResource(R.string.open_phone_settings), { Permissions.openAppSettings(context) },
                Modifier.fillMaxWidth().testTag("setting-micSettings"), kind = ButtonKind.Secondary)
        }
    }
}

/** The microphone's state as an icon and words, said by TalkBack as it changes. */
@Composable
private fun MicStatusLine(icon: ImageVector, words: String, color: Color) {
    Row(
        Modifier
            .testTag("setting-mic")
            .semantics(mergeDescendants = true) { liveRegion = LiveRegionMode.Polite },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(24.dp))
        Spacer(Modifier.width(8.dp))
        Text(words, style = EpicTheme.type.body, color = color)
    }
}

/**
 * Delete my usage data: asked first ("Delete your usage data?"), then the server is asked to delete everything this
 * phone sent under its random ID, and what happened is said under the button (a live region, so TalkBack says it
 * too). With [sharing] off, the app forgot its random ID as it was turned off: nothing can be found to delete, and the
 * words say why.
 */
@Composable
private fun DeleteUsageData(onDelete: suspend () -> UsageDeletion, sharing: Boolean) {
    var confirming by remember { mutableStateOf(false) }
    var deleting by remember { mutableStateOf(false) }
    // What the last deletion said, its words fixed as it answered (turning sharing on or off after doesn't change them).
    var said by remember { mutableStateOf<Pair<String, StatusKind>?>(null) }
    val sharingNow by rememberUpdatedState(sharing)
    val scope = rememberCoroutineScope()
    val words = rememberWords()
    EpicButton(stringResource(R.string.settings_delete_usage), { confirming = true },
        Modifier.fillMaxWidth().testTag("setting-deleteUsageData"), kind = ButtonKind.Secondary, busy = deleting,
        enabled = !deleting)
    said?.let { (text, kind) -> StatusText(text, Modifier.testTag("setting-deleteUsageData-result"), kind = kind) }
    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text(stringResource(R.string.delete_usage_title)) },
            text = { Text(stringResource(R.string.delete_usage_text)) },
            confirmButton = {
                EpicButton(stringResource(R.string.delete), {
                    confirming = false
                    deleting = true
                    said = null
                    scope.launch {
                        said = words.deletionWords(onDelete(), sharingNow)
                        deleting = false
                    }
                }, Modifier.testTag("delete-confirm"), kind = ButtonKind.Text)
            },
            dismissButton = {
                EpicButton(stringResource(R.string.cancel), { confirming = false }, Modifier.testTag("delete-cancel"),
                    kind = ButtonKind.Text)
            },
            modifier = Modifier.windowTestTags(),
        )
    }
}

/**
 * What Delete my usage data says when it's done, and how: deleted, the server not reached, or nothing to find (none
 * sent under the random ID; or, with [sharing] off, the ID forgotten as it was turned off). iOS: SettingsView.swift.
 */
internal fun Words.deletionWords(result: UsageDeletion, sharing: Boolean): Pair<String, StatusKind> = when (result) {
    UsageDeletion.DELETED -> text(R.string.delete_usage_done) to StatusKind.Success
    UsageDeletion.FAILED -> text(R.string.delete_usage_failed) to StatusKind.Error
    UsageDeletion.NOTHING_SENT ->
        text(if (sharing) R.string.delete_usage_nothing else R.string.delete_usage_nothing_off) to StatusKind.Info
}

/** Where the font's licence is, in the app (content/app/licences/, merged into the assets). */
private const val FONT_LICENCE = "app/licences/OFL-AtkinsonHyperlegibleNext.txt"

/**
 * Settings › Licences: the font's licence, the SIL Open Font License, in full, as the licence asks of every copy
 * (docs/DESIGN.md › Type). Its heading takes the focus as it shows; Back returns to Settings.
 */
@Composable
fun LicencesPage(onBack: () -> Unit) {
    val c = EpicTheme.colors
    val context = LocalContext.current
    // Null while it's read; empty if the build has no licence file (placeholder content).
    val blocks by produceState<List<LicenceBlock>?>(null) {
        value = withContext(Dispatchers.IO) {
            runCatching { context.assets.open(FONT_LICENCE).bufferedReader().use { licenceBlocks(it.readText()) } }
                .getOrDefault(emptyList())
        }
    }
    Column(
        Modifier
            .fillMaxSize()
            .background(c.background)
            .verticalScroll(rememberScrollState())
            .padding(start = 16.dp, top = 8.dp, end = 16.dp, bottom = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Column(Modifier.readableWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            IconActionButton(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back), onBack,
                Modifier.testTag("licences-back"))
            ScreenHeader(stringResource(R.string.licences_heading), Modifier.testTag("licences-heading").focusOnAppear())
            SectionHeading(stringResource(R.string.licences_font))
            Text(
                stringResource(R.string.licences_font_text),
                style = EpicTheme.type.body,
                color = c.text,
            )
            val text = blocks
            when {
                text == null -> Spacer(Modifier.height(48.dp))
                text.isEmpty() -> LinkRow(stringResource(R.string.licences_font_link),
                    { Links.open(context, "https://openfontlicense.org") })
                else -> for (block in text) {
                    if (block.heading) {
                        Text(block.text, Modifier.padding(top = 8.dp).semantics { heading() },
                            style = EpicTheme.type.itemTitle, color = c.heading)
                    } else {
                        Text(block.text, style = EpicTheme.type.body, color = c.text, textAlign = TextAlign.Start)
                    }
                }
            }
        }
    }
}

/** A part of a licence's text: a heading ("PREAMBLE"), or a paragraph. */
data class LicenceBlock(val text: String, val heading: Boolean)

/**
 * A licence's plain text as headings and paragraphs to show at any text size: paragraphs are separated by blank lines,
 * and the line breaks within one (made for an 80-column file) become spaces. A paragraph's first line is a heading
 * when it starts with a word in capitals and doesn't end a sentence ("PREAMBLE", "PERMISSION & CONDITIONS", "SIL OPEN
 * FONT LICENSE Version 1.1 - 26 February 2007"). Lines of dashes are rules, and go. Every word stays, in its order.
 */
fun licenceBlocks(text: String): List<LicenceBlock> {
    val blocks = mutableListOf<LicenceBlock>()
    val paragraph = mutableListOf<String>()
    fun flush() {
        if (paragraph.isEmpty()) return
        val first = paragraph.first()
        val firstWord = first.substringBefore(' ')
        val heading = firstWord.length >= 3 && firstWord.all { it in 'A'..'Z' } && first.last() !in ".,:;"
        if (heading) blocks += LicenceBlock(first, heading = true)
        val rest = if (heading) paragraph.drop(1) else paragraph
        if (rest.isNotEmpty()) blocks += LicenceBlock(rest.joinToString(" "), heading = false)
        paragraph.clear()
    }
    for (raw in text.lines()) {
        val line = raw.trim()
        when {
            line.isEmpty() -> flush()
            line.length >= 3 && line.all { it == '-' } -> flush()
            else -> paragraph += line
        }
    }
    flush()
    return blocks
}
