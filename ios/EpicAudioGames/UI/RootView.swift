// MainActivity.kt's App (lines 119-139): the game list, or the game being played, and the store sheet over either.

import EpicAppCore
import SwiftUI
import UIKit

struct RootView: View {
    let model: AppModel
    #if DEBUG
    @State private var lab = false
    #endif

    var body: some View {
        ZStack {
            // While a game loads (or loads again, with a pack), what's under the spinner waits.
            Group {
                if let game = model.game {
                    GameView(game: game, onStore: { model.showStore(game.info) })
                } else {
                    home
                }
            }
            .accessibilityHidden(model.opening != nil)
            if model.opening != nil {
                LoadingOverlay()
            }
        }
        .sheet(item: Binding(get: { model.storeFor }, set: { if $0 == nil { model.showStore(nil) } })) { game in
            StoreSheet(game: game, store: model.store)
        }
        .alert(
            "Sorry!",
            isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } }),
            actions: { Button("OK") { model.notice = nil } },
            message: { Text(model.notice ?? "") }
        )
        // The screen stays on while a game plays (Android's keepScreenOn); not while it's paused or at its end.
        .onChange(of: playing, initial: true) { _, playing in
            UIApplication.shared.isIdleTimerDisabled = playing
        }
        #if DEBUG
        .fullScreenCover(isPresented: $lab) { AudioLabView(model: model) }
        .task {
            lab = UserDefaults.standard.bool(forKey: "EpicLab")
            await DebugLaunch.run(model)
        }
        #endif
    }

    /// A game open, and neither paused nor at its end.
    private var playing: Bool {
        guard let game = model.game else { return false }
        return !game.paused && game.end == nil
    }

    /// The list: drawn again on the way back from a game and when a pack is installed (MainActivity.kt's
    /// key(visits, installs)), scrolled as it was.
    private var home: some View {
        let scroll = Binding(get: { model.homeScroll }, set: { model.homeScroll = $0 })
        #if DEBUG
        return HomeView(
            games: model.games, continuing: model.continuing, installs: model.store.installs,
            installed: model.packs.isInstalled, scroll: scroll, onOpen: { model.open($0) },
            onStore: model.showStore, onLab: { lab = true })
        #else
        return HomeView(
            games: model.games, continuing: model.continuing, installs: model.store.installs,
            installed: model.packs.isInstalled, scroll: scroll, onOpen: { model.open($0) },
            onStore: model.showStore)
        #endif
    }
}
