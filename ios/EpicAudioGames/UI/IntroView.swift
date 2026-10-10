// ui/IntroScreen.kt: the intro, which takes over from the launch screen with its emblem in the same place, then the
// circle round it and the wordmark.

import SwiftUI

/**
 * The intro (docs/DESIGN.md › Intro): it takes over from the launch screen (Info.plist's UILaunchScreen: navy, the
 * LaunchLogo emblem in the middle of the screen, whatever its safe area) with the emblem in exactly the same place and
 * size, then the circle round it and the "Epic Audio Games" wordmark fade in (at once with Reduce Motion). Navy in
 * every theme, the status bar's icons light over it (RootView has the window dark while it shows). The sting is the
 * model's (AppModel.startIntro: it starts as this appears, or a moment later with VoiceOver on).
 *
 * The whole screen is one element for VoiceOver, "Epic Audio Games", whose action is "Skip intro" ([onSkip]); a tap
 * anywhere, Magic Tap, VoiceOver's escape, and Escape or Space on a keyboard skip it too. Android's IntroScreen.kt.
 */
struct IntroView: View {
    let onSkip: @MainActor () -> Void
    /// The circle and the wordmark showing (they fade in as it appears).
    @State private var shown = false
    @Environment(\.epicReduceMotion) private var reduceMotion

    /// The launch screen's emblem (Assets.xcassets' LaunchLogo, 160 pt), drawn at its own size: it stays put.
    static let emblem: CGFloat = 160
    /// The circle round it, half as wide again (Android's is 192 dp round its 128 dp emblem).
    static let circle: CGFloat = 240

    var body: some View {
        let c = EpicColors.dark
        GeometryReader { geometry in
            IntroLayout(bottomInset: geometry.safeAreaInsets.bottom) {
                Circle()
                    .fill(c.surface)
                    .frame(width: Self.circle, height: Self.circle)
                    .opacity(shown ? 1 : 0)
                Image("LaunchLogo")
                    .frame(width: Self.emblem, height: Self.emblem)
                Text("Epic Audio Games")
                    .epicFont(.display)
                    .foregroundStyle(c.text)
                    .multilineTextAlignment(.center)
                    .opacity(shown ? 1 : 0)
            }
        }
        // The launch screen's image is in the middle of the whole screen (UIImageRespectsSafeAreaInsets false).
        .ignoresSafeArea()
        .background(c.background)
        .contentShape(Rectangle())
        .onTapGesture { onSkip() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Epic Audio Games")
        .accessibilityAction { onSkip() }
        .accessibilityAction(named: "Skip intro") { onSkip() }
        .accessibilityAction(.magicTap) { onSkip() }
        .accessibilityAction(.escape) { onSkip() }
        .accessibilityIdentifier("intro")
        .background {
            ZStack {
                ShortcutKey(title: "Skip intro", key: .escape, action: onSkip)
                ShortcutKey(title: "Skip intro", key: .space, action: onSkip)
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: IntroTimes.fadeIn)) { shown = true }
        }
    }
}

/**
 * The intro's three, in order: the circle, the emblem and the wordmark. The emblem is in the middle of the window, as
 * the launch screen has it, the circle round it and the wordmark under that. Without room for the wordmark under the
 * circle (a short window, very large text), all three move up as far as they need, the circle's top at most to the
 * window's. IntroScreen.kt's Layout.
 */
private struct IntroLayout: Layout {
    /// The room at the foot of the window that the wordmark keeps clear of (the home indicator's).
    let bottomInset: CGFloat

    private static let gap: CGFloat = 24
    private static let side: CGFloat = 24

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let circle = subviews[0].sizeThatFits(.unspecified)
        let emblem = subviews[1].sizeThatFits(.unspecified)
        let width = max(bounds.width - 2 * Self.side, 0)
        let wordmark = subviews[2].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let middle = bounds.midY
        let overflow = middle + circle.height / 2 + Self.gap + wordmark.height - (bounds.maxY - bottomInset)
        let up = min(max(overflow, 0), max(middle - circle.height / 2 - bounds.minY, 0))
        let centre = CGPoint(x: bounds.midX, y: middle - up)
        subviews[0].place(at: centre, anchor: .center, proposal: ProposedViewSize(circle))
        subviews[1].place(at: centre, anchor: .center, proposal: ProposedViewSize(emblem))
        subviews[2].place(
            at: CGPoint(x: bounds.midX, y: middle + circle.height / 2 + Self.gap - up), anchor: .top,
            proposal: ProposedViewSize(width: width, height: wordmark.height))
    }
}
