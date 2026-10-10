package com.epicaudiogames.app.ui

import android.Manifest
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.epicaudiogames.app.AppClip
import com.epicaudiogames.app.AppManifest
import com.epicaudiogames.app.AppSettings
import com.epicaudiogames.app.MicPrimed
import com.epicaudiogames.app.PageAudio
import com.epicaudiogames.app.Permissions
import com.epicaudiogames.app.R
import com.epicaudiogames.app.rememberWords
import com.epicaudiogames.app.ui.theme.EpicTheme
import com.epicaudiogames.app.ui.theme.LocalScreenReader

/**
 * Onboarding (docs/DESIGN.md › Onboarding), on the first run and again from Help or Settings ("Show the welcome
 * again"): Welcome (read aloud, by itself the first time without a screen reader; and the line about usage data, with
 * Turn off), Answer out loud (why the microphone, before Android asks for it), Make it comfortable (the theme and the
 * text size), Playing with TalkBack (only with it on), and You're ready. Back, Next and Skip are buttons, with nothing
 * to swipe; the step is in words ("Step 2 of 4"), and each page's heading takes the focus as it shows.
 *
 * Back (or Escape) goes to the page before; on the first page it closes onboarding opened again ([reopened]), and the
 * first run's has nothing before it (the app is left, and onboarding is there next time). [onDone] says whether it was
 * completed (Start playing) or skipped; [onMicAnswer] hears what the player said to Android's microphone question.
 * The [settings] it changes take effect at once (the theme, the text size, usage data, settings.micPrimed). The pages
 * and steps are OnboardingPage's and OnboardingStep's (AppFlow.kt, tested on the JVM). iOS: OnboardingView.swift.
 */
@Composable
fun Onboarding(
    settings: AppSettings,
    manifest: AppManifest?,
    audio: PageAudio,
    reopened: Boolean,
    onMicAnswer: (Boolean) -> Unit,
    onDone: (completed: Boolean) -> Unit,
) {
    val c = EpicTheme.colors
    val screenReader = LocalScreenReader.current
    var page by rememberSaveable { mutableStateOf(OnboardingPage.WELCOME) }
    val step = OnboardingStep.of(page, screenReader)
    // Leaving the welcome, its reading stops.
    val stopWelcome = { if (audio.clipPlaying == AppClip.Welcome) audio.stopClip() }
    val go = { to: OnboardingPage ->
        stopWelcome()
        page = to
    }
    val finish = { completed: Boolean ->
        stopWelcome()
        onDone(completed)
    }
    val previous = step.previous
    val back: (() -> Unit)? = when {
        previous != null -> ({ go(previous) })
        reopened -> ({ finish(false) })
        else -> null
    }
    BackHandler(enabled = back != null) { back?.invoke() }
    KeyShortcuts { (it == Shortcut.Escape && back != null).also { escape -> if (escape) back?.invoke() } }
    Column(
        Modifier
            .fillMaxSize()
            .background(c.background)
            .windowInsetsPadding(WindowInsets.safeDrawing),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Skip, on every page but the last (which has Start playing): its room is kept there too, so the heading
        // doesn't jump up, at any text size (the button's there, but not seen, heard, or reached). Over the page that
        // scrolls under it, so it stays whole for TalkBack.
        Row(
            Modifier.aboveScrollingContent().readableWidth().heightIn(min = SKIP_ROW)
                .padding(horizontal = 8.dp, vertical = 4.dp),
            horizontalArrangement = Arrangement.End,
        ) {
            EpicButton(
                stringResource(R.string.onboarding_skip), { finish(false) },
                if (step.last) Modifier.alpha(0f).clearAndSetSemantics {} else Modifier.testTag("onboarding-skip"),
                kind = ButtonKind.Text,
                enabled = !step.last,
            )
        }
        key(page) {
            val scroll = rememberScrollState()
            val follow = remember { ReadingFollower() }
            Column(
                Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .verticalScroll(scroll)
                    .onGloballyPositioned { follow.content = it }
                    .padding(start = 16.dp, top = 4.dp, end = 16.dp, bottom = 24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Column(Modifier.readableWidth().testTag(page.tag), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    when (page) {
                        OnboardingPage.WELCOME -> WelcomePage(step, manifest, audio, settings, scroll, follow)
                        OnboardingPage.MIC -> MicPage(step, settings, onMicAnswer)
                        OnboardingPage.COMFORT -> ComfortPage(step, settings)
                        OnboardingPage.SCREEN_READER -> ScreenReaderPage(step, manifest)
                        OnboardingPage.READY -> ReadyPage(step)
                    }
                }
            }
        }
        HorizontalDivider(thickness = c.edgeWidth, color = c.outlineSubtle)
        Row(
            Modifier.readableWidth().padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (previous != null) {
                EpicButton(stringResource(R.string.back), { go(previous) }, Modifier.weight(1f).testTag("onboarding-back"),
                    kind = ButtonKind.Secondary, icon = Icons.AutoMirrored.Filled.ArrowBack)
            }
            val next = step.next
            if (next == null) {
                EpicButton(stringResource(R.string.onboarding_start), { finish(true) },
                    Modifier.weight(1f).testTag("onboarding-start"))
            } else {
                EpicButton(stringResource(R.string.onboarding_next), { go(next) }, Modifier.weight(1f).testTag("onboarding-next"),
                    icon = Icons.AutoMirrored.Filled.ArrowForward)
            }
        }
    }
}

/** The row Skip is in: the button's 48 dp, and room round it. */
private val SKIP_ROW = 56.dp

/**
 * A page's heading, with its step before it: one element for TalkBack ("Step 2 of 4, Answer out loud, heading"),
 * which takes the focus a moment after the page shows.
 */
@Composable
private fun StepHeading(step: OnboardingStep, title: String) {
    val c = EpicTheme.colors
    Column(
        Modifier
            .testTag("onboarding-heading")
            .focusOnAppear(step.page)
            .semantics(mergeDescendants = true) { heading() },
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(step.words(rememberWords()), style = EpicTheme.type.label, color = c.textMuted)
        Text(title, style = EpicTheme.type.title, color = c.heading)
    }
}

/** A paragraph of a page. */
@Composable
private fun Paragraph(text: String) {
    Text(text, style = EpicTheme.type.body, color = EpicTheme.colors.text)
}

/**
 * The welcome: its words (the manifest's, as Jessica says them) with Listen, read aloud by itself the first time
 * onboarding shows without a screen reader (settings.welcomePlayed: only once); with one on, Listen is there for the
 * player to press. Then what the app shares, and Turn off.
 */
@Composable
private fun WelcomePage(
    step: OnboardingStep,
    manifest: AppManifest?,
    audio: PageAudio,
    settings: AppSettings,
    scroll: ScrollState,
    follow: ReadingFollower,
) {
    val welcome = manifest?.welcome
    val screenReader = LocalScreenReader.current
    StepHeading(step, welcome?.title ?: stringResource(R.string.onboarding_welcome))
    LaunchedEffect(Unit) {
        if (!settings.welcomePlayed && !screenReader && audio.hasClip(AppClip.Welcome)) {
            audio.play(AppClip.Welcome)
            settings.welcomePlayed = true
        }
    }
    if (welcome != null) {
        ListenButton(AppClip.Welcome, audio, Modifier.testTag("onboarding-listen"))
        PageParagraphs(welcome, audio.clipPlaying == AppClip.Welcome, audio.highlight, scroll, follow)
    } else {
        Paragraph(stringResource(R.string.onboarding_welcome_text))
    }
    UsageData(settings)
}

/**
 * Usage data, said plainly before any is sent (it's on unless turned off; docs/DESIGN.md › Usage data), with Turn
 * off; turned off, the words say so (TalkBack too, as they change) and the button turns it on again, so the
 * player's focus stays where it was.
 */
@Composable
private fun UsageData(settings: AppSettings) {
    val c = EpicTheme.colors
    val shape = RoundedCornerShape(16.dp)
    val on = settings.analytics
    Column(
        Modifier
            .fillMaxWidth()
            .background(c.surface, shape)
            .border(c.edgeWidth, c.outlineSubtle, shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (on) {
            Paragraph(stringResource(R.string.onboarding_usage))
        } else {
            StatusText(stringResource(R.string.onboarding_usage_off), Modifier.testTag("analytics-is-off"))
        }
        EpicButton(
            stringResource(if (on) R.string.turn_off else R.string.turn_on),
            { settings.analytics = !on },
            Modifier.testTag(if (on) "analytics-off" else "analytics-on"),
            kind = ButtonKind.Secondary,
            description = stringResource(if (on) R.string.turn_off_usage else R.string.turn_on_usage),
        )
    }
}

/**
 * Answer out loud: why the app needs the microphone (and, Android 13 and later, why Android will ask about
 * notifications too), before Android asks; Allow microphone asks (both), and Not now doesn't. The answer is said as
 * it comes (a polite live region) and kept as settings.micPrimed: a game asks again as it opens unless the player
 * said Not now, or refused here (docs/DESIGN.md › Onboarding). Allowed already, it just says so.
 */
@Composable
private fun MicPage(step: OnboardingStep, settings: AppSettings, onMicAnswer: (Boolean) -> Unit) {
    val context = LocalContext.current
    StepHeading(step, stringResource(R.string.onboarding_mic))
    Paragraph(stringResource(R.string.onboarding_mic_why))
    Paragraph(stringResource(R.string.onboarding_mic_private))
    // What this visit's question got: null until it's answered.
    var answer by rememberSaveable { mutableStateOf<Boolean?>(null) }
    val notifications = remember { Permissions.notificationPermission(context) }
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        val granted = Permissions.micGranted(context)
        settings.micPrimed = if (granted) MicPrimed.ALLOWED else MicPrimed.DECLINED
        answer = granted
        onMicAnswer(granted)
    }
    val allowed = answer ?: if (Permissions.micGranted(context)) true else null
    val result = Modifier.testTag("onboarding-mic-result")
    when (allowed) {
        true -> StatusText(stringResource(R.string.onboarding_mic_on), result, kind = StatusKind.Success)
        false -> StatusText(stringResource(R.string.onboarding_mic_later), result)
        null -> {
            if (notifications != null) {
                Paragraph(stringResource(R.string.onboarding_mic_notifications))
            }
            EpicButton(stringResource(R.string.allow_microphone), {
                Permissions.micAsked = true
                Permissions.notificationsAsked = true
                ask.launch(listOfNotNull(Manifest.permission.RECORD_AUDIO, notifications).toTypedArray())
            }, Modifier.fillMaxWidth().testTag("onboarding-mic-allow"), icon = Icons.Default.Mic)
            EpicButton(stringResource(R.string.not_now), {
                settings.micPrimed = MicPrimed.DECLINED
                answer = false
            }, Modifier.fillMaxWidth().testTag("onboarding-mic-not-now"), kind = ButtonKind.Secondary)
        }
    }
}

/** Make it comfortable: the theme and the text size, as Settings has them, taking effect as they're picked. */
@Composable
private fun ComfortPage(step: OnboardingStep, settings: AppSettings) {
    StepHeading(step, stringResource(R.string.onboarding_comfort))
    Paragraph(stringResource(R.string.onboarding_comfort_text))
    Label(stringResource(R.string.settings_theme))
    ThemeChoices(settings)
    Label(stringResource(R.string.settings_text_size))
    TextSizeChoices(settings)
    Paragraph(stringResource(R.string.onboarding_comfort_more))
}

/**
 * Playing with TalkBack: the help topic's own words (content/app/app.json's "screen-reader": talking with the
 * picture, the headphones' button, the mic not opening by itself), and where to find them again.
 */
@Composable
private fun ScreenReaderPage(step: OnboardingStep, manifest: AppManifest?) {
    val topic = manifest?.topic("screen-reader")
    StepHeading(step, stringResource(R.string.onboarding_screen_reader))
    if (topic != null) {
        for (text in topic.text) Paragraph(text)
        Paragraph(stringResource(R.string.onboarding_screen_reader_where, topic.title))
    } else {
        Paragraph(stringResource(R.string.onboarding_screen_reader_text))
    }
}

/** You're ready: what to do next, and where help is. Start playing goes to Games. */
@Composable
private fun ReadyPage(step: OnboardingStep) {
    StepHeading(step, stringResource(R.string.onboarding_ready))
    Paragraph(stringResource(R.string.onboarding_ready_text))
    Paragraph(stringResource(R.string.onboarding_ready_help))
}
