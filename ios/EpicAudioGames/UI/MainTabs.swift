// ui/MainTabs.kt: the app's four tabs (Games, Shop, Help, Settings) in the system's tab bar, and ⌘1 to ⌘4.

import SwiftUI

/**
 * The app's four places, in the tab bar's order (docs/DESIGN.md › Structure): Games, Shop, Help and Settings. [key] is
 * the name the usage data gives it (web/analytics/events.json's tab_view), and its test identifier's ("tab-shop").
 * Android's Tab (MainTabs.kt); AppTab here, as SwiftUI has a Tab of its own from iOS 18.
 */
nonisolated enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case games, shop, help, settings

    var id: Self { self }

    var key: String { rawValue }

    var title: String {
        switch self {
        case .games: "Games"
        case .shop: "Shop"
        case .help: "Help"
        case .settings: "Settings"
        }
    }

    /// Its SF Symbol (docs/DESIGN.md › Tab bar): filled for the tab showing, outlined for the others (MainTabs).
    var symbol: String {
        switch self {
        case .games: "headphones"
        case .shop: "bag"
        case .help: "questionmark.circle"
        case .settings: "gearshape"
        }
    }

    /// Its place in the bar, 1 to 4: with ⌘, the keyboard's way to it (⌘2 is the Shop).
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
}

/**
 * The tabs (docs/DESIGN.md › Tab bar, and › Tablets…): the [selected] tab's [content], in the system's tab bar: along
 * the bottom on an iPhone, and at the top on an iPad from iPadOS 18 (the bottom before). VoiceOver hears each as a tab
 * with its place ("Shop, tab, 2 of 4"), and at the largest text sizes a long press shows its name large (the Large
 * Content Viewer). The tab showing has its filled symbol and the others outlined, so which one it is isn't colour
 * alone; the bar is the raised surface. A game is shown instead of all of this, full screen (RootView).
 *
 * ⌘ with 1 to 4 picks a tab ([keys]: not while something is over the tabs, the store sheet or an alert). A tab picked
 * by hand keeps VoiceOver on the tab. Each tab's content starts with its own level-1 heading. Android's MainTabs.kt.
 */
struct MainTabs<Content: View>: View {
    let selected: AppTab
    let onSelect: @MainActor (AppTab) -> Void
    var keys = true
    @ViewBuilder let content: (AppTab) -> Content
    @Environment(\.epicColors) private var c

    var body: some View {
        TabView(selection: Binding(get: { selected }, set: { onSelect($0) })) {
            ForEach(AppTab.allCases) { tab in
                content(tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.symbol)
                            .environment(\.symbolVariants, tab == selected ? .fill : .none)
                            .accessibilityIdentifier("tab-\(tab.key)")
                    }
                    .tag(tab)
                    // The bar in the raised surface, whatever's under it (as Android's): the contrast palettes'
                    // surfaces are the background's colour, and the system draws its edge.
                    .toolbarBackground(c.surfaceRaised, for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)
            }
        }
        .background {
            ZStack {
                ForEach(AppTab.allCases) { tab in
                    ShortcutKey(
                        title: tab.title, key: KeyEquivalent(Character(String(tab.number))), modifiers: .command,
                        enabled: keys
                    ) {
                        onSelect(tab)
                    }
                }
            }
        }
    }
}
