// ui/Onboarding.kt: the first run's pages (the welcome read aloud, the microphone, comfort, VoiceOver, ready), and
// again from Help or Settings.

import EpicAppCore
import SwiftUI

/**
 * Onboarding (docs/DESIGN.md › Onboarding), on the first run and again from Help or Settings ("Show the welcome
 * again"): Welcome (read aloud, by itself the first time without VoiceOver; and the line about usage data, with Turn
 * off), Answer out loud (why the microphone, before iOS asks for it and for speech recognition), Make it comfortable
 * (the theme and the text size), Playing with VoiceOver (only with it on), and You're ready. Back, Next and Skip are
 * buttons, with nothing to swipe; the step is in words ("Step 2 of 4"), and each page's heading takes VoiceOver's focus
 * as it shows.
 *
 * Back (VoiceOver's escape, Escape on a keyboard) goes to the page before; on the first page it closes onboarding
 * opened again ([reopened]), and the first run's has nothing before it. [onDone] says whether it was completed (Start
 * playing) or skipped; [onMicAnswer] hears what the player said to iOS's microphone question. The [settings] it changes
 * take effect at once (the theme, the text size, usage data, settings.micPrimed). [screenReader]: VoiceOver is on (its
 * page shows, and the welcome waits for Listen). The pages and steps are OnboardingPage's and OnboardingStep's
 * (AppFlow.swift, unit-tested). Android's Onboarding.kt.
 */
struct OnboardingView: View {
    let settings: AppSettings
    let manifest: AppManifest?
    let audio: any PageAudio
    let reopened: Bool
    let screenReader: Bool
    let onMicAnswer: @MainActor (Bool) -> Void
    let onDone: @MainActor (Bool) -> Void
    @State private var page = OnboardingPage.welcome
    /// The welcome's Listen waiting to start (VoiceOver's moment).
    @State private var waiting: Task<Void, Never>? = nil
    @Environment(\.epicColors) private var c

    var body: some View {
        let step = OnboardingStep.of(page, screenReader: screenReader)
        let back = backAction(step)
        VStack(spacing: 0) {
            // Skip, on every page but the last (which has Start playing): its room is kept there too, so the heading
            // doesn't jump up.
            HStack {
                Spacer(minLength: 0)
                if !step.last {
                    EpicButton("Skip", kind: .text) { finish(completed: false) }
                        .accessibilityIdentifier("onboarding-skip")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minHeight: 56)
            .readableWidth()
            // Each page from its top, scrolled on its own.
            ScrollViewReader { proxy in
                ScrollView {
                    content(step, proxy)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .readableWidth()
                        .padding(EdgeInsets(top: 4, leading: 16, bottom: 24, trailing: 16))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(page.tag)
                }
                .scrollIndicators(.hidden)
            }
            .id(page)
            c.outlineSubtle
                .frame(height: c.edgeWidth)
                .accessibilityHidden(true)
            // Side by side while their words fit on one line each; with less room (the largest text) one above the
            // other, so no word is broken.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { moves(step) }
                VStack(spacing: 12) { moves(step) }
            }
            .padding(16)
            .readableWidth()
        }
        .background { c.background.ignoresSafeArea() }
        .background {
            ShortcutKey(title: "Back", key: .escape, enabled: back != nil) { back?() }
        }
        .accessibilityAction(.escape) { back?() }
        // Magic Tap on the welcome: Listen, or Pause, as on a Help topic.
        .accessibilityAction(.magicTap) {
            if page == .welcome && welcomeListen.available { welcomeListen.toggle() }
        }
    }

    /// Back (not on the first page), and Next, or Start playing on the last.
    @ViewBuilder private func moves(_ step: OnboardingStep) -> some View {
        if let previous = step.previous {
            EpicButton("Back", kind: .secondary, icon: .arrowBack, wide: true) { go(previous) }
                .accessibilityIdentifier("onboarding-back")
        }
        if let next = step.next {
            EpicButton("Next", icon: .arrowForward, wide: true) { go(next) }
                .accessibilityIdentifier("onboarding-next")
        } else {
            EpicButton("Start playing", wide: true) { finish(completed: true) }
                .accessibilityIdentifier("onboarding-start")
        }
    }

    @ViewBuilder private func content(_ step: OnboardingStep, _ proxy: ScrollViewProxy) -> some View {
        switch page {
        case .welcome:
            WelcomePage(
                step: step, manifest: manifest, audio: audio, settings: settings, listen: welcomeListen,
                screenReader: screenReader, proxy: proxy)
        case .mic:
            MicPage(step: step, settings: settings, onMicAnswer: onMicAnswer)
        case .comfort:
            ComfortPage(step: step, settings: settings)
        case .screenReader:
            ScreenReaderPage(step: step, manifest: manifest)
        case .ready:
            ReadyPage(step: step)
        }
    }

    /// Listen on the welcome (its button, and Magic Tap there).
    private var welcomeListen: ListenAction {
        ListenAction(clip: .welcome, audio: audio, waiting: $waiting, voiceOver: screenReader)
    }

    /// Back: the page before; on the first, onboarding opened again closes; the first run's has none.
    private func backAction(_ step: OnboardingStep) -> (@MainActor () -> Void)? {
        if let previous = step.previous { return { go(previous) } }
        if reopened { return { finish(completed: false) } }
        return nil
    }

    private func go(_ to: OnboardingPage) {
        stopWelcome()
        page = to
    }

    private func finish(completed: Bool) {
        stopWelcome()
        onDone(completed)
    }

    /// Leaving the welcome, its reading stops (and a Listen waiting to start doesn't).
    private func stopWelcome() {
        welcomeListen.cancel()
        if audio.clipPlaying == .welcome { audio.stopClip() }
    }
}

/**
 * A page's heading, with its step before it: one element for VoiceOver ("Step 2 of 4, Answer out loud", a heading),
 * which takes its focus a moment after the page shows. Onboarding.kt's StepHeading.
 */
private struct StepHeading: View {
    let step: OnboardingStep
    let title: String
    @Environment(\.epicColors) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(step.words)
                .epicFont(.label)
                .foregroundStyle(c.textMuted)
            Text(title)
                .epicFont(.title)
                .foregroundStyle(c.heading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step.words), \(title)")
        .accessibilityAddTraits(.isHeader)
        .accessibilityHeading(.h1)
        .accessibilityIdentifier("onboarding-heading")
        .focusOnAppear(step.page)
    }
}

/// A paragraph of a page.
private struct Paragraph: View {
    let text: String
    @Environment(\.epicColors) private var c

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .epicFont(.body)
            .foregroundStyle(c.text)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/**
 * The welcome: its words (the manifest's, as Jessica says them) with Listen, read aloud by itself the first time
 * onboarding shows without VoiceOver (settings.welcomePlayed: only once); with it on, Listen is there for the player to
 * press. Then what the app shares, and Turn off.
 */
private struct WelcomePage: View {
    let step: OnboardingStep
    let manifest: AppManifest?
    let audio: any PageAudio
    let settings: AppSettings
    let listen: ListenAction
    let screenReader: Bool
    let proxy: ScrollViewProxy

    var body: some View {
        let welcome = manifest?.welcome
        VStack(alignment: .leading, spacing: 16) {
            StepHeading(step: step, title: welcome?.title ?? "Welcome")
            if let welcome {
                ListenButton(listen: listen)
                    .accessibilityIdentifier("onboarding-listen")
                PageParagraphs(page: welcome, audio: audio, clip: .welcome, proxy: proxy)
            } else {
                Paragraph("Welcome to Epic Audio Games! The games talk to you, and you answer out loud.")
            }
            UsageDataNotice(settings: settings)
        }
        .onAppear {
            if !settings.welcomePlayed && !screenReader && audio.hasClip(.welcome) {
                audio.play(.welcome)
                settings.welcomePlayed = true
            }
        }
    }
}

/**
 * Usage data, said plainly before any is sent (it's on unless turned off; docs/DESIGN.md › Usage data), with Turn off;
 * turned off, the words say so (and VoiceOver, as it happens) and the button turns it on again, so VoiceOver stays
 * where it was. Turning it off here forgets everything recorded so far (AppModel tells UsageData): on the first run
 * nothing has been sent before this page. Onboarding.kt's UsageData (a name the usage data itself has here).
 */
private struct UsageDataNotice: View {
    let settings: AppSettings
    @Environment(\.epicColors) private var c

    private static let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
    static let offWords = "Usage data is off. You can turn it on again in Settings, under Privacy."

    var body: some View {
        let on = settings.analytics
        VStack(alignment: .leading, spacing: 12) {
            if on {
                Paragraph(
                    "We collect usage data under a random ID to improve the games — never what you say, and nothing "
                        + "about accessibility settings.")
            } else {
                StatusText(text: Self.offWords)
                    .accessibilityIdentifier("analytics-is-off")
            }
            EpicButton(
                on ? "Turn off" : "Turn on", kind: .secondary,
                description: on ? "Turn off usage data" : "Turn on usage data"
            ) {
                settings.analytics = !on
                // No game listens during onboarding.
                A11y.announce(on ? Self.offWords : "Usage data is on.", unlessListening: false)
            }
            .accessibilityIdentifier(on ? "analytics-off" : "analytics-on")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.surface, in: Self.shape)
        .overlay { Self.shape.strokeBorder(c.outlineSubtle, lineWidth: c.edgeWidth) }
    }
}

/**
 * Answer out loud: why the app needs the microphone (and that iOS will ask about speech recognition too), before iOS
 * asks; Allow microphone asks (both), and Not now doesn't. The answer is said as it comes (VoiceOver is told) and kept
 * as settings.micPrimed: a game asks again as it opens unless the player said Not now, or refused here
 * (docs/DESIGN.md › Onboarding; AppModel.askForTheMic). Allowed already, it just says so. Onboarding.kt's MicPage.
 */
private struct MicPage: View {
    let step: OnboardingStep
    let settings: AppSettings
    let onMicAnswer: @MainActor (Bool) -> Void
    /// What this visit's question got: nil until it's answered.
    @State private var answer: Bool? = nil
    @State private var asking = false

    static let allowedWords = "The microphone is on."
    static let notNowWords = "No problem: you can tap or type, and allow it later in Settings."

    var body: some View {
        let allowed = answer ?? (MicPermission.granted ? true : nil)
        VStack(alignment: .leading, spacing: 16) {
            StepHeading(step: step, title: "Answer out loud")
            Paragraph(
                "The games ask you questions, and you answer out loud. To hear you, the app needs the microphone.")
            Paragraph("What you say is turned into words by your phone's speech recognition, and never sent to us.")
            switch allowed {
            case .some(true):
                StatusText(text: Self.allowedWords, kind: .success)
                    .accessibilityIdentifier("onboarding-mic-result")
            case .some(false):
                StatusText(text: Self.notNowWords)
                    .accessibilityIdentifier("onboarding-mic-result")
            case .none:
                if MicPermission.speechUnasked {
                    Paragraph("iOS will ask about speech recognition too: it's what turns what you say into words.")
                }
                EpicButton("Allow microphone", icon: .mic, enabled: !asking, wide: true) { ask() }
                    .accessibilityIdentifier("onboarding-mic-allow")
                EpicButton("Not now", kind: .secondary, wide: true) {
                    settings.micPrimed = .declined
                    answer = false
                    // No game listens during onboarding.
                    A11y.announce(Self.notNowWords, unlessListening: false)
                }
                .accessibilityIdentifier("onboarding-mic-not-now")
            }
        }
    }

    /// iOS's questions (the mic, then speech recognition), then what's allowed, kept and said.
    private func ask() {
        asking = true
        Task { @MainActor in
            let granted = await MicPermission.request()
            asking = false
            settings.micPrimed = granted ? .allowed : .declined
            answer = granted
            onMicAnswer(granted)
            A11y.announce(granted ? Self.allowedWords : Self.notNowWords, unlessListening: false)
        }
    }
}

/// Make it comfortable: the theme and the text size, as Settings has them, taking effect as they're picked.
private struct ComfortPage: View {
    let step: OnboardingStep
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeading(step: step, title: "Make it comfortable")
            Paragraph("Choose the colours and the size of the words. You can change them any time in Settings.")
            SettingLabel("Theme")
            ThemeChoices(settings: settings)
            SettingLabel("Text size")
            TextSizeChoices(settings: settings)
            Paragraph("More in Settings: the font, the voice's speed, and how the story's words are shown.")
        }
    }
}

/**
 * Playing with VoiceOver: the help topic's own words (content/app/app.json's "screen-reader": the picture, Magic Tap,
 * the mic not opening by itself), and where to find them again.
 */
private struct ScreenReaderPage: View {
    let step: OnboardingStep
    let manifest: AppManifest?

    var body: some View {
        let topic = manifest?.topic("screen-reader")
        VStack(alignment: .leading, spacing: 16) {
            StepHeading(step: step, title: "Playing with VoiceOver")
            if let topic {
                ForEach(topic.text.indices, id: \.self) { i in
                    Paragraph(topic.text[i])
                }
                Paragraph("You'll find this in Help too, under \(topic.title).")
            } else {
                Paragraph(
                    "With VoiceOver on, the microphone doesn't open by itself. At the top of a game is a picture: "
                        + "double tap it to talk, then say your answer after the rising sound. A Magic Tap, a "
                        + "two-finger double tap, does the same, and so does the button on your headphones.")
            }
        }
    }
}

/// You're ready: what to do next, and where help is. Start playing goes to Games.
private struct ReadyPage: View {
    let step: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            StepHeading(step: step, title: "You're ready")
            Paragraph("Pick a game, put on your headphones, and answer out loud.")
            Paragraph("Help has its own tab, whenever you need it, and every topic can be read to you.")
        }
    }
}
