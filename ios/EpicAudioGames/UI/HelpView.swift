// ui/HelpScreen.kt: the Help tab (its topics, each topic's page read aloud with the word being read marked, the list
// and the page side by side on a wide window), and the help sheet a game opens.

import EpicAppCore
import SwiftUI

/**
 * The Help tab (docs/DESIGN.md › Help): its heading, a row per topic (its title and a line about it), Show the welcome
 * again, and how to reach us. A topic opens its page: its heading, Listen (the page read aloud in Jessica's voice, the
 * word being read marked), its paragraphs and its links. The [pages] are this app's, from content/app/app.json
 * (AppManifest: iOS's own and those for both), in its order: the words shown are the words spoken.
 *
 * On a phone (a compact width) the page is pushed over the list, and its Back button (VoiceOver's escape, Escape on a
 * keyboard) returns to the list, VoiceOver back on the topic's row; on a wider window (an iPad, a Mac) the list and the
 * page are side by side (NavigationSplitView, neither of which can be hidden), the topic showing marked as selected.
 * [topic] is the one open (AppModel keeps it while other tabs show); [onTopic] opens one, or closes it (nil). A topic
 * opened here takes VoiceOver to its heading; one still open as the tab comes back doesn't (a tab picked keeps the
 * focus). One opened from elsewhere ([focusTopic]: Settings › How to play) takes it once, as one opened here does, and
 * [onTopicFocused] says so. Android's HelpScreen.kt (which has two panes from 840 dp; here, from the regular width).
 */
struct HelpView: View {
    let pages: [HelpPage]
    let audio: any PageAudio
    let topic: String?
    let onTopic: @MainActor (String?) -> Void
    let onShowWelcome: @MainActor () -> Void
    var focusTopic = false
    var onTopicFocused: @MainActor () -> Void = {}
    /// VoiceOver to the open topic's heading: a new number each time that's asked for, nil once it's done.
    @State private var focusHeading: Int? = nil
    /// VoiceOver back on a topic's row as its page closes.
    @AccessibilityFocusState private var row: String?
    @Environment(\.epicWindow) private var window
    @Environment(\.epicColors) private var c

    var body: some View {
        Group {
            if window.widthClass == .compact {
                stack
            } else {
                split
            }
        }
        .onChange(of: focusTopic, initial: true) { _, now in
            guard now else { return }
            if page != nil { focusHeading = (focusHeading ?? 0) + 1 }
            onTopicFocused()
        }
        .onChange(of: topic) { was, now in
            // A topic closed: VoiceOver back on its row, once the list is in sight again (a phone's page slides away).
            guard let was, now == nil else { return }
            Task { @MainActor in
                do { try await Task.sleep(for: A11y.focusAfterTransition) } catch { return }
                row = was
            }
        }
    }

    /// The open topic's page, if this app has it.
    private var page: HelpPage? {
        topic.flatMap { id in pages.first { $0.id == id } }
    }

    /// A topic opened here: its page, VoiceOver on its heading.
    private func openTopic(_ id: String) {
        focusHeading = (focusHeading ?? 0) + 1
        onTopic(id)
    }

    /// A phone's: the list, the topic's page pushed over it.
    private var stack: some View {
        NavigationStack {
            list(beside: false)
                // The list has its own heading; the bar shows only on a page (its Back button, named "Help").
                .navigationTitle("Help")
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(item: Binding(get: { page?.id }, set: { onTopic($0) })) { id in
                    if let shown = pages.first(where: { $0.id == id }) {
                        topicPage(shown, focusDelay: A11y.focusAfterTransition)
                            // A title of its own would say the topic twice: the bar has only its Back.
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar(.visible, for: .navigationBar)
                    }
                }
        }
    }

    /// A wider window's: the list beside the topic's page (or a word to pick one), both always there.
    private var split: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            list(beside: true)
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                if let page {
                    topicPage(page)
                        .id(page.id)
                } else {
                    NoTopic()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            // An edge between the two (they're the same colour), as Android draws.
            .overlay(alignment: .leading) {
                c.outlineSubtle
                    .frame(width: c.edgeWidth)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func list(beside: Bool) -> some View {
        HelpList(
            pages: pages, beside: beside, selected: page?.id, row: $row, onTopic: openTopic,
            onShowWelcome: onShowWelcome)
    }

    /// [shown]'s page; VoiceOver to its heading [focusDelay] after it's asked for (later on a phone, once it's pushed).
    private func topicPage(_ shown: HelpPage, focusDelay: Duration = A11y.focusDelay) -> some View {
        TopicPage(
            page: shown, audio: audio, focus: focusHeading, focusDelay: focusDelay, onFocused: { focusHeading = nil })
            // VoiceOver's escape (the two-finger scrub), and Escape on a keyboard: back to the list, as a phone's
            // Back button is.
            .accessibilityAction(.escape) { onTopic(nil) }
            .background { ShortcutKey(title: "All help topics", key: .escape) { onTopic(nil) } }
    }
}

/**
 * The list: the heading "Help", a line about Listen, a row per topic, then (in the tab, not the help sheet) Show the
 * welcome again and Contact. A build with no help in it (placeholder content) has the website's instead. [beside]: on
 * a wide window, the topic [selected] showing beside it; [row] is where VoiceOver goes back to as a topic closes.
 * HelpScreen.kt's HelpList.
 */
private struct HelpList: View {
    let pages: [HelpPage]
    let beside: Bool
    let selected: String?
    let row: AccessibilityFocusState<String?>.Binding
    let onTopic: @MainActor (String) -> Void
    /// Show the welcome again, and Contact: the tab's (the help sheet has neither).
    let onShowWelcome: (@MainActor () -> Void)?
    /// VoiceOver to the heading (the help sheet's list, shown again from a page): a new number each time.
    var focusHeading: Int?
    /// The screen's background, or the sheet's.
    var background: Color?
    @Environment(\.openURL) private var openURL
    @Environment(\.epicColors) private var c

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ScreenHeader("Help")
                    .accessibilityIdentifier("help-heading")
                    .focusWhen(focusHeading)
                if pages.isEmpty {
                    Text("How to play, using VoiceOver, packs and purchases: it's all on our website.")
                        .epicFont(.body)
                        .foregroundStyle(c.text)
                    LinkRow(text: "Help and support") { openURL(Links.support) }
                        .accessibilityIdentifier("help-support")
                } else {
                    Text("Open a topic to read it. Listen reads it to you.")
                        .epicFont(.body)
                        .foregroundStyle(c.text)
                    VStack(spacing: 0) {
                        ForEach(pages.indices, id: \.self) { i in
                            if i > 0 {
                                c.outlineSubtle
                                    .frame(height: c.edgeWidth)
                                    .accessibilityHidden(true)
                            }
                            let page = pages[i]
                            TopicRow(page: page, selected: beside ? page.id == selected : nil) { onTopic(page.id) }
                                .accessibilityFocused(row, equals: page.id)
                        }
                    }
                }
                if let onShowWelcome {
                    ShopDivider()
                    PageRow(text: "Show the welcome again", action: onShowWelcome)
                        .accessibilityIdentifier("help-welcome")
                    SectionHeading("Contact")
                        .padding(.top, 8)
                    Text("We'd love to hear from you, especially about how well the app works for you.")
                        .epicFont(.body)
                        .foregroundStyle(c.text)
                    LinkRow(text: "Email \(Links.email)") { openURL(Links.mailto) }
                        .accessibilityIdentifier("help-email")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableWidth()
            .padding(EdgeInsets(top: 16, leading: 16, bottom: 28, trailing: 16))
        }
        .scrollIndicators(.hidden)
        .background { (background ?? c.background).ignoresSafeArea() }
    }
}

/**
 * A topic in the list: its title and its line, the whole row a button (Voice Control knows it by its title). Beside its
 * page on a wide window, the row showing is [selected] (VoiceOver: "Selected"), with the accent bar on its leading edge
 * and an edge round it, so every row there is inset to make room; [selected] is nil on a phone and in the help sheet,
 * where nothing shows beside the list. HelpScreen.kt's TopicRow.
 */
private struct TopicRow: View {
    let page: HelpPage
    let selected: Bool?
    let action: @MainActor () -> Void
    @Environment(\.epicColors) private var c

    private static let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        let marked = selected == true
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title)
                        .epicFont(.itemTitle)
                        .foregroundStyle(c.text)
                    if !page.summary.isEmpty {
                        Text(page.summary)
                            .epicFont(.secondary)
                            .foregroundStyle(c.textMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                IconView(icon: .keyboardArrowRight, size: 24, color: c.text)
            }
            .padding(.leading, selected == nil ? 0 : 16)
            .padding(.trailing, 8)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .background {
                if marked { c.surface }
            }
            .overlay(alignment: .leading) {
                if marked { c.accent.frame(width: 4) }
            }
            .clipShape(Self.shape)
            .overlay {
                if marked { Self.shape.strokeBorder(c.outline, lineWidth: 2 * c.edgeWidth) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .hoverEffect()
        .accessibilityAddTraits(marked ? .isSelected : [])
        .accessibilityInputLabels(A11y.inputLabels(page.title))
        .accessibilityIdentifier("help-topic-\(page.id)")
    }
}

/// Beside the list on a wide window, before a topic is picked.
private struct NoTopic: View {
    @Environment(\.epicColors) private var c

    var body: some View {
        Text("Pick a topic to read it here.")
            .epicFont(.body)
            .foregroundStyle(c.text)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { c.background.ignoresSafeArea() }
    }
}

/**
 * A help topic's page: its heading (level 1; VoiceOver moves to it a moment after [focus] is asked for, [focusDelay]
 * once it's been pushed or its sheet has risen, and [onFocused] lets the request go), Listen, the paragraphs with the
 * word being read marked, and its links (a web page in the browser, an email in the Mail app). Magic Tap reads it, or
 * stops it, as Listen does. HelpScreen.kt's TopicPage.
 */
struct TopicPage: View {
    let page: HelpPage
    let audio: any PageAudio
    var focus: Int?
    var focusDelay: Duration = A11y.focusDelay
    var onFocused: @MainActor () -> Void = {}
    /// The screen's background, or the sheet's.
    var background: Color?
    /// Listen waiting to start (VoiceOver's moment).
    @State private var waiting: Task<Void, Never>? = nil
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.openURL) private var openURL
    @Environment(\.epicColors) private var c

    var body: some View {
        let clip = AppClip.help(page.id)
        let listen = ListenAction(clip: clip, audio: audio, waiting: $waiting, voiceOver: voiceOver)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ScreenHeader(page.title)
                        .accessibilityIdentifier("help-page-heading")
                        .focusWhen(focus, after: focusDelay, then: onFocused)
                    ListenButton(listen: listen)
                        .accessibilityIdentifier("help-listen")
                    PageParagraphs(page: page, audio: audio, clip: clip, proxy: proxy)
                    ForEach(page.links.indices, id: \.self) { i in
                        let link = page.links[i]
                        LinkRow(text: link.label) {
                            if let url = URL(string: link.url) { openURL(url) }
                        }
                        .accessibilityIdentifier("help-link-\(i)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .readableWidth()
                .padding(EdgeInsets(top: 8, leading: 16, bottom: 28, trailing: 16))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("help-page")
            }
            .scrollIndicators(.hidden)
        }
        .background { (background ?? c.background).ignoresSafeArea() }
        // Magic Tap (two fingers, twice) anywhere on the page: Listen, or Pause (docs/DESIGN.md › Help).
        .accessibilityAction(.magicTap) {
            if listen.available { listen.toggle() }
        }
        // A Listen still waiting to start doesn't, once the page has gone.
        .onDisappear { listen.cancel() }
    }
}

/**
 * Listen and Pause's doing, for the button and for Magic Tap on its page: reads [clip] aloud, or stops it. With
 * VoiceOver on, the reading starts a moment after the tap ([A11y.listenDelay]), so VoiceOver's own sound for the tap
 * comes first, not over the voice; [waiting] is that moment (its page's state). HelpScreen.kt's ListenButton's onClick.
 */
struct ListenAction {
    let clip: AppClip
    let audio: any PageAudio
    let waiting: Binding<Task<Void, Never>?>
    let voiceOver: Bool

    /// The build has the clip: else there's no Listen at all.
    var available: Bool { audio.hasClip(clip) }

    /// Being read, or about to be: the button says Pause.
    var reading: Bool { waiting.wrappedValue != nil || audio.clipPlaying == clip }

    func toggle() {
        if reading {
            cancel()
            if audio.clipPlaying == clip { audio.stopClip() }
        } else if !voiceOver {
            audio.play(clip)
        } else {
            let waiting = self.waiting
            let audio = self.audio
            let clip = self.clip
            waiting.wrappedValue = Task { @MainActor in
                do { try await Task.sleep(for: A11y.listenDelay) } catch { return }
                waiting.wrappedValue = nil
                audio.play(clip)
            }
        }
    }

    /// A Listen still waiting to start doesn't.
    func cancel() {
        waiting.wrappedValue?.cancel()
        waiting.wrappedValue = nil
    }
}

/**
 * Listen: reads its clip aloud, and while it's read (or about to be) it's Pause, which stops it, with the value
 * "Playing" (Android's state). It starts a media session for VoiceOver, which stays quiet after the tap: the voice is
 * what comes next. Not there at all when the build hasn't the clip. HelpScreen.kt's ListenButton.
 */
struct ListenButton: View {
    let listen: ListenAction

    var body: some View {
        if listen.available {
            let reading = listen.reading
            EpicButton(reading ? "Pause" : "Listen", icon: reading ? MaterialIcon.pause : MaterialIcon.playArrow) {
                listen.toggle()
            }
            .accessibilityValue(reading ? "Playing" : "")
            .accessibilityAddTraits(.startsMediaSession)
        }
    }
}

/**
 * A page's paragraphs, the word the voice is on marked while it reads [clip] (as the transcript marks it, and not with
 * Settings › Highlight words as they're spoken off). Without VoiceOver, the paragraph being read is kept in sight as
 * the voice moves on to it (at once with Reduce Motion), so the words can be followed; with it, nothing moves under
 * the player's finger. [proxy] scrolls the page they're on. HelpScreen.kt's PageParagraphs.
 */
struct PageParagraphs: View {
    let page: HelpPage
    let audio: any PageAudio
    let clip: AppClip
    let proxy: ScrollViewProxy
    @Environment(AppSettings.self) private var settings: AppSettings?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.epicReduceMotion) private var reduceMotion
    @Environment(\.epicColors) private var c

    var body: some View {
        let marked = audio.clipPlaying == clip ? audio.highlight : nil
        let highlight = settings?.highlightWords ?? true
        VStack(alignment: .leading, spacing: 12) {
            ForEach(page.text.indices, id: \.self) { i in
                let said = marked?.paragraph == i ? marked?.chars : nil
                Text(transcriptText(page.text[i], saidChars: said, highlight: highlight, wholeLine: true, colors: c))
                    .epicFont(.body)
                    .foregroundStyle(c.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(Self.anchor(i))
            }
        }
        .onChange(of: marked?.paragraph) { _, paragraph in
            guard let paragraph, !voiceOver else { return }
            // As little as it takes to have the whole paragraph in sight (none if it is).
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) {
                proxy.scrollTo(Self.anchor(paragraph), anchor: nil)
            }
        }
    }

    /// A paragraph's place on its page, to scroll to.
    static func anchor(_ paragraph: Int) -> String { "paragraph-\(paragraph)" }
}

/**
 * Help in a game (docs/DESIGN.md › Help sheet): a topic's page, or the list of topics, in a sheet the full height of
 * the screen, over the game (which waits, paused). The page has All help topics, the list's rows open a topic, and
 * Close (or a swipe down, Escape on a keyboard, VoiceOver's escape) closes it. VoiceOver moves to the heading of what
 * it shows as it shows. [topic] is the page showing (nil: the list); [onTopic] changes it. HelpScreen.kt's HelpSheet.
 */
struct HelpSheet: View {
    let pages: [HelpPage]
    let audio: any PageAudio
    let topic: String?
    let onTopic: @MainActor (String?) -> Void
    /// The list shown again from a page: its heading takes VoiceOver's focus, as a page's does.
    @State private var fromPage: Int? = nil
    @AccessibilityFocusState private var row: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.epicColors) private var c

    /// The sheet's corners (presentationCornerRadius), which its edge follows.
    private static let corner: CGFloat = 28

    var body: some View {
        let page = topic.flatMap { id in pages.first { $0.id == id } }
        VStack(spacing: 0) {
            // Side by side while their words fit; with less room (the largest text), one above the other.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    allTopics(page != nil)
                    Spacer(minLength: 0)
                    close
                }
                VStack(alignment: .leading, spacing: 8) {
                    allTopics(page != nil)
                    close
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            // Under the sheet's drag indicator, which floats over it.
            .padding(.top, 24)
            .readableWidth()
            if let page {
                // Each page takes VoiceOver's focus to its heading as it shows (once the sheet has risen).
                TopicPage(
                    page: page, audio: audio, focus: 1, focusDelay: A11y.focusAfterTransition,
                    background: c.surfaceRaised)
                    .id(page.id)
            } else {
                HelpList(
                    pages: pages, beside: false, selected: nil, row: $row, onTopic: { onTopic($0) },
                    onShowWelcome: nil, focusHeading: fromPage, background: c.surfaceRaised)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Self.corner)
        .presentationBackground {
            // Edged round its top and down its sides, as the store sheet is: in the contrast palettes the sheet is the
            // colour of what's under it.
            ZStack {
                c.surfaceRaised
                RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                    .stroke(c.outlineSubtle, lineWidth: 2 * c.edgeWidth)
                    .padding(.bottom, -60)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("help-sheet")
        // Magic Tap on the list has nothing to read: taken here, so iOS doesn't play the game (what's playing) under
        // the sheet. A page's own reads it, or stops it (TopicPage).
        .accessibilityAction(.magicTap) {}
    }

    /// Back from a page to the list, as words (what it does, and what Voice Control hears); none on the list.
    @ViewBuilder private func allTopics(_ onPage: Bool) -> some View {
        if onPage {
            EpicButton("All help topics", kind: .text, icon: .arrowBack) {
                fromPage = (fromPage ?? 0) + 1
                onTopic(nil)
            }
            .accessibilityIdentifier("help-all-topics")
        }
    }

    /// Close: Escape on a keyboard is Close too (docs/DESIGN.md › Tablets… › Keyboard).
    private var close: some View {
        EpicButton("Close", kind: .secondary) { dismiss() }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("help-close")
    }
}
