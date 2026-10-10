// ui/Components.kt's WidthClass, windowWidthClass, gameHasTwoPanes and twoPanes: how wide the window is, and what
// fits in it (docs/DESIGN.md › Tablets, foldables, Chromebooks, Mac and Vision).

import SwiftUI

/**
 * How wide the window is: compact under 600 pt (a phone, an iPad's Slide Over or narrow Split View), medium to 839 (an
 * iPad mini or an 11-inch iPad upright, half an iPad), expanded from 840 (a 13-inch iPad, an iPad on its side, a wide
 * Mac or Stage Manager window). The window's, not the screen's, so Split View and Stage Manager get the layout that
 * fits them; and compact whenever iOS says the width is (the horizontal size class). Android's WidthClass, from
 * currentWindowAdaptiveInfo there.
 */
nonisolated enum WidthClass: Equatable, Sendable {
    case compact, medium, expanded

    /// From the window's horizontal size class (nil when there's none to say) and its width in points.
    static func of(sizeClass: UserInterfaceSizeClass?, width: CGFloat) -> WidthClass {
        if sizeClass == .compact || width < 600 { return .compact }
        return width < 840 ? .medium : .expanded
    }
}

/// The game in two panes, its transcript beside the rest: an expanded window, or a medium one on its side. A phone
/// (compact) has the one column. Android's twoPanes.
nonisolated func twoPanes(_ width: WidthClass, landscape: Bool) -> Bool {
    width == .expanded || (width == .medium && landscape)
}

/**
 * The window as the layouts see it (RootView measures it): its width class, and whether it's wider than it's tall.
 * The Games tab has two columns of cards on an expanded window; the game, two panes ([gameHasTwoPanes]). Everything
 * else stays one column at most 640 pt wide (readableWidth).
 */
nonisolated struct EpicWindow: Equatable, Sendable {
    var widthClass: WidthClass = .compact
    var landscape = false

    /// The window of [size] points, in the horizontal size class iOS gives it.
    static func of(sizeClass: UserInterfaceSizeClass?, size: CGSize) -> EpicWindow {
        EpicWindow(widthClass: .of(sizeClass: sizeClass, width: size.width), landscape: size.width > size.height)
    }

    /// The game in two panes (Android's gameHasTwoPanes).
    var gameHasTwoPanes: Bool { twoPanes(widthClass, landscape: landscape) }
}

/// The window, from RootView; a phone's, upright, until it says otherwise (previews, hosted tests).
nonisolated private struct EpicWindowKey: EnvironmentKey {
    static var defaultValue: EpicWindow { EpicWindow() }
}

extension EnvironmentValues {
    /// The window's width class and shape where a view lays out: `@Environment(\.epicWindow) private var window`.
    nonisolated var epicWindow: EpicWindow {
        get { self[EpicWindowKey.self] }
        set { self[EpicWindowKey.self] = newValue }
    }
}

extension View {
    /**
     * Measures the window this is the whole of (the app's root), for everything under it ([EnvironmentValues
     * .epicWindow]): as its content is laid out, so the first frame already has the window's layout. Its height is
     * the window's with the keyboard down: typing on an 11-inch iPad upright leaves less height than width, which
     * isn't the iPad turning (the game would change its layout under the player's typing).
     */
    func measuresWindow() -> some View {
        modifier(MeasuresWindow())
    }
}

private struct MeasuresWindow: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The height with the keyboard down, once measured (before, the window has no keyboard up).
    @State private var height: CGFloat?

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let size = CGSize(width: geometry.size.width, height: height ?? geometry.size.height)
            content
                .environment(\.epicWindow, EpicWindow.of(sizeClass: sizeClass, size: size))
                .background {
                    // As tall as the content and the keyboard under it: the same with the keyboard up or down.
                    Color.clear
                        .ignoresSafeArea(.keyboard)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                }
        }
    }
}
