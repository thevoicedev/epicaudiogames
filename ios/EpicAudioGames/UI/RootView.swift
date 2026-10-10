// MainActivity.kt's App (App, Screens and TabScreen): the way in (the intro, onboarding), then the tabs, or the game
// being played instead of them, and the store sheet over either and the help sheet over the game, in the player's theme.

import EpicAppCore
import SwiftUI
import UIKit

struct RootView: View {
    let model: AppModel
    #if DEBUG
    @State private var lab = false
    #endif
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        ZStack {
            if model.intro {
                // After the launch screen, once per process (docs/DESIGN.md › Intro).
                IntroView(onSkip: model.skipIntro)
                    .onAppear { model.startIntro() }
            } else if model.onboarding {
                // The first run, or opened again from Help or Settings (docs/DESIGN.md › Onboarding).
                OnboardingView(
                    settings: model.settings, manifest: model.appAudio.manifest, audio: model.appAudio,
                    reopened: model.onboardingFrom != nil, screenReader: screenReader,
                    onMicAnswer: model.onboardingMicAnswered, onDone: model.onboardingDone)
            } else {
                // While a game loads (or loads again, with a pack), what's under the spinner waits.
                Group {
                    if let game = model.game {
                        // The game's keys are off while a sheet is over it (each sheet has its own Escape).
                        GameView(
                            game: game, keys: model.storeFor == nil && !model.helpSheet, onHelp: model.openHelpSheet
                        ) { from in
                            model.showStore(game.info, from: from)
                        }
                    } else {
                        MainTabs(
                            selected: model.tab, onSelect: model.select,
                            keys: model.storeFor == nil && model.notice == nil
                        ) { tab in
                            screen(tab)
                        }
                    }
                }
                .accessibilityHidden(model.opening != nil)
                if let opening = model.opening {
                    LoadingOverlay(title: opening.title)
                }
            }
        }
        // The window's width and shape, for the layouts that change with them (docs/DESIGN.md › Tablets…).
        .measuresWindow()
        // The player's theme (Settings › Appearance and the phone's own settings), for everything under it; the window
        // dark under the intro, which is navy in every theme.
        .epicTheme(model.settings, darkWindow: model.intro)
        .sheet(item: Binding(get: { model.storeFor }, set: { if $0 == nil { model.showStore(nil) } })) { game in
            // A sheet is presented on its own: the theme is given to it again.
            StoreSheet(game: game, store: model.store, installed: model.packs.isInstalled)
                .epicTheme(model.settings)
        }
        .sheet(isPresented: Binding(
            get: { model.helpSheet && model.game != nil }, set: { if !$0 { model.closeHelpSheet() } }
        )) {
            HelpSheet(
                pages: model.helpPages, audio: model.appAudio, topic: model.helpSheetTopic,
                onTopic: model.showSheetTopic)
                .epicTheme(model.settings)
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

    /// VoiceOver is on, for onboarding (its page, the welcome waiting for Listen); in a Debug build -EpicVoiceOver YES
    /// too, so a UI test can see those pages (DebugLaunch).
    private var screenReader: Bool {
        #if DEBUG
        if DebugLaunch.screenReader { return true }
        #endif
        return voiceOver
    }

    /// A tab's screen, on the model's state (MainActivity.kt's TabScreen).
    @ViewBuilder private func screen(_ tab: AppTab) -> some View {
        switch tab {
        case .games:
            home
        case .shop:
            ShopView(
                games: model.games, store: model.store, installed: model.packs.isInstalled,
                speaks: model.tab == .shop && model.storeFor == nil, onShown: model.shopShown)
        case .help:
            HelpView(
                pages: model.helpPages, audio: model.appAudio, topic: model.helpTopic, onTopic: model.showTopic,
                onShowWelcome: model.showWelcome, focusTopic: model.focusHelpTopic,
                onTopicFocused: model.helpTopicFocused)
        case .settings:
            SettingsView(
                settings: model.settings, onPlaySample: model.playSample, onHowToPlay: model.howToPlay,
                onShowWelcome: model.showWelcome, onDeleteUsageData: model.deleteUsageData,
                onMicAnswer: model.micAnswered, onPreviewCue: model.previewCue, onPreviewIntro: model.previewIntro,
                onPreviewMusic: model.previewMusic)
        }
    }

    /// The list: drawn again on the way back from a game and when a pack is installed (MainActivity.kt's
    /// key(visits, installs)), scrolled as it was; VoiceOver on its heading after the intro or onboarding.
    private var home: some View {
        let scroll = Binding(get: { model.homeScroll }, set: { model.homeScroll = $0 })
        #if DEBUG
        return HomeView(
            games: model.games, continuing: model.continuing, installs: model.store.installs,
            installed: model.packs.isInstalled, scroll: scroll, onOpen: { model.open($0) },
            onStore: { model.showStore($0, from: .card) }, focusHeading: model.focusGames,
            onHeadingFocused: model.gamesFocused, onLab: { lab = true })
        #else
        return HomeView(
            games: model.games, continuing: model.continuing, installs: model.store.installs,
            installed: model.packs.isInstalled, scroll: scroll, onOpen: { model.open($0) },
            onStore: { model.showStore($0, from: .card) }, focusHeading: model.focusGames,
            onHeadingFocused: model.gamesFocused)
        #endif
    }
}
