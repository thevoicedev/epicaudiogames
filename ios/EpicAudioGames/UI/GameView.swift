// ui/GameScreen.kt (GameScreen, GameHeader, TalkingCircle and Paused): the game screen, its talking circle, and the
// pause.

import EpicAppCore
import SwiftUI
import UIKit

/**
 * The game, a chat: the header, the talking circle (the game's picture in a ring that shows what it's doing), the
 * transcript as it's spoken with the question's options at its end, and the answer bar: typing and the mic. At an
 * end, the end panel. At accessibility text sizes the layout is compact: the title moves into the transcript, the
 * circle shrinks and the answer bar stacks (docs/DESIGN.md › Type); nothing stops growing with the text. On a wide
 * window (an expanded one, or a medium one on its side) the transcript has a pane of its own beside the rest, read in
 * the same order as on a phone (docs/DESIGN.md › The game on wide windows). [onStore] opens the game's store sheet,
 * from its menu or a locked end; [onHelp] the help sheet on "Playing with your voice", from its menu or the pause (the
 * game waits for it, paused: AppModel.openHelpSheet).
 *
 * VoiceOver: Magic Tap does what a tap on the circle does (skips the voice, carries on after a pause, or starts and
 * stops listening); Escape (the two finger scrub) leaves the game; as the game opens, VoiceOver moves to the circle.
 * A keyboard: Space is the circle, unless the answer box has the keys, and Escape pauses or carries on (at an end, it
 * leaves); off while the store sheet or the help sheet is over the game ([keys]). GameScreen.kt's GameScreen.
 */
struct GameView: View {
    let game: GameController
    var keys = true
    var onHelp: @MainActor () -> Void = {}
    let onStore: @MainActor (ShopSource) -> Void
    /// The mic tapped with the mic refused: the alert leading to Settings.
    @State private var micOff = false
    /// The answer box has the keys (Space types there).
    @State private var typing = false
    /// What's typed in the answer box, kept here so it stays when the window changes layout (AnswersPanel).
    @State private var text = ""
    @Environment(\.openURL) private var openURL
    @Environment(\.epicWindow) private var window
    @Environment(\.epicColors) private var c
    @Environment(\.epicType) private var type

    var body: some View {
        let compact = type.isAccessibilitySize
        ZStack {
            Group {
                if window.gameHasTwoPanes {
                    twoPanes(compact)
                } else {
                    onePane(compact)
                }
            }
            // Paused, VoiceOver finds only the pause (its heading and buttons): what's under it can't be touched either.
            .accessibilityHidden(game.paused)
            if game.paused {
                PausedOverlay(game: game, onHelp: onHelp)
            }
        }
        .background { c.background.ignoresSafeArea() }
        .background { GameKeys(game: game, typing: typing, enabled: keys && !micOff, onCircle: magicTap) }
        .accessibilityAction(.escape) { game.leave() }
        .accessibilityAction(.magicTap) { magicTap() }
        // The screen stays on while the game talks or listens; paused, or at an end, it may sleep.
        .onChange(of: !game.paused && game.end == nil, initial: true) { _, awake in
            UIApplication.shared.isIdleTimerDisabled = awake
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .alert("The microphone is off", isPresented: $micOff) {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Not now", role: .cancel) {}
        } message: {
            Text("To answer out loud, allow the microphone and speech recognition in Settings. You can always tap or "
                + "type instead.")
        }
    }

    /// A phone's game: one column, the transcript taking the room the rest leaves.
    private func onePane(_ compact: Bool) -> some View {
        VStack(spacing: 0) {
            GameHeader(game: game, showTitle: !compact, onHelp: onHelp) { onStore(.menu) }
                .fixedSize(horizontal: false, vertical: true)
            TalkingCircle(game: game, compact: compact, onTap: magicTap)
                .fixedSize(horizontal: false, vertical: true)
            FeedView(game: game, compact: compact)
                .frame(maxHeight: .infinity)
            answers(compact)
        }
    }

    /**
     * The game on a wide window: on the leading side (40%), the header, the talking circle and its status line, then
     * the question's options and the answer bar (or the end panel); on the other, the transcript. VoiceOver goes
     * through it as on a phone: the header and the circle, the transcript, then the answers (GameScreen.kt's
     * TwoPanes, by its traversal indexes).
     */
    private func twoPanes(_ compact: Bool) -> some View {
        let options = game.end == nil ? game.ask?.buttons ?? [] : []
        return PaneSplit(fraction: 0.4) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    GameHeader(game: game, showTitle: !compact, onHelp: onHelp) { onStore(.menu) }
                        .fixedSize(horizontal: false, vertical: true)
                    TalkingCircle(game: game, compact: compact, onTap: magicTap)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .contain)
                .accessibilitySortPriority(3)
                VStack(spacing: 0) {
                    ScrollView {
                        if !options.isEmpty {
                            AnswerChips(game: game, buttons: options)
                                .padding(16)
                                .readableWidth()
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: .infinity)
                    answers(compact)
                }
                .accessibilityElement(children: .contain)
                .accessibilitySortPriority(1)
            }
            .overlay(alignment: .trailing) {
                c.outlineSubtle
                    .frame(width: c.edgeWidth)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            FeedView(game: game, compact: compact, showChips: false)
                .accessibilitySortPriority(2)
        }
        .accessibilityElement(children: .contain)
    }

    /**
     * The end panel, or the answer bar: it gets its room first (Compose measures it before the weighted feed); short of
     * it, the end panel scrolls. The header and the circle keep theirs.
     */
    @ViewBuilder private func answers(_ compact: Bool) -> some View {
        if game.end != nil {
            EndPanel(game: game) { onStore(.lockedEnd) }
                .layoutPriority(1)
        } else {
            AnswersPanel(game: game, compact: compact, text: $text, typing: $typing, onTalk: talk)
                .layoutPriority(1)
        }
    }

    /**
     * The mic button, and the circle waiting for an answer: listen (or stop). Not allowed, it asks for the mic while
     * iOS still can, and else says it's off. Allowed after the ask, the game listens as the tap would have, even
     * where it doesn't by itself (VoiceOver on, D8). What the player said to iOS is usage data (GameScreen.kt's
     * permission result).
     */
    private func talk() {
        if game.micAllowed {
            game.mic()
        } else if MicPermission.canAsk {
            Task {
                let granted = await MicPermission.request()
                game.micAnswered(granted: granted)
                guard granted else { return }
                game.allowMic(listen: true)
            }
        } else {
            micOff = true
        }
    }

    /// The circle tapped, and VoiceOver's Magic Tap (two fingers, twice): carry on, skip the voice, or start or stop
    /// listening (as the headphones' button does, NowPlaying), asking for the mic as the Talk button does.
    private func magicTap() {
        game.magicTap(talk: talk)
    }
}

/**
 * A keyboard in a game (docs/DESIGN.md › Tablets… › Keyboard): Space is the one button, what a tap on the talking circle
 * does (skip, talk, stop listening, carry on), unless the answer box has the keys ([typing]: Space types there) or
 * there's nothing to do yet; Escape pauses, carries on from the pause, and at an end (nothing to pause) leaves the
 * game, its place kept, as Back does. Return in the answer box sends it (AnswersPanel). iPadOS lists them while ⌘ is
 * held, Space by what it does now. Off while something is over the game ([enabled]: the store sheet, the microphone's
 * alert). GameScreen.kt's KeyShortcuts; MainActivity offers Space to the game first there.
 */
private struct GameKeys: View {
    let game: GameController
    let typing: Bool
    let enabled: Bool
    let onCircle: @MainActor () -> Void

    var body: some View {
        let action = game.circleAction
        ZStack {
            ShortcutKey(
                title: action?.label ?? CircleAction.talk.label, key: .space,
                enabled: enabled && !typing && action?.enabled == true, action: onCircle)
            ShortcutKey(title: escapeTitle, key: .escape, enabled: enabled, action: escape)
        }
    }

    private var escapeTitle: String {
        if game.end != nil { return "Leave game" }
        return game.paused ? "Carry on" : "Pause"
    }

    private func escape() {
        if game.end != nil {
            game.leave()
        } else if game.paused {
            game.carryOn()
        } else {
            game.pause()
        }
    }
}

/**
 * Two panes side by side, the first [fraction] of the width and the second the rest, each as tall as the space: the
 * game on a wide window (GameScreen.kt's Row of weights 0.4 and 0.6).
 */
struct PaneSplit: Layout {
    var fraction: CGFloat = 0.4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let first = (bounds.width * fraction).rounded()
        for (i, view) in subviews.enumerated() {
            let x = i == 0 ? bounds.minX : bounds.minX + first
            let width = i == 0 ? first : bounds.width - first
            view.place(
                at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}

/**
 * The header, under the status bar: Back, the game's title (a heading, wrapping onto more lines, never cut short), and
 * the ⋮ menu: Start again, More stories and levels (the store sheet, which pauses the game) and How to play (the help
 * sheet, which pauses it too: [onHelp]). Privacy and Support are in Settings. In the compact layout the title is the
 * transcript's first line instead (FeedView), so it has the width. GameScreen.kt's GameHeader.
 */
private struct GameHeader: View {
    let game: GameController
    let showTitle: Bool
    let onHelp: @MainActor () -> Void
    let onStore: @MainActor () -> Void
    @Environment(\.epicColors) private var c

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                IconActionButton(icon: .arrowBack, description: "Back", action: game.leave)
                if showTitle {
                    // The screen's title: a level-1 heading (docs/DESIGN.md › Everywhere › Headings).
                    Text(game.info.title)
                        .epicFont(.itemTitle)
                        .foregroundStyle(c.heading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityHeading(.h1)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }
                menu
            }
            .padding(4)
            .frame(minHeight: 56)
            .readableWidth()
            c.outlineSubtle.frame(height: c.edgeWidth)
        }
        .background { c.surfaceRaised.ignoresSafeArea(edges: .top) }
    }

    private var menu: some View {
        Menu {
            // Starting again stops the voice and the mic itself: a pause first would end the turn instead.
            Button("Start again") { game.startAgain() }
                .accessibilityIdentifier("menu-start-again")
            if !game.info.packs.isEmpty {
                // The store sheet pauses the game (AppModel.showStore).
                Button("More stories and levels", action: onStore)
                    .accessibilityIdentifier("menu-packs")
            }
            // The help sheet, on playing with your voice: the game waits for it (AppModel.openHelpSheet).
            Button("How to play", action: onHelp)
                .accessibilityIdentifier("menu-how-to-play")
        } label: {
            IconView(icon: .moreVert, size: 24, color: c.text)
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .hoverEffect()
        .accessibilityLabel("More")
        .accessibilityIdentifier("game-menu")
    }
}

/**
 * The game's picture, and its one button: a tap does what Magic Tap does ([onTap]): carries on, skips the voice, or
 * starts or stops listening; with the mic not allowed, it asks for it, as the Talk button does. VoiceOver hears what a
 * tap does and the game's state ([CircleAction]: "Skip", "Speaking"), and stays quiet after it. When the game opens,
 * VoiceOver moves to it a moment later ([A11y.focusDelay]), with nothing announced: the game is talking (docs/DESIGN.md ›
 * Game). At an end it's only a picture, which VoiceOver passes by.
 *
 * What the game is doing shows three ways, never by colour alone: the ring's colour, its style (speaking, a ring that
 * pulses; listening, one as thick as the voice it hears; waiting, a thin dashed one) and the badge's icon. With Reduce
 * Motion, nothing pulses and the listening ring holds at 10 pt. 128 pt, or 88 in the [compact] layout. Under it, what
 * to do, in words. GameScreen.kt's TalkingCircle.
 */
private struct TalkingCircle: View {
    let game: GameController
    let compact: Bool
    let onTap: @MainActor () -> Void
    /// When the pulse started: it runs all along, and shows only while the game speaks.
    @State private var start = Date()
    @Environment(\.epicReduceMotion) private var reduceMotion
    @Environment(\.epicColors) private var c

    var body: some View {
        VStack(spacing: 8) {
            if let action = game.circleAction {
                // What a tap does is decided as it's tapped. Waiting for the question, it's off.
                Button(action: onTap) { picture(action) }
                    .buttonStyle(Unpressed())
                    .hoverEffect()
                    .disabled(!action.enabled)
                    .accessibilityLabel(action.label)
                    .accessibilityValue(action.state)
                    // VoiceOver says nothing after the tap: the voice is cut short, or the mic opens.
                    .accessibilityAddTraits(.startsMediaSession)
                    .accessibilityInputLabels(A11y.inputLabels(action.label, "Skip", "Talk", "Picture"))
                    // At the largest text sizes a long press shows its name, large.
                    .accessibilityShowsLargeContentViewer { Text(action.label) }
                    .accessibilityIdentifier("talking-circle")
                    // VoiceOver on the one button as the game opens (once per game: its key is the game).
                    .focusOnAppear(ObjectIdentifier(game))
            } else {
                picture(nil)
                    .accessibilityHidden(true)
            }
            // Not announced: the game says what matters, and the mic must never hear VoiceOver.
            Text(status)
                .epicFont(.label)
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .readableWidth(alignment: .center)
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    /// The cover in its ring (pulsing together while the game speaks), the badge over them.
    private func picture(_ action: CircleAction?) -> some View {
        let size: CGFloat = compact ? 88 : 128
        let ring = ringOf(action)
        let pulsing = game.speaking && !game.paused && !reduceMotion
        let width = ringWidth(dashed: ring.dashed)
        return ZStack {
            TimelineView(.animation(paused: !pulsing)) { context in
                let scale = pulsing ? Pulse.scale(context.date.timeIntervalSince(start)) : 1
                ZStack {
                    cover
                        .frame(width: size - 16, height: size - 16)
                        .clipShape(Circle())
                    Circle()
                        .strokeBorder(ring.color, style: StrokeStyle(lineWidth: width, dash: ring.dashed ? [9, 6] : []))
                }
                .frame(width: size, height: size)
                .scaleEffect(scale)
            }
            if let badge = badgeOf(action) {
                let round: CGFloat = compact ? 36 : 44
                IconView(icon: badge, size: compact ? 20 : 26, color: ring.color)
                    .frame(width: round, height: round)
                    .background(c.background, in: Circle())
                    .overlay { Circle().strokeBorder(ring.color, lineWidth: 2) }
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }

    @ViewBuilder private var cover: some View {
        if let image = Covers.image(game.info.id) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            c.surface
        }
    }

    /// The ring: its colour, and whether it's the dashed one (waiting for the player, or paused).
    private func ringOf(_ action: CircleAction?) -> (color: Color, dashed: Bool) {
        guard action != nil else { return (c.ringIdle, false) }        // an end: just a picture
        if game.paused { return (c.ringIdle, true) }
        if game.speaking { return (c.ringSpeaking, false) }
        if game.listening { return (c.ringListening, false) }
        return (c.ringIdle, true)
    }

    /// Listening, as thick as the voice it hears (a steady 10 with Reduce Motion); else 4, or 3 dashed.
    private func ringWidth(dashed: Bool) -> CGFloat {
        guard game.listening && !game.paused else { return dashed ? 3 : 4 }
        return reduceMotion ? 10 : 4 + 10 * CGFloat(game.level)
    }

    /// The badge: what a tap does, as an icon (its words are the circle's name).
    private func badgeOf(_ action: CircleAction?) -> MaterialIcon? {
        switch action {
        case .carryOn: return MaterialIcon.playArrow
        case .skip: return MaterialIcon.skipNext
        case .stopListening: return MaterialIcon.mic
        case .talk: return MaterialIcon.micOutlined
        case .micRefused, .noRecognition: return MaterialIcon.micOffOutlined
        case .wait: return MaterialIcon.hourglassEmpty
        case nil: return nil
        }
    }

    private var status: String {
        if game.paused { return "Paused" }
        if game.listening && !game.partial.isEmpty { return "“\(game.partial)”" }
        if game.listening { return "Listening…" }
        if game.speaking { return "Tap the picture to skip" }
        if game.end != nil { return "" }
        if game.ask != nil {
            return game.micAllowed && game.micWorks ? "Your turn! Tap the mic to talk" : "Your turn!"
        }
        return ""
    }
}

/// A button drawn just as its label is, with no pressed look: the circle (Compose's clickable with no indication).
private struct Unpressed: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Compose's pulse: 1 to 1.06 over 480 ms and back (FastOutSlowInEasing, cubic 0.4, 0, 0.2, 1), for ever.
enum Pulse {
    static let half = 0.48

    static func scale(_ seconds: Double) -> CGFloat {
        let t = max(seconds, 0).truncatingRemainder(dividingBy: 2 * half)
        let u = t < half ? t / half : 1 - (t - half) / half
        return 1 + 0.06 * CGFloat(ease(u))
    }

    /// The cubic Bézier (0.4, 0, 0.2, 1) at time [x]: its y, solving x(s) = [x] for s.
    static func ease(_ x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func bezier(_ a: Double, _ b: Double, _ s: Double) -> Double {
            3 * a * s * (1 - s) * (1 - s) + 3 * b * s * s * (1 - s) + s * s * s
        }
        var low = 0.0
        var high = 1.0
        var s = x
        for _ in 0..<30 {
            s = (low + high) / 2
            if bezier(0.4, 0.2, s) < x { low = s } else { high = s }
        }
        return bezier(0, 1, s)
    }
}

/**
 * Everything waits for the player, over the game hidden by the scrim (solid: words showing through are hard to read):
 * carry on, how to play (the help sheet, [onHelp]), or leave the game (its place is kept, as with Back). A tap anywhere
 * else carries on too, for a finger only: VoiceOver stays in the pause (it's modal), moves to its heading as it
 * appears, and has the buttons; Magic Tap carries on. It covers the header too, as Android's does. GameScreen.kt's
 * Paused.
 */
private struct PausedOverlay: View {
    let game: GameController
    let onHelp: @MainActor () -> Void
    /// VoiceOver is on: its double tap on the heading is a tap there, which mustn't carry on (see the tap below).
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.epicColors) private var c

    var body: some View {
        ZStack {
            c.scrim
                .ignoresSafeArea()
            // With the largest text, the buttons scroll.
            ViewThatFits(in: .vertical) {
                choices
                ScrollView(.vertical) { choices }
                    .scrollBounceBehavior(.basedOnSize)
                    .scrollIndicators(.hidden)
            }
        }
        // A finger anywhere but the buttons carries on (the buttons take their own taps). VoiceOver isn't offered it:
        // it has Carry on, and Magic Tap. Its double tap on the Paused heading, which has no action, comes here as a
        // tap at the heading: that doesn't carry on (TalkBack's double tap there does nothing either).
        .contentShape(Rectangle())
        .onTapGesture { if !voiceOver { game.carryOn() } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.magicTap) { game.carryOn() }
        .accessibilityIdentifier("paused")
    }

    private var choices: some View {
        VStack(spacing: 14) {
            PaneHeading(text: "Paused", key: "paused")
            EpicButton("Carry on", icon: .playArrow, wide: true) { game.carryOn() }
                .accessibilityIdentifier("paused-carry-on")
            // The help sheet, over the pause: the game stays paused for it.
            EpicButton("How to play", kind: .secondary, wide: true, action: onHelp)
                .accessibilityIdentifier("paused-help")
            EpicButton("Leave game", kind: .secondary, wide: true) { game.leave() }
                .accessibilityIdentifier("paused-leave")
        }
        .padding(24)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }
}

/**
 * The heading of a pane over the game (the end panel, the pause), in the headline style: a level-2 heading under the
 * game's title, as the store sheet's is (docs/DESIGN.md › Everywhere › Headings), which VoiceOver moves to a moment
 * after the pane appears ([A11y.focusDelay]), and again for a new [key] (› Focus). GameScreen.kt's end and pause
 * headings, with their focusOnAppear.
 */
struct PaneHeading<Key: Equatable>: View {
    let text: String
    let key: Key
    @Environment(\.epicColors) private var c

    var body: some View {
        Text(text)
            .epicFont(.headline)
            .foregroundStyle(c.heading)
            .multilineTextAlignment(.center)
            .accessibilityAddTraits(.isHeader)
            .accessibilityHeading(.h2)
            .focusOnAppear(key)
    }
}
