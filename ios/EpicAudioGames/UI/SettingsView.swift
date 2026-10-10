// ui/SettingsScreen.kt: the Settings tab (sound and voice, the microphone, appearance, the transcript, privacy, help
// and about) and its Licences page.

import SwiftUI
import UIKit

/**
 * The Settings tab (docs/DESIGN.md › Settings): one page of level-2 sections, the most useful for blind players first.
 * Sound and voice, Microphone, Appearance, Transcript, Privacy, Help and about; every control is a whole row, saved as
 * it changes ([settings], AppSettings.swift). The sound settings take effect in the games, and each lets the player hear
 * what it does: [onPlaySample] plays the voice at its speed; [onPreviewIntro] the intro's sound, as Play the intro sound
 * is turned on; [onPreviewCue] the listening sound and tick as the mic would open, when either is turned on; and
 * [onPreviewMusic] a few seconds of a game's music at each Music volume picked (Off: silence). [onHowToPlay] opens the
 * Help tab on playing with your voice, [onShowWelcome] shows the welcome and the first run's pages again (onboarding),
 * and [onDeleteUsageData] asks the server to delete what this device sent under its random ID. [onMicAnswer] hears
 * what the player said to the microphone's question asked here. Licences is a page of its own, pushed within the tab:
 * its Back button, VoiceOver's escape and Escape on a keyboard return, VoiceOver to the Licences row. Android's
 * SettingsScreen.kt.
 */
struct SettingsView: View {
    @Bindable var settings: AppSettings
    let onPlaySample: @MainActor () -> Void
    let onHowToPlay: @MainActor () -> Void
    let onShowWelcome: @MainActor () -> Void
    let onDeleteUsageData: @MainActor () async -> UsageDeletion
    let onMicAnswer: @MainActor (Bool) -> Void
    var onPreviewCue: @MainActor () -> Void = {}
    var onPreviewIntro: @MainActor () -> Void = {}
    var onPreviewMusic: @MainActor () -> Void = {}
    @State private var licences = false
    /// VoiceOver back on the Licences row, as the page closes.
    @AccessibilityFocusState private var backToLicences: Bool
    /// The phone's own Reduce Motion: Settings' switch is on with it, and can't be turned off here.
    @Environment(\.accessibilityReduceMotion) private var phoneReduces
    @Environment(\.openURL) private var openURL
    @Environment(\.epicColors) private var c

    var body: some View {
        NavigationStack {
            page
                // The page has its own heading; the bar shows only on Licences (its Back button, named "Settings").
                .navigationTitle("Settings")
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(isPresented: $licences) { LicencesPage() }
        }
        .onChange(of: licences) { was, now in
            guard was && !now else { return }
            // Once the page has slid away: iOS moves VoiceOver itself as the transition ends (as Help's topics do).
            Task { @MainActor in
                do { try await Task.sleep(for: A11y.focusAfterTransition) } catch { return }
                backToLicences = true
            }
        }
    }

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader("Settings")
                    .accessibilityIdentifier("settings-heading")
                soundAndVoice
                microphone
                appearance
                transcript
                privacy
                helpAndAbout
            }
            .readableWidth()
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 28, trailing: 16))
        }
        .scrollIndicators(.hidden)
        .background { c.background.ignoresSafeArea() }
    }

    // ----- The sections -----

    @ViewBuilder private var soundAndVoice: some View {
        SettingsSection("Sound and voice", divider: false)
        SettingLabel("Voice speed")
        SpeedStepper(value: settings.voiceSpeed, steps: AppSettings.voiceSpeeds) { settings.voiceSpeed = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("setting-voiceSpeed")
        EpicButton("Play a sample", kind: .secondary, icon: .playArrow, wide: true, action: onPlaySample)
            .accessibilityIdentifier("setting-voiceSample")
        // Turned on, it lets the player hear what it will play as the app starts.
        SwitchRow(
            title: "Play the intro sound",
            isOn: Binding(get: { settings.introSound }, set: { on in
                settings.introSound = on
                if on { onPreviewIntro() }
            }),
            hint: "The Epic Audio Games sound as the app starts", identifier: "setting-introSound")
        // Turned on, each lets the player hear (or feel) what it does: the mic opening, as it will in a game.
        SwitchRow(
            title: "Listening sounds",
            isOn: Binding(get: { settings.listeningSounds }, set: { on in
                settings.listeningSounds = on
                if on { onPreviewCue() }
            }),
            hint: "A sound as the microphone opens, and as it closes", identifier: "setting-listeningSounds")
        SwitchRow(
            title: "Vibrate when listening starts",
            isOn: Binding(get: { settings.listeningHaptics }, set: { on in
                settings.listeningHaptics = on
                if on { onPreviewCue() }
            }),
            identifier: "setting-listeningHaptics")
        SettingLabel("Music volume")
        // Each step picked (the one already picked too) plays the music at it, to judge it by; Off, nothing.
        ChoiceGroup(
            choices: AppSettings.musicVolumes, selected: settings.musicVolume,
            onSelect: { volume in
                settings.musicVolume = volume
                onPreviewMusic()
            },
            label: volumeWords, tag: { "setting-musicVolume-\(Int(($0 * 100).rounded()))" })
            .accessibilityIdentifier("setting-musicVolume")
        SettingNote("Some scenes have their music mixed in and stay as they are.")
        SettingLabel("Time to answer")
        ChoiceGroup(
            choices: AnswerTime.allCases, selected: settings.answerTime, onSelect: { settings.answerTime = $0 },
            label: { time in
                switch time {
                case .normal: "Normal"
                case .longer: "Longer"
                case .longest: "Longest"
                }
            },
            hint: { "\($0.duration.components.seconds) seconds" },
            tag: { "setting-answerTime-\($0.rawValue)" })
            .accessibilityIdentifier("setting-answerTime")
    }

    @ViewBuilder private var microphone: some View {
        SettingsSection("Microphone")
        SettingLabel("Open the microphone by itself")
        ChoiceGroup(
            choices: MicAuto.allCases, selected: settings.micAuto, onSelect: { settings.micAuto = $0 },
            label: { policy in
                switch policy {
                case .notWithScreenReader: "Not when a screen reader is on"
                case .always: "Always"
                case .never: "Never"
                }
            },
            hint: { policy in
                switch policy {
                case .notWithScreenReader: "With VoiceOver on, you open it yourself"
                case .always: "Even with VoiceOver on"
                case .never: "You open it yourself, every time"
                }
            },
            tag: { "setting-micAuto-\($0.rawValue)" })
            .accessibilityIdentifier("setting-micAuto")
        MicrophoneStatus(onAnswer: onMicAnswer)
    }

    @ViewBuilder private var appearance: some View {
        SettingsSection("Appearance")
        SettingLabel("Theme")
        ThemeChoices(settings: settings)
        SettingLabel("Text size")
        TextSizeChoices(settings: settings)
        SettingLabel("Font")
        ChoiceGroup(
            choices: FontChoice.allCases, selected: settings.font, onSelect: { settings.font = $0 },
            label: { $0 == .atkinson ? "Atkinson Hyperlegible" : "Phone's font" },
            hint: { $0 == .atkinson ? "Easier to read" : nil },
            tag: { "setting-font-\($0.rawValue)" })
            .accessibilityIdentifier("setting-font")
        // With the phone's own Reduce Motion on, it's on here too, and can't be turned off here.
        SwitchRow(
            title: "Reduce motion",
            isOn: Binding(get: { settings.reduceMotion || phoneReduces }, set: { settings.reduceMotion = $0 }),
            hint: phoneReduces ? "On in your phone's settings" : "Nothing pulses, and the story jumps rather than scrolls",
            enabled: !phoneReduces, identifier: "setting-reduceMotion")
    }

    @ViewBuilder private var transcript: some View {
        SettingsSection("Transcript")
        SwitchRow(
            title: "Highlight words as they're spoken", isOn: $settings.highlightWords,
            identifier: "setting-highlightWords")
        SwitchRow(
            title: "Show the whole line at once", isOn: $settings.wholeLine,
            hint: "Off: each word shows as it's spoken", identifier: "setting-wholeLine")
        SwitchRow(
            title: "Show who's speaking", isOn: $settings.speakerNames,
            hint: "VoiceOver always says who's speaking", identifier: "setting-speakerNames")
    }

    @ViewBuilder private var privacy: some View {
        SettingsSection("Privacy")
        SwitchRow(
            title: "Share usage data", isOn: $settings.analytics,
            hint: "Helps us see which games and screens people use, under a random ID. Never your name, email or "
                + "voice, never what you say or type, and nothing about accessibility settings.",
            identifier: "setting-analytics")
        DeleteUsageData(settings: settings, onDelete: onDeleteUsageData)
        LinkRow(text: "Privacy policy") { openURL(Links.privacy) }
            .accessibilityIdentifier("setting-privacy")
    }

    @ViewBuilder private var helpAndAbout: some View {
        SettingsSection("Help and about")
        PageRow(text: "How to play", action: onHowToPlay)
            .accessibilityIdentifier("setting-howToPlay")
        PageRow(text: "Show the welcome again", action: onShowWelcome)
            .accessibilityIdentifier("setting-welcome")
        LinkRow(text: "Support") { openURL(Links.support) }
            .accessibilityIdentifier("setting-support")
        LinkRow(text: "Accessibility statement") { openURL(Links.accessibility) }
            .accessibilityIdentifier("setting-accessibility")
        PageRow(text: "Licences") { licences = true }
            .accessibilityFocused($backToLicences)
            .accessibilityIdentifier("setting-licences")
        Text(Self.version)
            .epicFont(.body)
            .foregroundStyle(c.text)
            .padding(.vertical, 8)
            .accessibilityIdentifier("setting-version")
    }

    /// "Version 1.0 (202610091200)": the version and the build, as the App Store and TestFlight show them.
    private static var version: String {
        let info = Bundle.main.infoDictionary
        let name = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(name) (\(build))"
    }
}

/// A section's heading, with room above it and (but for the first) a [divider] from the section before.
private struct SettingsSection: View {
    let title: String
    var divider = true
    @Environment(\.epicColors) private var c

    init(_ title: String, divider: Bool = true) {
        self.title = title
        self.divider = divider
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if divider {
                c.outlineSubtle
                    .frame(height: c.edgeWidth)
                    .accessibilityHidden(true)
            }
            SectionHeading(title)
                .padding(.top, 8)
        }
        .padding(.top, 16)
    }
}

/// What the controls under it set ("Theme"): read before them. Onboarding's comfort page has them too (Android's
/// Label).
struct SettingLabel: View {
    let text: String
    @Environment(\.epicColors) private var c

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .epicFont(.label)
            .foregroundStyle(c.text)
            .padding(.top, 8)
    }
}

/// A line about the setting above it.
private struct SettingNote: View {
    let text: String
    @Environment(\.epicColors) private var c

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .epicFont(.secondary)
            .foregroundStyle(c.textMuted)
    }
}

/**
 * Appearance › Theme: Match my phone, Light, Dark or High contrast, each with its swatch, taking effect as it's picked.
 * Onboarding's comfort page has it too (the same identifiers: the two are never on screen together). Android's
 * ThemeChoices.
 */
struct ThemeChoices: View {
    let settings: AppSettings

    var body: some View {
        ChoiceGroup(
            choices: ThemeChoice.allCases, selected: settings.theme, onSelect: { settings.theme = $0 },
            label: { theme in
                switch theme {
                case .system: "Match my phone"
                case .light: "Light"
                case .dark: "Dark"
                case .contrast: "High contrast"
                }
            },
            tag: { "setting-theme-\($0.rawValue)" },
            decoration: { ThemeSwatch(theme: $0) })
            .accessibilityIdentifier("setting-theme")
    }
}

/// Appearance › Text size: Standard, Large or Larger, and a line of a story at that size. Onboarding's too (Android's
/// TextSizeChoices).
struct TextSizeChoices: View {
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChoiceGroup(
                choices: AppSettings.textScales, selected: settings.textScale, onSelect: { settings.textScale = $0 },
                label: textSizeWords, tag: { "setting-textScale-\($0)" })
                .accessibilityIdentifier("setting-textScale")
            TextSizePreview()
        }
    }
}

/// Music volume's steps in words: "Off", "25%" and so on (Android's volumeWords).
nonisolated func volumeWords(_ volume: Double) -> String {
    volume == 0 ? "Off" : "\(Int((volume * 100).rounded()))%"
}

/// Text size's steps in words: Standard, Large, Larger (Android's textSizeWords).
nonisolated func textSizeWords(_ scale: Double) -> String {
    if scale >= 1.3 - 0.001 { return "Larger" }
    if scale >= 1.15 - 0.001 { return "Large" }
    return "Standard"
}

/**
 * A theme as a picture: a square of its palette (both of them, side by side, for Match my phone), with letters in its
 * heading colour. Only a picture, at a fixed size: the choice's words say which theme it is.
 */
private struct ThemeSwatch: View {
    let theme: ThemeChoice
    @Environment(\.epicColors) private var c

    var body: some View {
        let palettes: [EpicColors] = switch theme {
        case .system: [.light, .dark]
        case .light: [.light]
        case .dark: [.dark]
        case .contrast: [.contrast]
        }
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 0) {
            ForEach(palettes.indices, id: \.self) { i in
                Text(verbatim: "Aa")
                    .font(.custom(Atkinson.bold, fixedSize: 18))
                    .foregroundStyle(palettes[i].heading)
                    .frame(width: 40, height: 40)
                    .background(palettes[i].background, in: shape)
            }
        }
        .padding(2)
        .overlay { shape.strokeBorder(c.outline, lineWidth: 2) }
        .accessibilityHidden(true)
    }
}

/// A line of a story as the transcript shows it, at the text size chosen: the size to judge by.
private struct TextSizePreview: View {
    @Environment(\.epicColors) private var c

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            Text("Preview")
                .epicFont(.speaker)
                .foregroundStyle(c.textMuted)
            Text("Gribbo: Who goes there? Speak up, or the moon gets it!")
                .epicFont(.transcript)
                .foregroundStyle(c.text)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.surface, in: shape)
        .overlay { shape.strokeBorder(c.outlineSubtle, lineWidth: c.edgeWidth) }
    }
}

/**
 * Whether the games may use the microphone (and speech recognition, which iOS asks for alongside it), as it changes
 * (back from the phone's Settings, too): allowed, with a tick; or off, with "Allow microphone" while iOS can still ask,
 * else "Open phone settings", where only the player can turn it on. VoiceOver is told when it changes, and why the
 * button the player just pressed turned into the way to the phone's settings. Android's MicrophoneStatus; iOS knows a
 * refusal at once, so it never offers to ask when the answer can only be no.
 */
private struct MicrophoneStatus: View {
    let onAnswer: @MainActor (Bool) -> Void
    @State private var allowed: Bool
    @State private var canAsk: Bool
    /// Asked here and refused: iOS doesn't ask again.
    @State private var refused = false
    @State private var asking = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.epicColors) private var c

    init(onAnswer: @escaping @MainActor (Bool) -> Void) {
        self.onAnswer = onAnswer
        _allowed = State(initialValue: MicPermission.granted)
        _canAsk = State(initialValue: MicPermission.canAsk)
    }

    var body: some View {
        let words = allowed ? "The microphone is allowed" : "The microphone is off"
        let color = allowed ? c.success : c.text
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                IconView(icon: allowed ? .mic : .micOffOutlined, size: 24, color: color)
                Text(words)
                    .epicFont(.body)
                    .foregroundStyle(color)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(words)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("setting-mic")
            if !allowed {
                if refused {
                    StatusText(text: Self.refusal)
                        .accessibilityIdentifier("setting-micRefused")
                }
                if canAsk {
                    EpicButton("Allow microphone", icon: .mic, enabled: !asking, wide: true) { ask() }
                        .accessibilityIdentifier("setting-micAllow")
                } else {
                    EpicButton("Open phone settings", kind: .secondary, wide: true) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .accessibilityIdentifier("setting-micSettings")
                }
            }
        }
        // Back from the phone's Settings (or anywhere): what's allowed now. Not while asking: the system's questions
        // make the app inactive too, and the answer is said once, below.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !asking { read(announcing: true) }
        }
    }

    static let refusal = "Your phone won't ask again. To use the microphone, turn it on in your phone's settings."

    /// The system's questions (the mic, then speech recognition), then what's allowed, said; a refusal says what now.
    private func ask() {
        asking = true
        Task { @MainActor in
            let granted = await MicPermission.request()
            asking = false
            onAnswer(granted)
            refused = !granted
            read(announcing: false)
            // Settings has no game listening.
            A11y.announce(granted ? "The microphone is allowed" : "The microphone is off. " + Self.refusal,
                          unlessListening: false)
        }
    }

    /// What iOS says is allowed; VoiceOver hears a change, if [announcing].
    private func read(announcing: Bool) {
        let now = MicPermission.granted
        let changed = now != allowed
        allowed = now
        canAsk = MicPermission.canAsk
        if now { refused = false }
        if announcing && changed {
            A11y.announce(now ? "The microphone is allowed" : "The microphone is off", unlessListening: false)
        }
    }
}

/**
 * Delete my usage data: asked first ("Delete your usage data?"), then the server is asked to delete everything this
 * device sent under its random ID, and what happened is said under the button (and by VoiceOver). With Share usage
 * data off ([settings]), the app forgot its random ID as it was turned off: nothing can be found to delete, and the
 * words say why ([deletionWords]). Android's DeleteUsageData.
 */
private struct DeleteUsageData: View {
    let settings: AppSettings
    let onDelete: @MainActor () async -> UsageDeletion
    @State private var confirming = false
    @State private var deleting = false
    /// What the last deletion said, its words fixed as it answered (turning sharing on or off after doesn't change
    /// them).
    @State private var said: (words: String, kind: StatusKind)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EpicButton("Delete my usage data", kind: .secondary, enabled: !deleting, busy: deleting, wide: true) {
                confirming = true
            }
            .accessibilityIdentifier("setting-deleteUsageData")
            if let said {
                StatusText(text: said.words, kind: said.kind)
                    .accessibilityIdentifier("setting-deleteUsageData-result")
            }
        }
        .alert("Delete your usage data?", isPresented: $confirming) {
            Button("Delete", role: .destructive) { delete() }
                .accessibilityIdentifier("delete-confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("delete-cancel")
        } message: {
            Text("We'll delete the usage data this phone has sent us, and the app will use a new random ID.")
        }
    }

    private func delete() {
        deleting = true
        said = nil
        Task { @MainActor in
            let result = await onDelete()
            // Said as Share usage data is now: off, the random ID was forgotten as it was turned off.
            let outcome = deletionWords(result, sharing: settings.analytics)
            said = outcome
            deleting = false
            A11y.announce(outcome.words, unlessListening: false)
        }
    }
}

/**
 * What Delete my usage data says when it's done, and how: deleted, the server not reached, or nothing to find (none
 * sent under the random ID; or, with [sharing] off, the ID forgotten as it was turned off). Android's deletionWords
 * (SettingsScreen.kt).
 */
func deletionWords(_ result: UsageDeletion, sharing: Bool) -> (words: String, kind: StatusKind) {
    switch result {
    case .deleted:
        return ("Your usage data is deleted.", .success)
    case .failed:
        return ("Couldn't reach our server. Please try again.", .error)
    case .nothingSent where sharing:
        return ("There's nothing to delete: the app hasn't sent any usage data under its random ID.", .info)
    case .nothingSent:
        return (
            "There's nothing to delete. The app forgot its random ID when usage data was turned off, so what it sent "
                + "before can't be found, and we delete all usage data after 13 months.", .info)
    }
}

/**
 * Settings › Licences: the font's licence, the SIL Open Font License, in full, as the licence asks of every copy
 * (docs/DESIGN.md › Type), from the app's content (Content/app/licences/). Its heading takes VoiceOver's focus as it
 * shows; the bar's Back (or Escape) returns to Settings. Without the file (a build with no content), a link to the
 * licence's website. Android's LicencesPage.
 */
struct LicencesPage: View {
    /// Nil while it's read; empty if the build has no licence file.
    @State private var blocks: [LicenceBlock]?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.epicColors) private var c

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader("Licences")
                    .accessibilityIdentifier("licences-heading")
                    // Once it's been pushed: iOS moves VoiceOver to the bar's Back as the push ends.
                    .focusOnAppear("licences", after: A11y.focusAfterTransition)
                SectionHeading("Atkinson Hyperlegible Next")
                Text("The font the app's words are shown in, made to be easy to read by the Braille Institute. It's "
                    + "used under the SIL Open Font License 1.1:")
                    .epicFont(.body)
                    .foregroundStyle(c.text)
                if let blocks {
                    if blocks.isEmpty {
                        LinkRow(text: "The SIL Open Font License, on its website") { openURL(Self.website) }
                    } else {
                        ForEach(blocks.indices, id: \.self) { i in
                            let block = blocks[i]
                            if block.heading {
                                Text(block.text)
                                    .epicFont(.itemTitle)
                                    .foregroundStyle(c.heading)
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityHeading(.h3)
                                    .padding(.top, 8)
                            } else {
                                Text(block.text)
                                    .epicFont(.body)
                                    .foregroundStyle(c.text)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableWidth()
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 28, trailing: 16))
        }
        .scrollIndicators(.hidden)
        .background { c.background.ignoresSafeArea() }
        // A title of its own would say "Licences" twice: the bar has only its Back.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .background { ShortcutKey(title: "Back", key: .escape) { dismiss() } }
        .task { blocks = Self.read() }
    }

    static let website = URL(string: "https://openfontlicense.org")!

    /// The licence as the app has it (bundle_content.sh copies content/app/), as headings and paragraphs.
    private static func read() -> [LicenceBlock] {
        guard let url = Bundle.main.url(
            forResource: "OFL-AtkinsonHyperlegibleNext", withExtension: "txt", subdirectory: "Content/app/licences"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return [] }
        return licenceBlocks(text)
    }
}

/// A part of a licence's text: a heading ("PREAMBLE"), or a paragraph. Android's LicenceBlock.
nonisolated struct LicenceBlock: Equatable, Sendable {
    let text: String
    let heading: Bool
}

/**
 * A licence's plain text as headings and paragraphs to show at any text size: paragraphs are separated by blank lines,
 * and the line breaks within one (made for an 80-column file) become spaces. A paragraph's first line is a heading when
 * it starts with a word in capitals and doesn't end a sentence ("PREAMBLE", "PERMISSION & CONDITIONS", "SIL OPEN FONT
 * LICENSE Version 1.1 - 26 February 2007"). Lines of dashes are rules, and go. Every word stays, in its order.
 * Android's licenceBlocks.
 */
nonisolated func licenceBlocks(_ text: String) -> [LicenceBlock] {
    var blocks: [LicenceBlock] = []
    var paragraph: [String] = []
    func flush() {
        guard let first = paragraph.first else { return }
        let firstWord = first.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let capitals = firstWord.count >= 3 && firstWord.allSatisfy { ("A"..."Z").contains($0) }
        let heading = capitals && !".,:;".contains(first.last ?? ".")
        if heading { blocks.append(LicenceBlock(text: first, heading: true)) }
        let rest = heading ? Array(paragraph.dropFirst()) : paragraph
        if !rest.isEmpty { blocks.append(LicenceBlock(text: rest.joined(separator: " "), heading: false)) }
        paragraph = []
    }
    // Each line, blank ones too ("\r\n" is one Character in Swift, a newline like "\n").
    for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty || (line.count >= 3 && line.allSatisfy { $0 == "-" }) {
            flush()
        } else {
            paragraph.append(line)
        }
    }
    flush()
    return blocks
}
