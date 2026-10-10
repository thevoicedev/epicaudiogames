// MainActivity.kt's MainActivity: the app's one window, and whether it's on screen.

import SwiftUI

@main
struct EpicAudioGamesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        // From the phase the app starts in too, so a launch straight to active is seen (the usage data's app_open).
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Leaving the app or locking the phone doesn't pause the game: it plays and listens on (UIBackgroundModes
            // audio; AppModel.onScreen). A game that loads meanwhile waits until the app is back. A permission alert
            // makes the app inactive for a moment; the store sheet pauses the game itself (AppModel.showStore).
            switch phase {
            case .background:
                model.onScreen(false)
            case .active:
                model.onScreen(true)
            default:
                break
            }
        }
    }
}
