// The Apple Watch app (docs/WATCH.md; docs/DESIGN.md › Watches): a remote for the game on the iPhone, which plays the
// audio and listens. Android's is the Wear OS app in android/wear.

import SwiftUI

/// The watch app's one screen, the game on the iPhone and its two buttons (WatchView), with the iPhone at the other end
/// of WatchConnectivity (PhoneLink).
@main
struct EpicWatchApp: App {
    @State private var phone = PhoneLink()

    var body: some Scene {
        WindowGroup {
            WatchView(phone: phone)
                // The session starts with the app: the iPhone's latest state shows as soon as it's up.
                .task { phone.start() }
        }
    }
}
