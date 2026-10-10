// The Apple Watch app's one screen (docs/DESIGN.md › Watches): the game on the iPhone, its big button and Pause. The
// iPhone's own one button is the talking circle (UI/GameView.swift); Android's watch screen is the Wear OS app's.

import SwiftUI

/**
 * The game on the iPhone (PhoneLink): its title, a heading; what it's doing, in words; the big button, named as on the
 * iPhone (the talking circle's CircleAction: "Skip", "Talk", "Stop listening", "Carry on"), which does what tapping the
 * picture does; and Pause, while there's something to pause. At an end, nothing to press: what's next is chosen on the
 * iPhone, and the watch says so. With no game open on the iPhone: "Open a game on your iPhone".
 *
 * The watch's text styles, so the type follows its text size and Bold Text (it wraps, never cut short, and the page
 * scrolls); the app's dark colours, or with the watch asking for more contrast its black, white and yellow
 * (WatchColors); each state in words, the big button's in an icon too, never by colour alone. VoiceOver reads the title
 * as a heading, the state, then the buttons; Magic Tap (two fingers, twice) is the big button, and so is the double-tap
 * gesture on the watches that have it (watchOS 11).
 */
struct WatchView: View {
    let phone: PhoneLink
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let c = WatchColors.of(contrast)
        let state = phone.state
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if state.gameOpen {
                        game(state, c)
                    } else {
                        noGame(c)
                    }
                    if let trouble = phone.trouble {
                        troubleLine(trouble, c)
                    }
                }
                .padding(.horizontal, 2)
            }
            .containerBackground(c.background, for: .navigation)
        }
        // Magic Tap, wherever VoiceOver is: the big button, when it can do something.
        .accessibilityAction(.magicTap) {
            if state.gameOpen && state.enabled { phone.press(.primary) }
        }
    }

    @ViewBuilder private func game(_ state: WatchState, _ c: WatchColors) -> some View {
        Text(state.title)
            .font(.headline)
            .foregroundStyle(c.heading)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("watch-title")
        Text(state.state)
            .font(.title3.bold())
            .foregroundStyle(c.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("watch-state")
        if state.label.isEmpty {
            // At an end there's nothing to press here: the iPhone's end panel has Next chapter, Play again and Back to
            // games.
            Text("Choose what's next on your iPhone.")
                .font(.body)
                .foregroundStyle(c.textMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("watch-end-hint")
        } else {
            Button {
                phone.press(.primary)
            } label: {
                VStack(spacing: 4) {
                    if let icon = Self.icon(state.action) {
                        Image(systemName: icon)
                            .font(.title2)
                            .accessibilityHidden(true)
                    }
                    Text(state.label)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(WatchButtonStyle(filled: true, c: c))
            .disabled(!state.enabled)
            .accessibilityLabel(state.label)
            .accessibilityIdentifier("watch-primary")
            .primaryHandGesture()
        }
        // Paused, or at an end, there's nothing to pause: the big button carries on (or the iPhone's end panel has
        // what's next).
        if state.canPause {
            Button {
                phone.press(.pause)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pause.fill")
                        .accessibilityHidden(true)
                    Text("Pause")
                }
                .font(.headline)
            }
            .buttonStyle(WatchButtonStyle(filled: false, c: c))
            .accessibilityLabel("Pause")
            .accessibilityIdentifier("watch-pause")
        }
    }

    private func noGame(_ c: WatchColors) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone")
                .font(.title2)
                .foregroundStyle(c.heading)
                .accessibilityHidden(true)
            Text("Open a game on your iPhone")
                .font(.title3)
                .foregroundStyle(c.text)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("watch-no-game")
        }
        .padding(.top, 8)
    }

    /// A press that couldn't reach the iPhone: in words, with an icon (the watch buzzed a failure as it happened, and
    /// VoiceOver said these words: PhoneLink.couldntReach).
    private func troubleLine(_ trouble: String, _ c: WatchColors) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .accessibilityHidden(true)
            Text(trouble)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.body)
        .foregroundStyle(c.error)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watch-trouble")
    }

    /**
     * The big button's icon, what a press does, as the iPhone has its own (GameView.swift's circle badge and Talk
     * button): play to carry on, skip, stop, the mic to talk, the mic struck through when it can't open, an hourglass
     * while there's nothing to do yet.
     */
    static func icon(_ action: WatchAction?) -> String? {
        switch action {
        case .carryOn: "play.fill"
        case .skip: "forward.end.fill"
        case .stopListening: "stop.fill"
        case .talk: "mic.fill"
        case .micRefused, .noRecognition: "mic.slash.fill"
        case .wait: "hourglass"
        case nil: nil
        }
    }
}

private extension View {
    /// The double tap (finger and thumb, twice) presses it, on the watches that have the gesture (watchOS 11).
    @ViewBuilder func primaryHandGesture() -> some View {
        if #available(watchOS 11.0, *) {
            handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}

/**
 * The watch's buttons in the app's colours (UI/Design/Components.swift's EpicButton), as big as a watch allows: the big
 * one [filled] (primary, its words onPrimary), Pause outlined. Dimmed when it can't do anything: its words muted, no
 * fill, a faint edge (VoiceOver says "dimmed"). Always On (the wrist down) shows the big one outlined, so the screen
 * isn't left bright. Held, it's a little darker, as the iPhone's PressStyle.
 */
private struct WatchButtonStyle: ButtonStyle {
    let filled: Bool
    let c: WatchColors

    func makeBody(configuration: Configuration) -> some View {
        WatchButtonBody(configuration: configuration, filled: filled, c: c)
    }
}

private struct WatchButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let filled: Bool
    let c: WatchColors
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isLuminanceReduced) private var alwaysOn

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let solid = filled && enabled && !alwaysOn
        configuration.label
            .foregroundStyle(enabled ? (solid ? c.onPrimary : c.text) : c.textMuted)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: filled ? 80 : 48)
            .background { shape.fill(solid ? c.primary : c.surface) }
            .overlay { shape.strokeBorder(enabled ? (filled ? c.primary : c.outline) : c.outlineSubtle, lineWidth: 2) }
            .contentShape(shape)
            .brightness(configuration.isPressed ? -0.08 : 0)
    }
}

/**
 * The colours the watch uses, by their names in the iPhone's palettes (UI/Design/Tokens.swift; docs/DESIGN.md ›
 * Colour): Dark's, or High contrast's when the watch asks for more contrast, as Dark does on the iPhone. Every text
 * colour is at least 7:1 on what it's drawn on (the iPhone's ThemeContrastTests check the same pairs).
 */
nonisolated struct WatchColors: Equatable, Sendable {
    let background: Color
    let surface: Color
    let text: Color
    let textMuted: Color
    let heading: Color
    let primary: Color
    let onPrimary: Color
    let outline: Color
    let outlineSubtle: Color
    let error: Color

    static let dark = WatchColors(
        background: Color(hex: 0x0B1430), surface: Color(hex: 0x16275E), text: Color(hex: 0xF6F8FF),
        textMuted: Color(hex: 0xC9D2F0), heading: Color(hex: 0xFFD54F), primary: Color(hex: 0xFFD54F),
        onPrimary: Color(hex: 0x1A1400), outline: Color(hex: 0x8E9CCB), outlineSubtle: Color(hex: 0x2C3D7A),
        error: Color(hex: 0xFFB4AB))

    static let contrast = WatchColors(
        background: Color(hex: 0x000000), surface: Color(hex: 0x000000), text: Color(hex: 0xFFFFFF),
        textMuted: Color(hex: 0xFFFFFF), heading: Color(hex: 0xFFFF00), primary: Color(hex: 0xFFFF00),
        onPrimary: Color(hex: 0x000000), outline: Color(hex: 0xFFFFFF), outlineSubtle: Color(hex: 0xFFFFFF),
        error: Color(hex: 0xFF9E9E))

    static func of(_ contrast: ColorSchemeContrast) -> WatchColors {
        contrast == .increased ? Self.contrast : dark
    }
}

extension Color {
    /// An sRGB colour from 0xRRGGBB, as the iPhone app's (UI/Theme.swift), which the watch app doesn't have.
    nonisolated init(hex: UInt32) {
        self.init(
            .sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}
