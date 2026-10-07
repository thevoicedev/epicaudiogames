// MainActivity.kt's MainActivity: the app's one window, and leaving the app pausing the game.

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
        .onChange(of: scenePhase) { _, phase in
            // Leaving the app pauses the game; a game that loads meanwhile waits until the app is back. A
            // permission alert makes the app inactive for a moment, and the game plays on; the store sheet pauses the
            // game itself (AppModel.showStore).
            switch phase {
            case .background:
                model.pause()
                model.onScreen(false)
            case .active:
                model.onScreen(true)
            default:
                break
            }
        }
    }
}
