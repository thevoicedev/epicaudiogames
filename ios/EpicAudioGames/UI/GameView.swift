// ui/GameScreen.kt (lines 86-179 and 381-398): the game screen, its talking circle, and the pause.

import EpicAppCore
import SwiftUI
import UIKit

/**
 * The game: the talking circle (the game's picture, pulsing while it speaks, ringed while it listens), the
 * transcript as it's spoken with the question's options at its end, and the bar to answer: typing and the mic. At an
 * end, the end panel.
 *
 * VoiceOver: Magic Tap skips the voice, carries on after a pause, or starts and stops listening; Escape (the two
 * finger scrub) leaves the game. The header and the circle stop growing at the second accessibility text size.
 */
struct GameView: View {
    let game: GameController
    let onStore: () -> Void
    /// The mic tapped with the mic refused: the alert leading to Settings.
    @State private var micOff = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HeaderBar(game.info.title, onBack: game.leave) {
                    Menu {
                        Button("Start again") { game.startAgain() }
                        if !game.info.packs.isEmpty {
                            Button("More stories and levels", action: onStore)
                        }
                        // The website's help and privacy pages (the stores want both reachable in the app), in Safari.
                        Button("Help") { openURL(WebPages.help) }
                        Button("Privacy policy") { openURL(WebPages.privacy) }
                    } label: {
                        IconView(icon: .moreVert)
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("More")
                }
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .fixedSize(horizontal: false, vertical: true)
                TalkingCircle(game: game)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .fixedSize(horizontal: false, vertical: true)
                FeedView(game: game)
                    .frame(maxHeight: .infinity)
                // The end panel gets its room first (Compose measures it before the weighted feed); short of it, it
                // scrolls. The header and the circle keep theirs.
                if game.end != nil {
                    EndPanel(game: game, onStore: onStore)
                        .layoutPriority(1)
                } else {
                    AnswersPanel(game: game, onTalk: talk)
                        .layoutPriority(1)
                }
            }
            // Paused, VoiceOver finds only the pause (its carry on, and its back arrow).
            .accessibilityHidden(game.paused)
            if game.paused {
                PausedOverlay(game: game)
            }
        }
        .background { Backdrop().ignoresSafeArea(.keyboard) }
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

    /// The mic button: listen (or stop). Not allowed, it asks for the mic while iOS still can, and else says it's off.
    private func talk() {
        if game.micAllowed {
            game.mic()
        } else if MicPermission.canAsk {
            Task {
                guard await MicPermission.request() else { return }
                game.allowMic()
                game.listen()       // asked for: it listens even where it wouldn't by itself (VoiceOver, D8)
            }
        } else {
            micOff = true
        }
    }

    /// VoiceOver's Magic Tap (two fingers, twice): carry on, skip the voice, or start or stop listening.
    private func magicTap() {
        if game.paused {
            game.carryOn()
        } else if game.speaking {
            game.skip()
        } else if game.end == nil {
            talk()
        }
    }
}

/**
 * The game's picture: it pulses while the game speaks (not with Reduce Motion), and is ringed while it listens.
 * Tapping it skips the voice, or starts or stops listening.
 */
private struct TalkingCircle: View {
    let game: GameController
    /// When the pulse started: it runs all along, and shows only while the game speaks.
    @State private var start = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            let pulsing = game.speaking && !reduceMotion
            TimelineView(.animation(paused: !pulsing)) { context in
                let scale = pulsing ? Pulse.scale(context.date.timeIntervalSince(start)) : 1
                ZStack {
                    Circle()
                        .strokeBorder(ring, lineWidth: ringWidth)
                        .frame(width: 146, height: 146)
                        .scaleEffect(scale)
                    if let cover = Covers.image(game.info.id) {
                        Image(uiImage: cover)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 126, height: 126)
                            .clipShape(Circle())
                            .scaleEffect(scale)
                    }
                }
                .frame(width: 146, height: 146)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: tap)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(game.speaking ? "Skip" : game.listening ? "Stop listening" : "Talk")
            .accessibilityAddTraits([.isButton, .startsMediaSession])
            .accessibilityAction { tap() }
            .accessibilityIdentifier("talking-circle")
            Spacer().frame(height: 8)
            OutlinedText(status, size: 18, maxLines: 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    private func tap() {
        if game.speaking { game.skip() } else { game.mic() }
    }

    private var ring: Color {
        if game.listening { return Palette.listen }
        if game.speaking { return Palette.gold }
        return Color.white.opacity(0.7)
    }

    private var ringWidth: CGFloat { game.listening ? 4 + 10 * CGFloat(game.level) : 4 }

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
 * Everything waits for a tap: the dimmed screen and its play button. It covers the header too, as Android's does;
 * there, the system Back button still leaves the game. iOS has none, so the dimmed back arrow still works.
 */
private struct PausedOverlay: View {
    let game: GameController

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                IconView(icon: .playArrow, size: 64)
                    .frame(width: 96, height: 96)
                    .background(Palette.yes, in: Circle())
                    .accessibilityElement()
                    .accessibilityLabel("Carry on")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { game.carryOn() }
                Spacer().frame(height: 14)
                OutlinedText("Tap to carry on", size: 24)
                    .accessibilityHidden(true)      // the button says it
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            // Where the header's back arrow is, under the dimming.
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Button(action: game.leave) {
                        Color.clear
                            .frame(width: 48, height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(height: 60)
                Spacer(minLength: 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { game.carryOn() }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("paused")
    }
}

/// The website's pages the game menu opens (GameScreen.kt's HELP_URL and PRIVACY_URL).
private enum WebPages {
    static let help = URL(string: "https://epicaudiogames.com/support")!
    static let privacy = URL(string: "https://epicaudiogames.com/privacy")!
}
